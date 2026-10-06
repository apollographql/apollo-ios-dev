//! IR Compare Tool
//!
//! Takes a GraphQL schema file and operation files, runs them through the
//! Rust adapter -> IR builder pipeline, and outputs canonical JSON for each
//! operation and fragment. Designed for comparison testing against Swift codegen.
//!
//! Usage:
//!   cargo run --bin ir-compare -- <schema.graphql> <operations.graphql> [more_ops.graphql...]
//!   cargo run --bin ir-compare -- --strict <schema.graphql> <operations.graphql>
//!
//! By default, uses permissive parsing (matching Swift's GraphQL.js behavior) --
//! unused fragments are allowed and won't cause errors.
//! With --strict, runs full apollo-compiler validation (rejects unused fragments, etc.).
//!
//! Output: JSON to stdout with one object per operation/fragment.

use std::sync::Arc;
use std::{env, fs, process};

use apollo_compiler::{schema, executable, validation::Valid};
use graphql_compiler::adapter::{
    self, TypeRegistry, build_network_request_source, collect_referenced_fragments,
    collect_referenced_types, convert_directives, convert_selection_set,
};
use graphql_compiler::compilation_result::{
    self, CompilationResult, FragmentDefinition, OperationDefinition, OperationType,
    RootTypeDefinition,
};
use graphql_compiler::{
    GraphQLCompositeType, GraphQLNamedType, GraphQLType, GraphQLValue,
};
use indexmap::IndexMap;
use ir::builder::IRBuilder;
use serde_json::{json, Value};

/// Parsed operation file: the absolute path and the parsed ExecutableDocument.
struct ParsedFile {
    abs_path: String,
    doc: executable::ExecutableDocument,
}

fn main() {
    let args: Vec<String> = env::args().collect();

    // Parse flags
    let strict = args.iter().any(|a| a == "--strict");
    let compilation_result_mode = args.iter().any(|a| a == "--compilation-result");
    let file_args: Vec<&str> = args[1..].iter()
        .filter(|a| *a != "--strict" && *a != "--compilation-result")
        .map(|s| s.as_str())
        .collect();

    if file_args.len() < 2 {
        eprintln!("Usage: ir-compare [OPTIONS] <schema.graphql> <operations.graphql> [more.graphql...]");
        eprintln!();
        eprintln!("Parses GraphQL schema and operations, outputs canonical JSON.");
        eprintln!();
        eprintln!("Options:");
        eprintln!("  --strict              Full apollo-compiler validation (rejects unused fragments)");
        eprintln!("                        Default: permissive parsing matching Swift's GraphQL.js");
        eprintln!("  --compilation-result  Output CompilationResult JSON (pre-IR, for comparing with");
        eprintln!("                        Swift's compare-compilation-result tool)");
        eprintln!("                        Default: output post-IR JSON");
        process::exit(1);
    }

    let schema_path = file_args[0];
    let op_paths: Vec<&str> = file_args[1..].to_vec();

    // GAP-06: Resolve schema path to absolute
    let schema_abs_path = canonicalize_path(schema_path);

    // 1. Read and parse schema (always validated -- schema errors are fatal)
    let schema_sdl = fs::read_to_string(schema_path)
        .unwrap_or_else(|e| {
            eprintln!("Error reading schema file '{}': {}", schema_path, e);
            process::exit(1);
        });

    // Prepend stub definitions for custom directives that Swift's graphql-js
    // accepts but apollo-compiler's strict validation rejects.
    // These are common Apollo-specific directives used in real schemas.
    let schema_sdl = prepend_custom_directive_stubs(&schema_sdl);

    let parsed_schema = schema::Schema::parse_and_validate(&schema_sdl, &schema_abs_path)
        .unwrap_or_else(|diag| {
            eprintln!("Schema validation failed:\n{}", diag.errors);
            process::exit(1);
        });

    // 2. Parse each operation file individually with its absolute path.
    //    GAP-06: Each file gets its own absolute path for file_path fields.
    let parsed_files: Vec<ParsedFile> = op_paths
        .iter()
        .map(|path| {
            let abs_path = canonicalize_path(path);
            let content = fs::read_to_string(path)
                .unwrap_or_else(|e| {
                    eprintln!("Error reading operation file '{}': {}", path, e);
                    process::exit(1);
                });

            let doc = if strict {
                executable::ExecutableDocument::parse_and_validate(
                    &parsed_schema,
                    &content,
                    &abs_path,
                )
                .unwrap_or_else(|diag| {
                    eprintln!("Operation validation failed for '{}':\n{}", path, diag.errors);
                    process::exit(1);
                })
                .into_inner()
            } else {
                executable::ExecutableDocument::parse(
                    &parsed_schema,
                    &content,
                    &abs_path,
                )
                .unwrap_or_else(|diag| {
                    eprintln!("Operation parsing failed for '{}':\n{}", path, diag.errors);
                    process::exit(1);
                })
            };

            ParsedFile { abs_path, doc }
        })
        .collect();

    // 3. Build TypeRegistry
    let registry = TypeRegistry::from_schema(&parsed_schema);

    // 4. Build root type definition
    let schema_root_types = build_root_types(&parsed_schema, &registry);

    // 5. Build fragment definitions from ALL files first (operations may reference
    //    fragments from any file). Two-pass: stubs then full, using per-file absolute paths.
    let fragment_defs = build_fragment_definitions_multi_file(&parsed_files, &registry);

    // 6. Build operation definitions from each file, using per-file absolute paths.
    let operation_defs = build_operation_definitions_multi_file(
        &parsed_files,
        &registry,
        &parsed_schema,
        &fragment_defs,
    );

    // 7. GAP-03: Use adapter::collect_referenced_types() which filters to
    //    operation-referenced types and excludes introspection meta-types.
    let fragment_defs_vec: Vec<FragmentDefinition> =
        fragment_defs.values().map(|f| (**f).clone()).collect();
    let all_types = collect_referenced_types(
        &registry,
        &operation_defs,
        &fragment_defs_vec,
        false,
    );

    // 8. Assemble CompilationResult
    let compilation_result = Arc::new(CompilationResult {
        schema_root_types,
        referenced_types: all_types,
        operations: operation_defs,
        fragments: fragment_defs_vec,
        schema_documentation: parsed_schema
            .schema_definition
            .description
            .as_ref()
            .map(|d| d.to_string()),
    });

    // If --compilation-result mode, output the CompilationResult JSON directly
    // (matches Swift's compare-compilation-result tool format)
    if compilation_result_mode {
        let value = serialize_compilation_result(&compilation_result);
        let json = serde_json::to_string_pretty(&value)
            .expect("Failed to format JSON");
        println!("{}", json);
        return;
    }

    // 9. Build IR
    let builder = IRBuilder::new(compilation_result.clone());

    let mut output = serde_json::Map::new();

    // Build and serialize each operation
    let mut operations_arr = Vec::new();
    for op_def in &compilation_result.operations {
        let op_arc = Arc::new(op_def.clone());
        let operation = builder.build_operation(&op_arc);
        let json_str = ir::serialize_operation_to_json(&operation);
        let json_val: serde_json::Value = serde_json::from_str(&json_str)
            .expect("IR serialization produced invalid JSON");
        operations_arr.push(json_val);
    }
    output.insert("operations".to_string(), serde_json::Value::Array(operations_arr));

    // Build and serialize each fragment
    let mut fragments_arr = Vec::new();
    for frag_def in compilation_result.fragments.iter() {
        let frag_arc = Arc::new(frag_def.clone());
        let fragment = builder.build_fragment(&frag_arc);
        let json_str = ir::serialize_fragment_to_json(&fragment);
        let json_val: serde_json::Value = serde_json::from_str(&json_str)
            .expect("IR serialization produced invalid JSON");
        fragments_arr.push(json_val);
    }
    output.insert("fragments".to_string(), serde_json::Value::Array(fragments_arr));

    // Output canonical JSON
    let final_json = serde_json::to_string_pretty(&serde_json::Value::Object(output))
        .expect("Failed to serialize output");
    println!("{}", final_json);
}

/// Resolves a file path to an absolute path using canonicalize().
/// Falls back to the original path if canonicalize fails (e.g., file doesn't exist yet).
/// Makes a path absolute without resolving symlinks.
///
/// GAP-06: Swift's graphql-js uses the path as-is (no symlink resolution).
/// Using `std::fs::canonicalize` resolves `/tmp` -> `/private/tmp` on macOS,
/// causing file_path mismatches. Instead, prepend CWD for relative paths.
fn canonicalize_path(path: &str) -> String {
    let p = std::path::Path::new(path);
    if p.is_absolute() {
        path.to_string()
    } else {
        let cwd = std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
        cwd.join(p).display().to_string()
    }
}

/// Prepends stub definitions for custom directives that Swift's graphql-js
/// accepts but apollo-compiler's strict validation rejects.
///
/// Apollo iOS schemas commonly use directives like `@oneOf`, `@typePolicy`,
/// and `@import` which are not part of the core GraphQL spec. Swift's
/// graphql-js frontend accepts these without error, but apollo-compiler
/// requires explicit definitions.
fn prepend_custom_directive_stubs(schema_sdl: &str) -> String {
    let mut stubs = Vec::new();

    // Only add stubs for directives actually used in the schema
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

/// Builds fragment definitions from multiple parsed files.
/// Two-pass build: stubs first (for cross-references), then full definitions.
/// Each fragment gets the absolute file path of the file it came from.
fn build_fragment_definitions_multi_file(
    parsed_files: &[ParsedFile],
    registry: &TypeRegistry,
) -> IndexMap<String, Arc<FragmentDefinition>> {
    let mut fragment_defs: IndexMap<String, Arc<FragmentDefinition>> = IndexMap::new();

    // First pass: create fragment stubs with empty selection sets
    // (needed for cross-references between fragments across files)
    for pf in parsed_files {
        for (name, frag) in &pf.doc.fragments {
            let type_name = frag.type_condition().as_str();
            let parent_type = resolve_composite_type(type_name, registry);

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

    // Second pass: fill in selection sets and referenced fragments
    for pf in parsed_files {
        for (name, frag) in &pf.doc.fragments {
            let type_name = frag.type_condition().as_str();
            let parent_type = resolve_composite_type(type_name, registry);

            let selection_set = convert_selection_set(
                &frag.selection_set.selections,
                &parent_type,
                registry,
                &fragment_defs,
            );

            let referenced = collect_referenced_fragments(
                &frag.selection_set.selections,
                &fragment_defs,
            );

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

    fragment_defs
}

/// Builds operation definitions from multiple parsed files.
/// Each operation gets the absolute file path of the file it came from.
fn build_operation_definitions_multi_file(
    parsed_files: &[ParsedFile],
    registry: &TypeRegistry,
    schema: &Valid<schema::Schema>,
    fragment_defs: &IndexMap<String, Arc<FragmentDefinition>>,
) -> Vec<OperationDefinition> {
    let mut operations = Vec::new();

    for pf in parsed_files {
        // Collect all operations from this file: anonymous + named
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
                executable::OperationType::Query => schema
                    .schema_definition
                    .query
                    .as_ref()
                    .map(|n| n.as_str().to_string())
                    .unwrap_or_else(|| "Query".to_string()),
                executable::OperationType::Mutation => schema
                    .schema_definition
                    .mutation
                    .as_ref()
                    .map(|n| n.as_str().to_string())
                    .unwrap_or_else(|| "Mutation".to_string()),
                executable::OperationType::Subscription => schema
                    .schema_definition
                    .subscription
                    .as_ref()
                    .map(|n| n.as_str().to_string())
                    .unwrap_or_else(|| "Subscription".to_string()),
            };

            let root_type = resolve_composite_type(&root_type_name, registry);

            let selection_set = convert_selection_set(
                &op.selection_set.selections,
                &root_type,
                registry,
                fragment_defs,
            );

            let variables = op
                .variables
                .iter()
                .map(|var| compilation_result::VariableDefinition {
                    name: var.name.as_str().to_string(),
                    type_: adapter::convert_type(&var.ty, registry),
                    default_value: var.default_value.as_ref().map(|v| adapter::convert_value(v)),
                })
                .collect();

            let referenced = collect_referenced_fragments(
                &op.selection_set.selections,
                fragment_defs,
            );

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

    operations
}

fn build_root_types(
    schema: &Valid<schema::Schema>,
    registry: &TypeRegistry,
) -> RootTypeDefinition {
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

    let query_type = registry.get(&query_name)
        .cloned()
        .unwrap_or_else(|| panic!("Query type '{}' not found in schema", query_name));

    let mutation_type = mutation_name
        .and_then(|name| registry.get(&name).cloned());

    let subscription_type = subscription_name
        .and_then(|name| registry.get(&name).cloned());

    RootTypeDefinition {
        query_type,
        mutation_type,
        subscription_type,
    }
}

fn resolve_composite_type(name: &str, registry: &TypeRegistry) -> GraphQLCompositeType {
    match registry.get(name) {
        Some(GraphQLNamedType::Object(obj)) => GraphQLCompositeType::Object(Arc::clone(obj)),
        Some(GraphQLNamedType::Interface(iface)) => {
            GraphQLCompositeType::Interface(Arc::clone(iface))
        }
        Some(GraphQLNamedType::Union(union_)) => GraphQLCompositeType::Union(Arc::clone(union_)),
        Some(other) => panic!("Type '{}' is not a composite type: {:?}", name, other.name()),
        None => panic!("Type '{}' not found in registry", name),
    }
}

// MARK: - Manual CompilationResult serialization (avoids serde derive recursion overflow)

fn serialize_compilation_result(cr: &CompilationResult) -> Value {
    json!({
        "schema_root_types": {
            "query_type": cr.schema_root_types.query_type.name().schema_name,
            "mutation_type": cr.schema_root_types.mutation_type.as_ref().map(|t| &t.name().schema_name),
            "subscription_type": cr.schema_root_types.subscription_type.as_ref().map(|t| &t.name().schema_name),
        },
        "referenced_types": cr.referenced_types.iter()
            .map(serialize_named_type)
            .collect::<Vec<_>>(),
        "operations": cr.operations.iter()
            .map(serialize_operation_def)
            .collect::<Vec<_>>(),
        "fragments": cr.fragments.iter()
            .map(serialize_fragment_def)
            .collect::<Vec<_>>(),
        "schema_documentation": cr.schema_documentation,
    })
}

fn serialize_named_type(t: &GraphQLNamedType) -> Value {
    use graphql_compiler::*;
    match t {
        GraphQLNamedType::Scalar(s) => json!({
            "kind": "Scalar", "name": s.name.schema_name,
            "documentation": s.documentation,
        }),
        GraphQLNamedType::Object(o) => json!({
            "kind": "Object", "name": o.name.schema_name,
            "documentation": o.documentation,
            "fields": o.fields.iter().map(|(k, v)| (k.clone(), serialize_schema_field(v))).collect::<serde_json::Map<_,_>>(),
            "interfaces": o.interfaces.iter().map(|i| &i.name.schema_name).collect::<Vec<_>>(),
        }),
        GraphQLNamedType::Interface(i) => json!({
            "kind": "Interface", "name": i.name.schema_name,
            "documentation": i.documentation,
            "fields": i.fields.iter().map(|(k, v)| (k.clone(), serialize_schema_field(v))).collect::<serde_json::Map<_,_>>(),
            "interfaces": i.interfaces.iter().map(|i2| &i2.name.schema_name).collect::<Vec<_>>(),
        }),
        GraphQLNamedType::Union(u) => json!({
            "kind": "Union", "name": u.name.schema_name,
            "documentation": u.documentation,
            "types": u.types.iter().map(|t2| &t2.name.schema_name).collect::<Vec<_>>(),
        }),
        GraphQLNamedType::Enum(e) => json!({
            "kind": "Enum", "name": e.name.schema_name,
            "documentation": e.documentation,
            "values": e.values.iter().map(|v| json!({
                "name": v.name.schema_name,
                "documentation": v.documentation,
                "deprecation_reason": v.deprecation_reason,
            })).collect::<Vec<_>>(),
        }),
        GraphQLNamedType::InputObject(io) => json!({
            "kind": "InputObject", "name": io.name.schema_name,
            "documentation": io.documentation,
            "input_fields": io.fields.iter().map(|(k, v)| (k.clone(), json!({
                "name": v.name.schema_name,
                "type": serialize_graphql_type(&v.type_),
                "default_value": v.default_value.as_ref().map(serialize_graphql_value),
                "documentation": v.documentation,
                "deprecation_reason": v.deprecation_reason,
            }))).collect::<serde_json::Map<_,_>>(),
        }),
    }
}

fn serialize_schema_field(f: &graphql_compiler::GraphQLField) -> Value {
    json!({
        "name": f.name,
        "type": serialize_graphql_type(&f.type_),
        "arguments": f.arguments.iter().map(|a| json!({
            "name": a.name,
            "type": serialize_graphql_type(&a.type_),
            "documentation": a.documentation,
            "deprecation_reason": a.deprecation_reason,
        })).collect::<Vec<_>>(),
        "documentation": f.documentation,
        "deprecation_reason": f.deprecation_reason,
    })
}

fn serialize_graphql_type(t: &GraphQLType) -> Value {
    match t {
        GraphQLType::NonNull(inner) => json!({"kind": "NonNull", "ofType": serialize_graphql_type(inner)}),
        GraphQLType::List(inner) => json!({"kind": "List", "ofType": serialize_graphql_type(inner)}),
        GraphQLType::Entity(ct) => json!({"kind": "Entity", "value": {"name": ct.name().schema_name}}),
        GraphQLType::Scalar(s) => json!({"kind": "Scalar", "value": {"name": s.name.schema_name}}),
        GraphQLType::Enum(e) => json!({"kind": "Enum", "value": {"name": e.name.schema_name}}),
        GraphQLType::InputObject(io) => json!({"kind": "InputObject", "value": {"name": io.name.schema_name}}),
    }
}

fn serialize_graphql_value(v: &GraphQLValue) -> Value {
    match v {
        GraphQLValue::Variable(s) => json!({"kind": "variable", "value": s}),
        GraphQLValue::Int(i) => json!({"kind": "int", "value": i}),
        GraphQLValue::Float(f) => {
            // Match Swift's graphql-js behavior: whole-number floats (5.0) are
            // serialized as integers (5) in JSON
            if f.fract() == 0.0 && f.is_finite() {
                json!({"kind": "float", "value": *f as i64})
            } else {
                json!({"kind": "float", "value": f})
            }
        },
        GraphQLValue::String(s) => json!({"kind": "string", "value": s}),
        GraphQLValue::Boolean(b) => json!({"kind": "boolean", "value": b}),
        GraphQLValue::Null => json!({"kind": "null"}),
        GraphQLValue::Enum(s) => json!({"kind": "enum", "value": s}),
        GraphQLValue::List(arr) => json!({"kind": "list", "value": arr.iter().map(serialize_graphql_value).collect::<Vec<_>>()}),
        GraphQLValue::Object(map) => json!({"kind": "object", "value": map.iter().map(|(k,v)| (k.clone(), serialize_graphql_value(v))).collect::<serde_json::Map<_,_>>()}),
    }
}

fn serialize_operation_def(op: &OperationDefinition) -> Value {
    json!({
        "name": op.name,
        "operation_type": match op.operation_type {
            OperationType::Query => "query",
            OperationType::Mutation => "mutation",
            OperationType::Subscription => "subscription",
        },
        "variables": op.variables.iter().map(|v| json!({
            "name": v.name,
            "type": serialize_graphql_type(&v.type_),
            "default_value": v.default_value.as_ref().map(serialize_graphql_value),
        })).collect::<Vec<_>>(),
        "root_type": op.root_type.name().schema_name,
        "selection_set": serialize_selection_set(&op.selection_set),
        "directives": op.directives.as_ref().map(|ds| ds.iter().map(serialize_directive).collect::<Vec<_>>()),
        "referenced_fragments": op.referenced_fragments.iter().map(|f| &f.name).collect::<Vec<_>>(),
        "source": op.source,
        "file_path": op.file_path,
    })
}

fn serialize_fragment_def(frag: &FragmentDefinition) -> Value {
    json!({
        "name": frag.name,
        "type_condition": frag.type_.name().schema_name,
        "selection_set": serialize_selection_set(&frag.selection_set),
        "directives": frag.directives.as_ref().map(|ds| ds.iter().map(serialize_directive).collect::<Vec<_>>()),
        "referenced_fragments": frag.referenced_fragments.iter().map(|f| &f.name).collect::<Vec<_>>(),
        "source": frag.source,
        "file_path": frag.file_path,
    })
}

fn serialize_selection_set(ss: &compilation_result::SelectionSet) -> Value {
    json!({
        "parent_type": ss.parent_type.name().schema_name,
        "selections": ss.selections.iter().map(serialize_selection).collect::<Vec<_>>(),
    })
}

fn serialize_selection(sel: &compilation_result::Selection) -> Value {
    match sel {
        compilation_result::Selection::Field(f) => json!({
            "kind": "Field",
            "field": {
                "name": f.name,
                "alias": f.alias,
                "type": serialize_graphql_type(&f.type_),
                "arguments": f.arguments.as_ref().map(|args| args.iter().map(|a| json!({
                    "name": a.name,
                    "type": serialize_graphql_type(&a.type_),
                    "value": serialize_graphql_value(&a.value),
                    "deprecation_reason": a.deprecation_reason,
                })).collect::<Vec<_>>()),
                "inclusion_conditions": f.inclusion_conditions.as_ref().map(|ics| ics.iter().map(serialize_inclusion_condition).collect::<Vec<_>>()),
                "directives": f.directives.as_ref().map(|ds| ds.iter().map(serialize_directive).collect::<Vec<_>>()),
                "selection_set": f.selection_set.as_ref().map(serialize_selection_set),
                "deprecation_reason": f.deprecation_reason,
                "documentation": f.documentation,
            }
        }),
        compilation_result::Selection::InlineFragment(i) => json!({
            "kind": "InlineFragment",
            "inline_fragment": {
                "selection_set": serialize_selection_set(&i.selection_set),
                "inclusion_conditions": i.inclusion_conditions.as_ref().map(|ics| ics.iter().map(serialize_inclusion_condition).collect::<Vec<_>>()),
                "directives": i.directives.as_ref().map(|ds| ds.iter().map(serialize_directive).collect::<Vec<_>>()),
                "defer_condition": i.defer_condition.as_ref().map(|dc| json!({"label": dc.label, "variable": dc.variable})),
            }
        }),
        compilation_result::Selection::FragmentSpread(fs) => json!({
            "kind": "FragmentSpread",
            "fragment_spread": {
                "fragment_name": fs.fragment.name,
                "inclusion_conditions": fs.inclusion_conditions.as_ref().map(|ics| ics.iter().map(serialize_inclusion_condition).collect::<Vec<_>>()),
                "directives": fs.directives.as_ref().map(|ds| ds.iter().map(serialize_directive).collect::<Vec<_>>()),
                "defer_condition": fs.defer_condition.as_ref().map(|dc| json!({"label": dc.label, "variable": dc.variable})),
            }
        }),
    }
}

fn serialize_directive(d: &compilation_result::Directive) -> Value {
    json!({
        "name": d.name,
        "arguments": d.arguments.as_ref().map(|args| args.iter().map(|a| json!({
            "name": a.name,
            "type": serialize_graphql_type(&a.type_),
            "value": serialize_graphql_value(&a.value),
            "deprecation_reason": a.deprecation_reason,
        })).collect::<Vec<_>>()),
    })
}

fn serialize_inclusion_condition(ic: &compilation_result::InclusionCondition) -> Value {
    match ic {
        compilation_result::InclusionCondition::Included => json!({"kind": "Included"}),
        compilation_result::InclusionCondition::Skipped => json!({"kind": "Skipped"}),
        compilation_result::InclusionCondition::Variable { name, is_inverted } => json!({
            "kind": "Variable", "variable": name, "is_inverted": is_inverted,
        }),
    }
}
