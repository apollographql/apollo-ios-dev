//! Integration tests for operation and fragment templates against AnimalKingdomAPI.
//!
//! These tests exercise the full pipeline: parse GraphQL -> compile -> build IR -> render template.
//! Each test compares the Rust-rendered output against the Swift-generated reference file.
//!
//! Tests are marked `#[ignore]` because:
//! 1. SelectionSetTemplate (Plan 02) is a stub -- the inner selection set body is placeholder text
//! 2. Reference .graphql.swift files may not be present in the worktree
//!
//! Once Plan 02's full SelectionSetTemplate is merged and reference files are available,
//! un-ignore these tests to validate byte-identical output.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use apollo_compiler::{executable, schema, validation::Valid};
use graphql_compiler::adapter::{
    self, build_network_request_source, collect_referenced_fragments, collect_referenced_types,
    convert_directives, convert_selection_set, TypeRegistry,
};
use graphql_compiler::compilation_result::{
    self, CompilationResult, FragmentDefinition, OperationDefinition, OperationType,
    RootTypeDefinition,
};
use graphql_compiler::{GraphQLCompositeType, GraphQLNamedType};
use indexmap::IndexMap;
use ir::builder::IRBuilder;

use apollo_codegen_lib::config::ApolloCodegenConfiguration;
use apollo_codegen_lib::templates::fragment_template::FragmentTemplate;
use apollo_codegen_lib::templates::local_cache_mutation_definition_template::LocalCacheMutationDefinitionTemplate;
use apollo_codegen_lib::templates::operation_definition_template::OperationDefinitionTemplate;
use apollo_codegen_lib::templates::{ConfigurationContext, TemplateRenderer};

// MARK: - Test Configuration

/// Standard SPM config matching what Swift codegen uses for AnimalKingdomAPI.
fn animal_kingdom_config() -> ConfigurationContext {
    let config: ApolloCodegenConfiguration = serde_json::from_str(
        r#"{
        "schemaNamespace": "AnimalKingdomAPI",
        "input": {},
        "output": {
            "schemaTypes": { "path": ".", "moduleType": {"swiftPackageManager": {}} },
            "operations": {"inSchemaModule": {}},
            "testMocks": {"none": {}}
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

fn resolve_composite_type(name: &str, registry: &TypeRegistry) -> GraphQLCompositeType {
    match registry.get(name) {
        Some(GraphQLNamedType::Object(obj)) => GraphQLCompositeType::Object(Arc::clone(obj)),
        Some(GraphQLNamedType::Interface(iface)) => {
            GraphQLCompositeType::Interface(Arc::clone(iface))
        }
        Some(GraphQLNamedType::Union(union_)) => GraphQLCompositeType::Union(Arc::clone(union_)),
        Some(other) => panic!(
            "Type '{}' is not a composite type: {:?}",
            name,
            other.name()
        ),
        None => panic!("Type '{}' not found in registry", name),
    }
}

fn build_root_types(schema: &Valid<schema::Schema>, registry: &TypeRegistry) -> RootTypeDefinition {
    let query_name = schema
        .schema_definition
        .query
        .as_ref()
        .map(|n| n.as_str().to_string())
        .unwrap_or_else(|| "Query".to_string());
    let mutation_name = schema
        .schema_definition
        .mutation
        .as_ref()
        .map(|n| n.as_str().to_string());
    let subscription_name = schema
        .schema_definition
        .subscription
        .as_ref()
        .map(|n| n.as_str().to_string());

    let query_type = registry
        .get(&query_name)
        .cloned()
        .unwrap_or_else(|| panic!("Query type '{}' not found in schema", query_name));
    let mutation_type = mutation_name.and_then(|name| registry.get(&name).cloned());
    let subscription_type = subscription_name.and_then(|name| registry.get(&name).cloned());

    RootTypeDefinition {
        query_type,
        mutation_type,
        subscription_type,
    }
}

struct ParsedFile {
    abs_path: String,
    doc: executable::ExecutableDocument,
}

/// Builds the full pipeline from schema + operation files to CompilationResult + IRBuilder.
fn build_pipeline(schema_path: &Path, op_paths: &[PathBuf]) -> (Arc<CompilationResult>, IRBuilder) {
    let schema_sdl = std::fs::read_to_string(schema_path)
        .unwrap_or_else(|e| panic!("Failed to read schema: {}: {}", schema_path.display(), e));
    let schema_sdl = prepend_custom_directive_stubs(&schema_sdl);
    let schema_abs_path = schema_path.to_string_lossy().to_string();

    let parsed_schema = schema::Schema::parse_and_validate(&schema_sdl, &schema_abs_path)
        .unwrap_or_else(|diag| panic!("Schema validation failed:\n{}", diag.errors));

    let parsed_files: Vec<ParsedFile> = op_paths
        .iter()
        .map(|path| {
            let abs_path = path.to_string_lossy().to_string();
            let content = std::fs::read_to_string(path)
                .unwrap_or_else(|e| panic!("Failed to read operation: {}: {}", path.display(), e));
            let doc = executable::ExecutableDocument::parse(&parsed_schema, &content, &abs_path)
                .unwrap_or_else(|diag| panic!("Operation parsing failed: {}", diag.errors));
            ParsedFile { abs_path, doc }
        })
        .collect();

    let registry = TypeRegistry::from_schema(&parsed_schema);
    let schema_root_types = build_root_types(&parsed_schema, &registry);

    // Build fragments (two-pass for cross-references)
    let mut fragment_defs: IndexMap<String, Arc<FragmentDefinition>> = IndexMap::new();

    // First pass: stubs
    for pf in &parsed_files {
        for (name, frag) in &pf.doc.fragments {
            let type_name = frag.type_condition().as_str();
            let parent_type = resolve_composite_type(type_name, &registry);
            let stub = Arc::new(FragmentDefinition {
                name: name.as_str().to_string(),
                type_: parent_type.clone(),
                selection_set: compilation_result::SelectionSet {
                    parent_type,
                    selections: vec![],
                },
                directives: None,
                referenced_fragments: vec![],
                source: frag.to_string(),
                file_path: pf.abs_path.clone(),
            });
            fragment_defs.insert(name.as_str().to_string(), stub);
        }
    }

    // Second pass: full definitions
    for pf in &parsed_files {
        for (name, frag) in &pf.doc.fragments {
            let type_name = frag.type_condition().as_str();
            let parent_type = resolve_composite_type(type_name, &registry);
            let selection_set = convert_selection_set(
                &frag.selection_set.selections,
                &parent_type,
                &registry,
                &fragment_defs,
            );
            let referenced =
                collect_referenced_fragments(&frag.selection_set.selections, &fragment_defs);
            let full = Arc::new(FragmentDefinition {
                name: name.as_str().to_string(),
                type_: parent_type,
                selection_set,
                directives: convert_directives(&frag.directives),
                referenced_fragments: referenced,
                source: build_network_request_source(&frag.to_string(), false),
                file_path: pf.abs_path.clone(),
            });
            fragment_defs.insert(name.as_str().to_string(), full);
        }
    }

    // Build operations
    let mut operations = Vec::new();
    for pf in &parsed_files {
        let mut all_ops: Vec<(&executable::Operation, String)> = Vec::new();
        if let Some(ref anon) = pf.doc.operations.anonymous {
            all_ops.push((anon, "AnonymousOperation".to_string()));
        }
        for (name, op) in &pf.doc.operations.named {
            all_ops.push((op, name.as_str().to_string()));
        }

        for (op, op_name) in &all_ops {
            let op_type = match op.operation_type {
                executable::OperationType::Query => OperationType::Query,
                executable::OperationType::Mutation => OperationType::Mutation,
                executable::OperationType::Subscription => OperationType::Subscription,
            };
            let root_type_name = match op.operation_type {
                executable::OperationType::Query => parsed_schema
                    .schema_definition
                    .query
                    .as_ref()
                    .map(|n| n.as_str().to_string())
                    .unwrap_or_else(|| "Query".to_string()),
                executable::OperationType::Mutation => parsed_schema
                    .schema_definition
                    .mutation
                    .as_ref()
                    .map(|n| n.as_str().to_string())
                    .unwrap_or_else(|| "Mutation".to_string()),
                executable::OperationType::Subscription => parsed_schema
                    .schema_definition
                    .subscription
                    .as_ref()
                    .map(|n| n.as_str().to_string())
                    .unwrap_or_else(|| "Subscription".to_string()),
            };
            let root_type = resolve_composite_type(&root_type_name, &registry);
            let selection_set = convert_selection_set(
                &op.selection_set.selections,
                &root_type,
                &registry,
                &fragment_defs,
            );
            let variables = op
                .variables
                .iter()
                .map(|var| compilation_result::VariableDefinition {
                    name: var.name.as_str().to_string(),
                    type_: adapter::convert_type(&var.ty, &registry),
                    default_value: var
                        .default_value
                        .as_ref()
                        .map(|v| adapter::convert_value(v)),
                })
                .collect();
            let referenced =
                collect_referenced_fragments(&op.selection_set.selections, &fragment_defs);
            operations.push(OperationDefinition {
                name: op_name.clone(),
                operation_type: op_type,
                variables,
                root_type,
                selection_set,
                directives: convert_directives(&op.directives),
                referenced_fragments: referenced,
                source: build_network_request_source(&op.to_string(), false),
                file_path: pf.abs_path.clone(),
            });
        }
    }

    let fragment_defs_vec: Vec<FragmentDefinition> =
        fragment_defs.values().map(|f| (**f).clone()).collect();
    let all_types = collect_referenced_types(&registry, &operations, &fragment_defs_vec, false);

    let compilation_result = Arc::new(CompilationResult {
        schema_root_types,
        referenced_types: all_types,
        operations,
        fragments: fragment_defs_vec,
        schema_documentation: parsed_schema
            .schema_definition
            .description
            .as_ref()
            .map(|d| d.to_string()),
    });

    let builder = IRBuilder::new(compilation_result.clone());
    (compilation_result, builder)
}

/// Collects all .graphql files from the AnimalKingdomAPI directory.
fn collect_all_graphql_files() -> Vec<PathBuf> {
    let dir = animal_kingdom_graphql_dir();
    let mut files: Vec<PathBuf> = std::fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("Failed to read dir: {}: {}", dir.display(), e))
        .filter_map(|entry| {
            let entry = entry.ok()?;
            let path = entry.path();
            if path.extension().is_some_and(|ext| ext == "graphql") {
                Some(path)
            } else {
                None
            }
        })
        .collect();
    files.sort();
    files
}

/// Renders an operation through the OperationDefinitionTemplate.
fn render_operation(
    ir_builder: &IRBuilder,
    op_def: &OperationDefinition,
    config: ConfigurationContext,
) -> String {
    let op_arc = Arc::new(op_def.clone());
    let operation = Arc::new(ir_builder.build_operation(&op_arc));

    if operation.definition.is_local_cache_mutation() {
        let template = LocalCacheMutationDefinitionTemplate {
            operation,
            config,
            referenced_types: Arc::clone(&ir_builder.schema.referenced_types),
        };
        template.render().body
    } else {
        let template = OperationDefinitionTemplate {
            operation,
            operation_identifier: None,
            config,
            referenced_types: Arc::clone(&ir_builder.schema.referenced_types),
        };
        template.render().body
    }
}

/// Renders a fragment through the FragmentTemplate.
fn render_fragment(
    ir_builder: &IRBuilder,
    frag_def: &FragmentDefinition,
    config: ConfigurationContext,
) -> String {
    let frag_arc = Arc::new(frag_def.clone());
    let fragment = ir_builder.build_fragment(&frag_arc);

    let template = FragmentTemplate { fragment, config };
    template.render().body
}

// MARK: - Pipeline Sanity Tests (not ignored -- verify the pipeline works)

#[test]
fn test_pipeline_parses_animal_kingdom_schema() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    assert!(
        schema_path.exists(),
        "AnimalKingdomAPI schema not found at: {}",
        schema_path.display()
    );

    let op_files = collect_all_graphql_files();
    assert!(
        op_files.len() >= 14,
        "Expected at least 14 .graphql files, found {}",
        op_files.len()
    );

    let (cr, _builder) = build_pipeline(&schema_path, &op_files);
    assert!(!cr.operations.is_empty(), "No operations found");
    assert!(!cr.fragments.is_empty(), "No fragments found");
}

#[test]
fn test_pipeline_builds_ir_for_all_operations() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    for op in &cr.operations {
        let op_arc = Arc::new(op.clone());
        let _operation = builder.build_operation(&op_arc);
        // If this doesn't panic, the IR build succeeded
    }

    for frag in &cr.fragments {
        let frag_arc = Arc::new(frag.clone());
        let _fragment = builder.build_fragment(&frag_arc);
        // If this doesn't panic, the IR build succeeded
    }
}

#[test]
fn test_operation_template_renders_without_panic() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    for op in &cr.operations {
        let config = animal_kingdom_config();
        let rendered = render_operation(&builder, op, config);
        assert!(
            !rendered.is_empty(),
            "Rendered output for {} is empty",
            op.name
        );
    }
}

#[test]
fn test_fragment_template_renders_without_panic() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    for frag in &cr.fragments {
        let config = animal_kingdom_config();
        let rendered = render_fragment(&builder, frag, config);
        assert!(
            !rendered.is_empty(),
            "Rendered output for {} is empty",
            frag.name
        );
    }
}

#[test]
fn test_all_animals_query_renders_struct_declaration() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let op = cr
        .operations
        .iter()
        .find(|o| o.name == "AllAnimalsQuery")
        .expect("AllAnimalsQuery not found");
    let config = animal_kingdom_config();
    let rendered = render_operation(&builder, op, config);

    assert!(
        rendered.contains("struct AllAnimalsQuery: GraphQLQuery"),
        "Missing struct declaration"
    );
    assert!(
        rendered.contains("static let operationName: String = \"AllAnimalsQuery\""),
        "Missing operationName"
    );
    assert!(
        rendered.contains("operationDocument"),
        "Missing operationDocument"
    );
}

#[test]
fn test_dog_query_renders_struct_declaration() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let op = cr
        .operations
        .iter()
        .find(|o| o.name == "DogQuery")
        .expect("DogQuery not found");
    let config = animal_kingdom_config();
    let rendered = render_operation(&builder, op, config);

    assert!(
        rendered.contains("struct DogQuery: GraphQLQuery"),
        "Missing struct declaration"
    );
    assert!(
        rendered.contains("static let operationName: String = \"DogQuery\""),
        "Missing operationName"
    );
}

#[test]
fn test_pet_adoption_mutation_renders_struct_declaration() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let op = cr
        .operations
        .iter()
        .find(|o| o.name == "PetAdoptionMutation")
        .expect("PetAdoptionMutation not found");
    let config = animal_kingdom_config();
    let rendered = render_operation(&builder, op, config);

    assert!(
        rendered.contains("struct PetAdoptionMutation: GraphQLMutation"),
        "Missing struct declaration"
    );
}

#[test]
fn test_pet_details_mutation_renders_fragment_struct() {
    // PetDetailsMutation.graphql defines a fragment with @apollo_client_ios_localCacheMutation,
    // not an operation. It should be rendered as a fragment.
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let frag = cr
        .fragments
        .iter()
        .find(|f| f.name == "PetDetailsMutation")
        .expect("PetDetailsMutation fragment not found");
    let config = animal_kingdom_config();
    let rendered = render_fragment(&builder, frag, config);

    assert!(
        rendered.contains("struct PetDetailsMutation"),
        "Missing struct declaration"
    );
    assert!(
        rendered.contains("Fragment"),
        "Missing Fragment conformance"
    );
}

#[test]
fn test_all_animals_local_cache_mutation_renders_struct() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let op = cr
        .operations
        .iter()
        .find(|o| o.name == "AllAnimalsLocalCacheMutation")
        .expect("AllAnimalsLocalCacheMutation not found");
    let config = animal_kingdom_config();
    let rendered = render_operation(&builder, op, config);

    assert!(
        rendered.contains("LocalCacheMutation"),
        "Missing LocalCacheMutation conformance"
    );
    assert!(
        rendered.contains("MutableSelectionSet"),
        "Missing MutableSelectionSet"
    );
}

#[test]
fn test_pet_search_local_cache_mutation_renders_struct() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let op = cr
        .operations
        .iter()
        .find(|o| o.name == "PetSearchLocalCacheMutation")
        .expect("PetSearchLocalCacheMutation not found");
    let config = animal_kingdom_config();
    let rendered = render_operation(&builder, op, config);

    assert!(
        rendered.contains("LocalCacheMutation"),
        "Missing LocalCacheMutation"
    );
}

#[test]
fn test_crocodile_fragment_renders_struct() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let frag = cr
        .fragments
        .iter()
        .find(|f| f.name == "CrocodileFragment")
        .expect("CrocodileFragment not found");
    let config = animal_kingdom_config();
    let rendered = render_fragment(&builder, frag, config);

    assert!(
        rendered.contains("struct CrocodileFragment:"),
        "Missing struct declaration"
    );
    assert!(
        rendered.contains("Fragment"),
        "Missing Fragment conformance"
    );
}

#[test]
fn test_dog_fragment_renders_struct() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let frag = cr
        .fragments
        .iter()
        .find(|f| f.name == "DogFragment")
        .expect("DogFragment not found");
    let config = animal_kingdom_config();
    let rendered = render_fragment(&builder, frag, config);

    assert!(
        rendered.contains("struct DogFragment:"),
        "Missing struct declaration"
    );
}

#[test]
fn test_height_in_meters_fragment_renders_struct() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let frag = cr
        .fragments
        .iter()
        .find(|f| f.name == "HeightInMeters")
        .expect("HeightInMeters not found");
    let config = animal_kingdom_config();
    let rendered = render_fragment(&builder, frag, config);

    assert!(
        rendered.contains("struct HeightInMeters:"),
        "Missing struct declaration"
    );
}

#[test]
fn test_pet_details_fragment_renders_struct() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let frag = cr
        .fragments
        .iter()
        .find(|f| f.name == "PetDetails")
        .expect("PetDetails not found");
    let config = animal_kingdom_config();
    let rendered = render_fragment(&builder, frag, config);

    assert!(
        rendered.contains("struct PetDetails:"),
        "Missing struct declaration"
    );
}

#[test]
fn test_warm_blooded_details_fragment_renders_struct() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();

    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let frag = cr
        .fragments
        .iter()
        .find(|f| f.name == "WarmBloodedDetails")
        .expect("WarmBloodedDetails not found");
    let config = animal_kingdom_config();
    let rendered = render_fragment(&builder, frag, config);

    assert!(
        rendered.contains("struct WarmBloodedDetails:"),
        "Missing struct declaration"
    );
}

// MARK: - Full Output Comparison Tests (ignored until Plan 02 merges)
// These compare the full rendered output against the Swift-generated reference files.
// They require:
// 1. Plan 02's full SelectionSetTemplate implementation
// 2. Reference .graphql.swift files present on disk

#[test]
#[ignore = "Requires Plan 02 SelectionSetTemplate and reference .graphql.swift files"]
fn test_all_animals_query_matches_swift_reference() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();
    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let op = cr
        .operations
        .iter()
        .find(|o| o.name == "AllAnimalsQuery")
        .unwrap();
    let config = animal_kingdom_config();
    let rendered = render_operation(&builder, op, config);

    let reference_path = dir.join("AllAnimalsQuery.graphql.swift");
    let reference = std::fs::read_to_string(&reference_path).unwrap_or_else(|e| {
        panic!(
            "Reference file not found: {}: {}",
            reference_path.display(),
            e
        )
    });
    assert_eq!(rendered, reference, "Output mismatch for AllAnimalsQuery");
}

#[test]
#[ignore = "Requires Plan 02 SelectionSetTemplate and reference .graphql.swift files"]
fn test_all_animals_include_skip_query_matches_swift_reference() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();
    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let op = cr
        .operations
        .iter()
        .find(|o| o.name == "AllAnimalsIncludeSkipQuery")
        .unwrap();
    let config = animal_kingdom_config();
    let rendered = render_operation(&builder, op, config);

    let reference_path = dir.join("AllAnimalsIncludeSkipQuery.graphql.swift");
    let reference = std::fs::read_to_string(&reference_path).unwrap_or_else(|e| {
        panic!(
            "Reference file not found: {}: {}",
            reference_path.display(),
            e
        )
    });
    assert_eq!(
        rendered, reference,
        "Output mismatch for AllAnimalsIncludeSkipQuery"
    );
}

#[test]
#[ignore = "Requires Plan 02 SelectionSetTemplate and reference .graphql.swift files"]
fn test_classroom_pets_query_matches_swift_reference() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();
    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let op = cr
        .operations
        .iter()
        .find(|o| o.name == "ClassroomPetsQuery")
        .unwrap();
    let config = animal_kingdom_config();
    let rendered = render_operation(&builder, op, config);

    let reference_path = dir.join("ClassroomPetsQuery.graphql.swift");
    let reference = std::fs::read_to_string(&reference_path).unwrap_or_else(|e| {
        panic!(
            "Reference file not found: {}: {}",
            reference_path.display(),
            e
        )
    });
    assert_eq!(
        rendered, reference,
        "Output mismatch for ClassroomPetsQuery"
    );
}

#[test]
#[ignore = "Requires Plan 02 SelectionSetTemplate and reference .graphql.swift files"]
fn test_dog_query_matches_swift_reference() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();
    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let op = cr.operations.iter().find(|o| o.name == "DogQuery").unwrap();
    let config = animal_kingdom_config();
    let rendered = render_operation(&builder, op, config);

    let reference_path = dir.join("DogQuery.graphql.swift");
    let reference = std::fs::read_to_string(&reference_path).unwrap_or_else(|e| {
        panic!(
            "Reference file not found: {}: {}",
            reference_path.display(),
            e
        )
    });
    assert_eq!(rendered, reference, "Output mismatch for DogQuery");
}

#[test]
#[ignore = "Requires Plan 02 SelectionSetTemplate and reference .graphql.swift files"]
fn test_pet_search_query_matches_swift_reference() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();
    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let op = cr
        .operations
        .iter()
        .find(|o| o.name == "PetSearchQuery")
        .unwrap();
    let config = animal_kingdom_config();
    let rendered = render_operation(&builder, op, config);

    let reference_path = dir.join("PetSearchQuery.graphql.swift");
    let reference = std::fs::read_to_string(&reference_path).unwrap_or_else(|e| {
        panic!(
            "Reference file not found: {}: {}",
            reference_path.display(),
            e
        )
    });
    assert_eq!(rendered, reference, "Output mismatch for PetSearchQuery");
}

#[test]
#[ignore = "Requires Plan 02 SelectionSetTemplate and reference .graphql.swift files"]
fn test_crocodile_fragment_matches_swift_reference() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();
    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let frag = cr
        .fragments
        .iter()
        .find(|f| f.name == "CrocodileFragment")
        .unwrap();
    let config = animal_kingdom_config();
    let rendered = render_fragment(&builder, frag, config);

    let reference_path = dir.join("CrocodileFragment.graphql.swift");
    let reference = std::fs::read_to_string(&reference_path).unwrap_or_else(|e| {
        panic!(
            "Reference file not found: {}: {}",
            reference_path.display(),
            e
        )
    });
    assert_eq!(rendered, reference, "Output mismatch for CrocodileFragment");
}

#[test]
#[ignore = "Requires Plan 02 SelectionSetTemplate and reference .graphql.swift files"]
fn test_dog_fragment_matches_swift_reference() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();
    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let frag = cr
        .fragments
        .iter()
        .find(|f| f.name == "DogFragment")
        .unwrap();
    let config = animal_kingdom_config();
    let rendered = render_fragment(&builder, frag, config);

    let reference_path = dir.join("DogFragment.graphql.swift");
    let reference = std::fs::read_to_string(&reference_path).unwrap_or_else(|e| {
        panic!(
            "Reference file not found: {}: {}",
            reference_path.display(),
            e
        )
    });
    assert_eq!(rendered, reference, "Output mismatch for DogFragment");
}

#[test]
#[ignore = "Requires Plan 02 SelectionSetTemplate and reference .graphql.swift files"]
fn test_height_in_meters_matches_swift_reference() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();
    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let frag = cr
        .fragments
        .iter()
        .find(|f| f.name == "HeightInMeters")
        .unwrap();
    let config = animal_kingdom_config();
    let rendered = render_fragment(&builder, frag, config);

    let reference_path = dir.join("HeightInMeters.graphql.swift");
    let reference = std::fs::read_to_string(&reference_path).unwrap_or_else(|e| {
        panic!(
            "Reference file not found: {}: {}",
            reference_path.display(),
            e
        )
    });
    assert_eq!(rendered, reference, "Output mismatch for HeightInMeters");
}

#[test]
#[ignore = "Requires Plan 02 SelectionSetTemplate and reference .graphql.swift files"]
fn test_pet_details_matches_swift_reference() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();
    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let frag = cr
        .fragments
        .iter()
        .find(|f| f.name == "PetDetails")
        .unwrap();
    let config = animal_kingdom_config();
    let rendered = render_fragment(&builder, frag, config);

    let reference_path = dir.join("PetDetails.graphql.swift");
    let reference = std::fs::read_to_string(&reference_path).unwrap_or_else(|e| {
        panic!(
            "Reference file not found: {}: {}",
            reference_path.display(),
            e
        )
    });
    assert_eq!(rendered, reference, "Output mismatch for PetDetails");
}

#[test]
#[ignore = "Requires Plan 02 SelectionSetTemplate and reference .graphql.swift files"]
fn test_warm_blooded_details_matches_swift_reference() {
    let dir = animal_kingdom_graphql_dir();
    let schema_path = dir.join("AnimalSchema.graphqls");
    let op_files = collect_all_graphql_files();
    let (cr, builder) = build_pipeline(&schema_path, &op_files);

    let frag = cr
        .fragments
        .iter()
        .find(|f| f.name == "WarmBloodedDetails")
        .unwrap();
    let config = animal_kingdom_config();
    let rendered = render_fragment(&builder, frag, config);

    let reference_path = dir.join("WarmBloodedDetails.graphql.swift");
    let reference = std::fs::read_to_string(&reference_path).unwrap_or_else(|e| {
        panic!(
            "Reference file not found: {}: {}",
            reference_path.display(),
            e
        )
    });
    assert_eq!(
        rendered, reference,
        "Output mismatch for WarmBloodedDetails"
    );
}
