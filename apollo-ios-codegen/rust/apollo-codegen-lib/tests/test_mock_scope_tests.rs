//! Scoped test mocks: selection of the object types a `testMocks` output covers.

use std::fs;
use std::path::Path;

use apollo_codegen_lib::codegen::{ApolloCodegen, CodegenError, GenerationFilter};
use apollo_codegen_lib::config::test_mock_file_output::{TestMockScope, TestMockScoping};
use apollo_codegen_lib::config::ApolloCodegenConfiguration;
use apollo_codegen_lib::templates::ConfigurationContext;
use apollo_codegen_lib::test_mock_scope::{referenced_object_types, select_mock_object_types};
use tempfile::TempDir;

const SCHEMA: &str = r#"
type Query { pets: [Pet!]!, me: User, rocks: [Rock!]!, search: [SearchResult!]! }
type Mutation { adopt(input: AdoptInput!): Dog }
input AdoptInput { name: String!, kind: Kind }
enum Kind { DOG CAT }
interface Pet { id: ID!, name: String! }
interface WarmBlooded { temperature: Int! }
type Dog implements Pet & WarmBlooded { id: ID!, name: String!, temperature: Int!, owner: User }
type Cat implements Pet & WarmBlooded { id: ID!, name: String!, temperature: Int! }
type Fish implements Pet { id: ID!, name: String! }
type User { id: ID!, name: String }
type Rock { id: ID! }
type Shop { id: ID! }
union SearchResult = Shop | Rock
"#;

const FILES: &[(&str, &str)] = &[
    ("Shared/PetBits.graphql", "fragment PetBits on Pet { id name }"),
    ("Features/Pets/PetsQuery.graphql", "query PetsQuery { pets { ...PetBits } }"),
    ("Features/Account/MeQuery.graphql", "query MeQuery { me { id name } }"),
    ("Features/Rocks/RocksQuery.graphql", "query RocksQuery { rocks { id } }"),
    ("Features/Search/SearchQuery.graphql", "query SearchQuery { search { ... on Shop { id } } }"),
    ("Features/Adopt/AdoptMutation.graphql", "mutation Adopt($input: AdoptInput!) { adopt(input: $input) { id } }"),
];

fn write_fixture(root: &Path) {
    fs::create_dir_all(root.join("Schema")).unwrap();
    fs::write(root.join("Schema/schema.graphqls"), SCHEMA).unwrap();
    for (path, content) in FILES {
        let full = root.join(path);
        fs::create_dir_all(full.parent().unwrap()).unwrap();
        fs::write(full, content).unwrap();
    }
}

fn compile(root: &Path) -> apollo_codegen_lib::codegen::CompileResult {
    let config_json = serde_json::json!({
        "schemaNamespace": "ZooAPI",
        "input": {
            "schemaSearchPaths": [root.join("Schema/schema.graphqls")],
            "operationSearchPaths": FILES.iter().map(|(p, _)| root.join(p)).collect::<Vec<_>>()
        },
        "output": {
            "schemaTypes": {"path": root.join("out"), "moduleType": {"other": {}}},
            "operations": {"absolute": {"path": root.join("out")}},
            "testMocks": {"absolute": {"path": root.join("mocks")}}
        }
    });
    let configuration: ApolloCodegenConfiguration = serde_json::from_value(config_json).unwrap();
    let config = ConfigurationContext::new(configuration, None);
    ApolloCodegen::compile_schema_and_ir(&config).expect("compile")
}

fn names(set: &indexmap::IndexSet<String>) -> Vec<&str> {
    set.iter().map(String::as_str).collect()
}

fn files(paths: &[&str], root: &Path) -> GenerationFilter {
    GenerationFilter::Files(paths.iter().map(|p| root.join(p).to_string_lossy().to_string()).collect())
}

#[test]
fn unfiltered_referenced_objects_equal_the_configuration_objects() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let result = compile(tmp.path());

    let all = referenced_object_types(&result.compilation_result, None);
    let expected: Vec<String> = result
        .ir
        .schema
        .referenced_types
        .objects
        .iter()
        .map(|o| o.name.schema_name.clone())
        .collect();
    // The IR lists referenced objects in configuration order on 1.15.1/1.15.2 and
    // alphabetically from 1.15.3; the selection keeps configuration order and the mock
    // files are emitted by iterating the IR's list, so only the sets must match.
    let mut got = names(&all);
    got.sort_unstable();
    let mut want: Vec<&str> = expected.iter().map(String::as_str).collect();
    want.sort_unstable();
    assert_eq!(got, want);
    assert!(all.contains("Dog") && all.contains("Shop") && all.contains("Mutation"), "{:?}", all);
}

#[test]
fn referenced_scope_follows_interfaces_unions_and_fragments() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let result = compile(tmp.path());
    let cr = &result.compilation_result;

    // pets: [Pet] through a fragment spread: every Pet implementor, and through
    // Dog/Cat's WarmBlooded interface nothing new (its implementors are pets too).
    let pets = referenced_object_types(cr, Some(&files(&["Features/Pets/PetsQuery.graphql"], tmp.path())));
    assert_eq!(names(&pets), ["Query", "Dog", "Cat", "Fish"]);

    // me: User only.
    let me = referenced_object_types(cr, Some(&files(&["Features/Account/MeQuery.graphql"], tmp.path())));
    assert_eq!(names(&me), ["Query", "User"]);

    // search: [SearchResult] union: both members even though only Shop is selected.
    let search = referenced_object_types(cr, Some(&files(&["Features/Search/SearchQuery.graphql"], tmp.path())));
    assert_eq!(names(&search), ["Query", "Shop", "Rock"]);

    // adopt: Dog -> its interfaces Pet and WarmBlooded -> their implementors; the
    // input object contributes no objects.
    let adopt = referenced_object_types(cr, Some(&files(&["Features/Adopt/AdoptMutation.graphql"], tmp.path())));
    assert_eq!(names(&adopt), ["Mutation", "Dog", "Cat", "Fish"]);

    // A fragment file selected on its own contributes its type condition's closure.
    let shared = referenced_object_types(cr, Some(&files(&["Shared/PetBits.graphql"], tmp.path())));
    assert_eq!(names(&shared), ["Dog", "Cat", "Fish"]);

    // Prefix selection works too.
    let prefix = referenced_object_types(cr, Some(&GenerationFilter::Prefix(tmp.path().join("Features/Rocks").to_string_lossy().to_string())));
    assert_eq!(names(&prefix), ["Query", "Rock"]);
}

#[test]
fn select_applies_scope_include_and_exclude_in_configuration_order() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let result = compile(tmp.path());
    let cr = &result.compilation_result;
    let filter = files(&["Features/Account/MeQuery.graphql"], tmp.path());

    let all = select_mock_object_types(cr, &TestMockScoping::default(), Some(&filter)).unwrap();
    assert_eq!(names(&all), names(&referenced_object_types(cr, None)), "scope all ignores the filter");

    let scoping = TestMockScoping {
        scope: TestMockScope::ReferencedByOperations,
        include_types: vec!["Rock".to_string()],
        exclude_types: vec!["Query".to_string(), "NotAType".to_string()],
        base_module: None,
        include_typealiases: None,
    };
    let selected = select_mock_object_types(cr, &scoping, Some(&filter)).unwrap();
    // Configuration order (Query, Dog, Cat, Fish, User, Rock, ...), not insertion order.
    assert_eq!(names(&selected), ["User", "Rock"]);

    let everything_but = TestMockScoping {
        exclude_types: vec!["Dog".to_string(), "Cat".to_string()],
        ..Default::default()
    };
    let base = select_mock_object_types(cr, &everything_but, None).unwrap();
    assert!(!base.contains("Dog") && !base.contains("Cat") && base.contains("Fish"), "{:?}", base);
}

#[test]
fn unknown_include_type_is_an_error() {
    let tmp = TempDir::new().unwrap();
    write_fixture(tmp.path());
    let result = compile(tmp.path());
    let scoping = TestMockScoping {
        include_types: vec!["Shop".to_string(), "Ghost".to_string()],
        ..Default::default()
    };
    let err = select_mock_object_types(&result.compilation_result, &scoping, None).unwrap_err();
    assert!(err.to_string().contains("'Ghost'"), "{err}");
    match err {
        CodegenError::TestMocksUnknownIncludeType { name } => assert_eq!(name, "Ghost"),
        other => panic!("unexpected error {other:?}"),
    }
}
