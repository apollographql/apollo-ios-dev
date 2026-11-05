//! Integration tests for mock templates against AnimalKingdomAPI.
//!
//! These tests exercise the full pipeline: parse GraphQL schema -> compile -> build TypeRegistry
//! -> extract types -> render mock templates. Each test validates that the Rust mock template
//! output matches the expected Swift codegen output for real AnimalKingdomAPI schema types.
//!
//! Covers MockObjectTemplate (11 object types), MockUnionsTemplate (union types),
//! and MockInterfacesTemplate (interface types) -- 13 test cases total plus helpers.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use apollo_compiler::schema;
use graphql_compiler::adapter::TypeRegistry;
use graphql_compiler::graphql_type::GraphQLType;
use graphql_compiler::schema::{
    GraphQLInterfaceType, GraphQLNamedType, GraphQLObjectType, GraphQLUnionType,
};
use graphql_compiler::RootTypeDefinition;
use indexmap::IndexSet;
use ir::ReferencedTypes;

use apollo_codegen_lib::config::ApolloCodegenConfiguration;
use apollo_codegen_lib::templates::mock_interfaces_template::MockInterfacesTemplate;
use apollo_codegen_lib::templates::mock_object_template::MockObjectTemplate;
use apollo_codegen_lib::templates::mock_unions_template::MockUnionsTemplate;
use apollo_codegen_lib::templates::{ConfigurationContext, TemplateRenderer};

// Swift dialect of the Apollo iOS version this branch targets (`MockObjectTemplate.swift` at the
// matching upstream tag); the byte-for-byte parity harness is the source of truth.
// 2.0.0+: "public final class" / "public struct MockFields: Sendable {"
// 2.1.0+: `markTypesNonisolated` defaults to true
const MOCK_CLASS_DECL: &str = "nonisolated public final class";
const MOCK_FIELDS_DECL: &str = "public struct MockFields: Sendable {";
// 1.23.0+: convenience-initializer parameters for non-null fields get default values
const REQUIRED_PARAMS_HAVE_DEFAULTS: bool = true;

/// Convenience-initializer parameter for a non-null field.
fn required_param(name: &str, mock_type: &str, default: &str) -> String {
    if REQUIRED_PARAMS_HAVE_DEFAULTS {
        format!("{}: {} = {}", name, mock_type, default)
    } else {
        format!("{}: {}? = nil", name, mock_type)
    }
}

// The schema under test is the repository's AnimalKingdomAPI snapshot (upstream 1.15.1), which
// predates the `Query.findPet` and `adoptionDate` fields added to the upstream schema later.

// MARK: - Test Configuration

/// SPM config with testMocks enabled (swiftPackage) matching AnimalKingdomAPI test mock generation.
fn animal_kingdom_mock_config() -> ConfigurationContext {
    let config: ApolloCodegenConfiguration = serde_json::from_str(
        r#"{
        "schemaNamespace": "AnimalKingdomAPI",
        "input": {},
        "output": {
            "schemaTypes": { "path": ".", "moduleType": {"swiftPackageManager": {}} },
            "operations": {"inSchemaModule": {}},
            "testMocks": {"swiftPackage": {}}
        }
    }"#,
    )
    .unwrap();
    ConfigurationContext::new(config, None)
}

// MARK: - Pipeline Helpers

/// Resolves a path relative to the apollo-ios-dev repo root.
///
/// CARGO_MANIFEST_DIR = apollo-ios-codegen/rust/apollo-codegen-lib
/// Go up 3 levels to get to the repo root (apollo-ios-dev worktree root).
fn repo_relative_path(relative: &str) -> PathBuf {
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let repo_root = Path::new(manifest_dir)
        .parent()
        .unwrap() // rust/
        .parent()
        .unwrap() // apollo-ios-codegen/
        .parent()
        .unwrap(); // repo root
    repo_root.join(relative)
}

/// Gets the path to the AnimalKingdomAPI graphql directory.
fn animal_kingdom_graphql_dir() -> PathBuf {
    repo_relative_path("Sources/AnimalKingdomAPI/animalkingdom-graphql")
}

/// Prepends stub definitions for custom directives.
fn prepend_custom_directive_stubs(schema_sdl: &str) -> String {
    let mut stubs = Vec::new();
    if schema_sdl.contains("@oneOf") && !schema_sdl.contains("directive @oneOf") {
        stubs.push("directive @oneOf on INPUT_OBJECT");
    }
    if schema_sdl.contains("@typePolicy") && !schema_sdl.contains("directive @typePolicy") {
        stubs.push("directive @typePolicy(keyFields: String!) on OBJECT | INTERFACE");
    }
    if schema_sdl.contains("@import") && !schema_sdl.contains("directive @import") {
        stubs.push("directive @import(module: String!) on QUERY");
    }
    if stubs.is_empty() {
        schema_sdl.to_string()
    } else {
        format!("{}\n\n{}", stubs.join("\n"), schema_sdl)
    }
}

/// Parsed schema and type registry for AnimalKingdomAPI.
struct ParsedSchema {
    registry: TypeRegistry,
}

/// Parses the AnimalKingdomAPI schema and builds a TypeRegistry.
fn parse_animal_kingdom_schema() -> ParsedSchema {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let schema_sdl = std::fs::read_to_string(&schema_path)
        .unwrap_or_else(|e| panic!("Failed to read schema: {}: {}", schema_path.display(), e));
    let schema_sdl = prepend_custom_directive_stubs(&schema_sdl);

    let parsed_schema =
        schema::Schema::parse_and_validate(&schema_sdl, schema_path.to_string_lossy().as_ref())
            .unwrap_or_else(|diag| panic!("Schema validation failed:\n{}", diag.errors));

    let registry = TypeRegistry::from_schema(&parsed_schema);

    ParsedSchema { registry }
}

/// Gets an object type by name from the registry.
fn get_object_type(name: &str, registry: &TypeRegistry) -> Arc<GraphQLObjectType> {
    match registry.get(name) {
        Some(GraphQLNamedType::Object(obj)) => Arc::clone(obj),
        other => panic!(
            "Expected Object type '{}', found: {:?}",
            name,
            other.map(|t| t.name().to_string())
        ),
    }
}

/// Collects all fields from a GraphQLObjectType's schema-defined fields as tuples.
///
/// Returns Vec<(response_key, GraphQLType, Option<deprecation_reason>)>.
fn collect_schema_fields(obj: &GraphQLObjectType) -> Vec<(String, GraphQLType, Option<String>)> {
    obj.fields
        .iter()
        .map(|(name, field)| {
            (
                name.clone(),
                field.type_.clone(),
                field.deprecation_reason.clone(),
            )
        })
        .collect()
}

/// Collects all union types from the registry.
fn collect_all_unions(registry: &TypeRegistry) -> IndexSet<Arc<GraphQLUnionType>> {
    let mut unions = IndexSet::new();
    for (_name, named_type) in registry.all_types() {
        if let GraphQLNamedType::Union(u) = named_type {
            unions.insert(Arc::clone(u));
        }
    }
    unions
}

/// Collects all interface types from the registry.
fn collect_all_interfaces(registry: &TypeRegistry) -> IndexSet<Arc<GraphQLInterfaceType>> {
    let mut interfaces = IndexSet::new();
    for (_name, named_type) in registry.all_types() {
        if let GraphQLNamedType::Interface(i) = named_type {
            interfaces.insert(Arc::clone(i));
        }
    }
    interfaces
}

/// Renders a mock object template for the given object type name and returns the full output.
fn render_mock_object(name: &str, registry: &TypeRegistry) -> String {
    let obj = get_object_type(name, registry);
    let fields = collect_schema_fields(&obj);
    let config = animal_kingdom_mock_config();
    let referenced_types = Arc::new(ReferencedTypes::new(
        &[GraphQLNamedType::Object(Arc::clone(&obj))],
        RootTypeDefinition {
            query_type: GraphQLNamedType::Object(Arc::clone(&obj)),
            mutation_type: None,
            subscription_type: None,
        },
    ));
    let template = MockObjectTemplate {
        graphql_object: obj,
        fields,
        referenced_types,
        config,
    };
    template.render().body
}

// MARK: - Common Assertions

/// Validates the standard mock object file structure.
fn assert_mock_object_structure(rendered: &str, type_name: &str) {
    // Header
    assert!(
        rendered.contains("// @generated"),
        "Missing @generated header for {}",
        type_name,
    );
    assert!(
        rendered.contains("import ApolloTestSupport"),
        "Missing ApolloTestSupport import for {}",
        type_name,
    );
    assert!(
        rendered.contains("@testable import AnimalKingdomAPI"),
        "Missing @testable import for {}",
        type_name,
    );

    // Class structure -- version-specific class and MockFields declarations
    assert!(
        rendered.contains(&format!("{} {}: MockObject {{", MOCK_CLASS_DECL, type_name)),
        "Missing '{} {}' declaration in:\n{}",
        MOCK_CLASS_DECL,
        type_name,
        rendered,
    );
    assert!(
        rendered.contains(&format!(
            "public static let objectType: ApolloAPI.Object = AnimalKingdomAPI.Objects.{}",
            type_name
        )),
        "Missing objectType for {}",
        type_name,
    );
    assert!(
        rendered.contains("public static let _mockFields = MockFields()"),
        "Missing _mockFields for {}",
        type_name,
    );
    assert!(
        rendered.contains(&format!(
            "public typealias MockValueCollectionType = Array<Mock<{}>>",
            type_name
        )),
        "Missing MockValueCollectionType for {}",
        type_name,
    );
    assert!(
        rendered.contains(&format!("  {}\n", MOCK_FIELDS_DECL)),
        "Missing '{}' for {}\nRendered:\n{}",
        MOCK_FIELDS_DECL,
        type_name,
        rendered,
    );
}

// MARK: - Object Type Tests

#[test]
fn test_bird_mock() {
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Bird", &parsed.registry);

    assert_mock_object_structure(&rendered, "Bird");

    // Bird has these schema fields: id, species, height, predators, skinCovering,
    // humanName, favoriteToy, owner, adoptionDate, bodyTemperature, laysEggs, wingspan
    assert!(rendered.contains(r#"@Field<AnimalKingdomAPI.ID>("id") public var id"#));
    assert!(rendered.contains(r#"@Field<String>("species") public var species"#));
    assert!(rendered.contains(r#"@Field<Height>("height") public var height"#));
    assert!(rendered.contains(r#"@Field<String>("humanName") public var humanName"#));
    assert!(rendered.contains(r#"@Field<String>("favoriteToy") public var favoriteToy"#));
    assert!(rendered.contains(r#"@Field<Human>("owner") public var owner"#));
    assert!(rendered.contains(r#"@Field<Int>("bodyTemperature") public var bodyTemperature"#));
    assert!(rendered.contains(r#"@Field<Bool>("laysEggs") public var laysEggs"#));
    // GraphQL Float maps to Swift Double
    assert!(rendered.contains(r#"@Field<Double>("wingspan") public var wingspan"#));

    // predators is [Animal!]! -- Animal is an interface, renders without MockObject. prefix
    // (only "Actor" gets MockObject. prefix per Swift's test mock namespace rules)
    assert!(rendered.contains(r#"@Field<[Animal]>("predators") public var predators"#));

    // Should have convenience initializer extension
    assert!(rendered.contains("public extension Mock where O == Bird {"));
    assert!(rendered.contains("convenience init("));
    assert!(rendered.contains("self.init()"));
}

#[test]
fn test_cat_mock() {
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Cat", &parsed.registry);

    assert_mock_object_structure(&rendered, "Cat");

    // Cat fields from schema
    assert!(rendered.contains(r#"@Field<AnimalKingdomAPI.ID>("id") public var id"#));
    assert!(rendered.contains(r#"@Field<String>("species") public var species"#));
    assert!(rendered.contains(r#"@Field<Height>("height") public var height"#));
    assert!(rendered.contains(r#"@Field<String>("humanName") public var humanName"#));
    assert!(rendered.contains(r#"@Field<String>("favoriteToy") public var favoriteToy"#));
    assert!(rendered.contains(r#"@Field<Human>("owner") public var owner"#));
    assert!(rendered.contains(r#"@Field<Int>("bodyTemperature") public var bodyTemperature"#));
    assert!(rendered.contains(r#"@Field<Bool>("laysEggs") public var laysEggs"#));
    assert!(rendered.contains(r#"@Field<Bool>("isJellicle") public var isJellicle"#));

    // Convenience init
    assert!(rendered.contains("public extension Mock where O == Cat {"));
}

#[test]
fn test_dog_mock() {
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Dog", &parsed.registry);

    assert_mock_object_structure(&rendered, "Dog");

    // Dog has many fields including entity references
    assert!(rendered.contains(r#"@Field<AnimalKingdomAPI.ID>("id") public var id"#));
    assert!(rendered.contains(r#"@Field<String>("species") public var species"#));
    assert!(rendered.contains(r#"@Field<Height>("height") public var height"#));
    assert!(rendered.contains(r#"@Field<String>("humanName") public var humanName"#));
    assert!(rendered.contains(r#"@Field<String>("favoriteToy") public var favoriteToy"#));
    assert!(rendered.contains(r#"@Field<Human>("owner") public var owner"#));
    assert!(rendered.contains(r#"@Field<Int>("bodyTemperature") public var bodyTemperature"#));
    assert!(rendered.contains(r#"@Field<Bool>("laysEggs") public var laysEggs"#));

    // Entity field references: HousePet is an interface (no MockObject. prefix),
    // Cat and Bird are objects
    assert!(rendered.contains(r#"@Field<HousePet>("bestFriend") public var bestFriend"#));
    assert!(rendered.contains(r#"@Field<Cat>("rival") public var rival"#));
    assert!(rendered.contains(r#"@Field<Bird>("livesWith") public var livesWith"#));

    // Custom scalars
    assert!(rendered
        .contains(r#"@Field<AnimalKingdomAPI.CustomDate>("birthdate") public var birthdate"#));

    // houseDetails is custom scalar "Object"
    assert!(rendered
        .contains(r#"@Field<AnimalKingdomAPI.Object>("houseDetails") public var houseDetails"#));

    // Convenience init
    assert!(rendered.contains("public extension Mock where O == Dog {"));

    // Verify entity mock types in convenience init
    // height is Height! (non-null) -> default value Mock<Height>()
    assert!(
        rendered.contains(&required_param("height", "Mock<Height>", "Mock<Height>()")),
        "actual:\n{}",
        rendered
    );
    // owner is Human (nullable) -> optional
    assert!(rendered.contains("owner: Mock<Human>? = nil"));
    // bestFriend is HousePet (interface, nullable) -> (any AnyMock)?
    assert!(rendered.contains("bestFriend: (any AnyMock)? = nil"));
    // rival is Cat (nullable) -> optional
    assert!(rendered.contains("rival: Mock<Cat>? = nil"));
    // livesWith is Bird (nullable) -> optional
    assert!(rendered.contains("livesWith: Mock<Bird>? = nil"));
}

#[test]
fn test_human_mock() {
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Human", &parsed.registry);

    assert_mock_object_structure(&rendered, "Human");

    assert!(rendered.contains(r#"@Field<AnimalKingdomAPI.ID>("id") public var id"#));
    assert!(rendered.contains(r#"@Field<String>("firstName") public var firstName"#));
    assert!(rendered.contains(r#"@Field<String>("species") public var species"#));
    assert!(rendered.contains(r#"@Field<Height>("height") public var height"#));
    assert!(rendered.contains(r#"@Field<Int>("bodyTemperature") public var bodyTemperature"#));
    assert!(rendered.contains(r#"@Field<Bool>("laysEggs") public var laysEggs"#));

    // Predators is [Animal!]! -- Animal is an interface, no MockObject. prefix
    assert!(rendered.contains(r#"@Field<[Animal]>("predators") public var predators"#));

    // skinCovering is SkinCovering enum
    assert!(rendered.contains(r#"@Field<GraphQLEnum<AnimalKingdomAPI.SkinCovering>>("skinCovering") public var skinCovering"#));

    assert!(rendered.contains("public extension Mock where O == Human {"));
}

#[test]
fn test_fish_mock() {
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Fish", &parsed.registry);

    assert_mock_object_structure(&rendered, "Fish");

    assert!(rendered.contains(r#"@Field<AnimalKingdomAPI.ID>("id") public var id"#));
    assert!(rendered.contains(r#"@Field<String>("species") public var species"#));
    assert!(rendered.contains(r#"@Field<Height>("height") public var height"#));
    assert!(rendered.contains(r#"@Field<String>("humanName") public var humanName"#));
    assert!(rendered.contains(r#"@Field<String>("favoriteToy") public var favoriteToy"#));
    assert!(rendered.contains(r#"@Field<Human>("owner") public var owner"#));

    assert!(rendered.contains("public extension Mock where O == Fish {"));
}

#[test]
fn test_rat_mock() {
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Rat", &parsed.registry);

    assert_mock_object_structure(&rendered, "Rat");

    assert!(rendered.contains(r#"@Field<AnimalKingdomAPI.ID>("id") public var id"#));
    assert!(rendered.contains(r#"@Field<String>("species") public var species"#));
    assert!(rendered.contains(r#"@Field<Height>("height") public var height"#));
    assert!(rendered.contains(r#"@Field<String>("humanName") public var humanName"#));
    assert!(rendered.contains(r#"@Field<String>("favoriteToy") public var favoriteToy"#));

    assert!(rendered.contains("public extension Mock where O == Rat {"));
}

#[test]
fn test_pet_rock_mock() {
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("PetRock", &parsed.registry);

    assert_mock_object_structure(&rendered, "PetRock");

    assert!(rendered.contains(r#"@Field<AnimalKingdomAPI.ID>("id") public var id"#));
    assert!(rendered.contains(r#"@Field<String>("humanName") public var humanName"#));
    assert!(rendered.contains(r#"@Field<String>("favoriteToy") public var favoriteToy"#));
    assert!(rendered.contains(r#"@Field<Human>("owner") public var owner"#));

    assert!(rendered.contains("public extension Mock where O == PetRock {"));
}

#[test]
fn test_crocodile_mock() {
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Crocodile", &parsed.registry);

    assert_mock_object_structure(&rendered, "Crocodile");

    assert!(rendered.contains(r#"@Field<AnimalKingdomAPI.ID>("id") public var id"#));
    assert!(rendered.contains(r#"@Field<String>("species") public var species"#));
    assert!(rendered.contains(r#"@Field<Height>("height") public var height"#));
    assert!(rendered.contains(r#"@Field<Int>("age") public var age"#));

    // `tag` field has arguments -- should still be included in mock
    assert!(rendered.contains(r#"@Field<String>("tag") public var tag"#));

    assert!(rendered.contains("public extension Mock where O == Crocodile {"));
}

#[test]
fn test_height_mock() {
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Height", &parsed.registry);

    assert_mock_object_structure(&rendered, "Height");

    // Height type has: relativeSize, centimeters, meters, feet, inches, yards
    assert!(rendered.contains(r#"@Field<GraphQLEnum<AnimalKingdomAPI.RelativeSize>>("relativeSize") public var relativeSize"#));
    // GraphQL Float maps to Swift Double
    assert!(rendered.contains(r#"@Field<Double>("centimeters") public var centimeters"#));
    assert!(rendered.contains(r#"@Field<Int>("meters") public var meters"#));
    assert!(rendered.contains(r#"@Field<Int>("feet") public var feet"#));
    assert!(rendered.contains(r#"@Field<Int>("inches") public var inches"#));
    assert!(rendered.contains(r#"@Field<Int>("yards") public var yards"#));

    assert!(rendered.contains("public extension Mock where O == Height {"));

    // Verify default values for non-null fields in convenience init
    assert!(
        rendered.contains(&required_param("centimeters", "Double", "0.0")),
        "actual:\n{}",
        rendered
    );
    assert!(
        rendered.contains(&required_param("feet", "Int", "0")),
        "actual:\n{}",
        rendered
    );
    assert!(
        rendered.contains(&required_param("meters", "Int", "0")),
        "actual:\n{}",
        rendered
    );
    assert!(
        rendered.contains(&required_param("yards", "Int", "0")),
        "actual:\n{}",
        rendered
    );
    assert!(
        rendered.contains(&required_param(
            "relativeSize",
            "GraphQLEnum<AnimalKingdomAPI.RelativeSize>",
            ".case(.large)"
        )),
        "actual:\n{}",
        rendered
    );
    assert!(rendered.contains("inches: Int? = nil")); // nullable
}

#[test]
fn test_query_mock() {
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Query", &parsed.registry);

    assert_mock_object_structure(&rendered, "Query");

    // Query has: allAnimals, classroomPets, pets
    assert!(rendered.contains(r#""allAnimals"#));
    assert!(rendered.contains(r#""classroomPets"#));
    assert!(rendered.contains(r#""pets"#));

    assert!(rendered.contains("public extension Mock where O == Query {"));
}

#[test]
fn test_mutation_mock() {
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Mutation", &parsed.registry);

    assert_mock_object_structure(&rendered, "Mutation");

    // Mutation has: adoptPet (returns Pet! which is an interface)
    assert!(rendered.contains(r#""adoptPet"#));

    // Pet is an interface, so in convenience init it uses (any AnyMock)
    // The default value uses Mock<first implementing object>()
    assert!(rendered.contains("adoptPet: (any AnyMock)"));

    assert!(rendered.contains("public extension Mock where O == Mutation {"));
}

// MARK: - Union and Interface Tests

#[test]
fn test_mock_unions() {
    let parsed = parse_animal_kingdom_schema();
    let unions = collect_all_unions(&parsed.registry);
    let config = animal_kingdom_mock_config();

    let template = MockUnionsTemplate {
        graphql_unions: unions,
        config,
    };
    let rendered = template.render().body;

    // Header
    assert!(rendered.contains("// @generated"));
    assert!(rendered.contains("import ApolloTestSupport"));
    assert!(rendered.contains("@testable import AnimalKingdomAPI"));

    // AnimalKingdomAPI has one union: ClassroomPet
    assert!(rendered.contains("public extension MockObject {"));
    assert!(rendered.contains("typealias ClassroomPet = Union"));
}

#[test]
fn test_mock_interfaces() {
    let parsed = parse_animal_kingdom_schema();
    let interfaces = collect_all_interfaces(&parsed.registry);
    let config = animal_kingdom_mock_config();

    let template = MockInterfacesTemplate {
        graphql_interfaces: interfaces,
        config,
    };
    let rendered = template.render().body;

    // Header
    assert!(rendered.contains("// @generated"));
    assert!(rendered.contains("import ApolloTestSupport"));
    assert!(rendered.contains("@testable import AnimalKingdomAPI"));

    // AnimalKingdomAPI has 4 interfaces: Animal, Pet, HousePet, WarmBlooded
    assert!(rendered.contains("public extension MockObject {"));
    assert!(rendered.contains("typealias Animal = Interface"));
    assert!(rendered.contains("typealias Pet = Interface"));
    assert!(rendered.contains("typealias HousePet = Interface"));
    assert!(rendered.contains("typealias WarmBlooded = Interface"));
}

// MARK: - Cross-cutting validation tests

#[test]
fn test_all_object_mocks_use_expected_class_declaration() {
    let parsed = parse_animal_kingdom_schema();
    let type_names = [
        "Bird",
        "Cat",
        "Dog",
        "Human",
        "Fish",
        "Rat",
        "PetRock",
        "Crocodile",
        "Height",
        "Query",
        "Mutation",
    ];

    for name in &type_names {
        let rendered = render_mock_object(name, &parsed.registry);
        let decl = rendered
            .lines()
            .find(|line| line.contains(&format!("class {}: MockObject", name)))
            .unwrap_or_else(|| panic!("{} mock has no class declaration:\n{}", name, rendered));
        assert_eq!(decl, format!("{} {}: MockObject {{", MOCK_CLASS_DECL, name));
    }
}

#[test]
fn test_all_object_mocks_use_expected_mock_fields_declaration() {
    let parsed = parse_animal_kingdom_schema();
    let type_names = [
        "Bird",
        "Cat",
        "Dog",
        "Human",
        "Fish",
        "Rat",
        "PetRock",
        "Crocodile",
        "Height",
        "Query",
        "Mutation",
    ];

    for name in &type_names {
        let rendered = render_mock_object(name, &parsed.registry);
        let decl = rendered
            .lines()
            .find(|line| line.contains("struct MockFields"))
            .unwrap_or_else(|| {
                panic!("{} mock has no MockFields declaration:\n{}", name, rendered)
            });
        assert_eq!(decl.trim_start(), MOCK_FIELDS_DECL);
    }
}

#[test]
fn test_predators_field_renders_interface_type_correctly() {
    // The `predators` field is [Animal!]! -- Animal is an interface.
    // Only "Actor" gets MockObject. prefix per Swift's test mock namespace rules.
    // Other interface types render plain.
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Bird", &parsed.registry);

    assert!(
        rendered.contains(r#"@Field<[Animal]>("predators") public var predators"#),
        "Interface type Animal should render without MockObject. prefix.\nRendered:\n{}",
        rendered,
    );

    // In convenience init, interface types should render as (any AnyMock)
    assert!(
        rendered.contains("predators: [(any AnyMock)]"),
        "Interface list type should render as [(any AnyMock)] in convenience init\nRendered:\n{}",
        rendered,
    );
}

#[test]
fn test_custom_scalar_fields_render_with_namespace() {
    // Custom scalars like CustomDate should render as AnimalKingdomAPI.CustomDate
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Dog", &parsed.registry);

    assert!(
        rendered.contains("AnimalKingdomAPI.CustomDate"),
        "Custom scalar CustomDate should be namespaced with AnimalKingdomAPI\nRendered:\n{}",
        rendered,
    );

    // The built-in scalar "Object" is a custom scalar in this schema -- should also be namespaced
    assert!(
        rendered.contains("AnimalKingdomAPI.Object"),
        "Custom scalar Object should be namespaced with AnimalKingdomAPI\nRendered:\n{}",
        rendered,
    );
}

#[test]
fn test_enum_fields_render_with_graphql_enum_wrapper() {
    // Enum fields should render as GraphQLEnum<AnimalKingdomAPI.EnumType>
    let parsed = parse_animal_kingdom_schema();
    let rendered = render_mock_object("Height", &parsed.registry);

    assert!(
        rendered.contains("GraphQLEnum<AnimalKingdomAPI.RelativeSize>"),
        "Enum fields should use GraphQLEnum wrapper\nRendered:\n{}",
        rendered,
    );
}

#[test]
fn test_implementing_objects_populated_for_interfaces() {
    // Verify the adapter populates implementing_objects on interfaces,
    // which is needed for default mock values in convenience initializers.
    let parsed = parse_animal_kingdom_schema();

    // Check that Pet interface has implementing objects
    let pet_iface = match parsed.registry.get("Pet") {
        Some(GraphQLNamedType::Interface(i)) => Arc::clone(i),
        _ => panic!("Pet interface not found"),
    };
    assert!(
        !pet_iface.implementing_objects.is_empty(),
        "Pet interface should have implementing_objects populated by the adapter",
    );

    // Check that Animal interface also has implementing objects
    let animal_iface = match parsed.registry.get("Animal") {
        Some(GraphQLNamedType::Interface(i)) => Arc::clone(i),
        _ => panic!("Animal interface not found"),
    };
    assert!(
        !animal_iface.implementing_objects.is_empty(),
        "Animal interface should have implementing_objects populated by the adapter",
    );
}
