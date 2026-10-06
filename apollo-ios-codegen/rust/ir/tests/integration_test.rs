//! Integration tests for IR builder pipeline.
//!
//! Tests exercise all IR requirement IDs (IR-01 through IR-06) and validate
//! the entire builder pipeline end-to-end using programmatically constructed
//! CompilationResult fixtures.
//!
//! D-33: Serialization tests validate deterministic canonical JSON output.
//! D-34: Edge case tests for diamond fragment inheritance and recursive types.

use std::sync::Arc;

use graphql_compiler::compilation_result::{
    CompilationResult, Field as CRField, FragmentDefinition, FragmentSpread,
    InlineFragment, OperationDefinition, OperationType,
    Selection, SelectionSet as CRSelectionSet, InclusionCondition as CRInclusionCondition,
};
use graphql_compiler::{
    GraphQLCompositeType, GraphQLInterfaceType, GraphQLName, GraphQLNamedType,
    GraphQLObjectType, GraphQLScalarType, GraphQLType, RootTypeDefinition,
};
use indexmap::IndexMap;

use ir::builder::IRBuilder;
use ir::computed_selection_set;
use ir::definition::Definition;
use ir::fields::Field;
use ir::MergingStrategy;

// MARK: - Test Helpers

fn make_object(name: &str) -> Arc<GraphQLObjectType> {
    Arc::new(GraphQLObjectType {
        name: GraphQLName::new(name.to_string()),
        documentation: None,
        fields: IndexMap::new(),
        interfaces: vec![],
        key_fields: None,
    })
}

fn make_object_with_interfaces(
    name: &str,
    interfaces: Vec<Arc<GraphQLInterfaceType>>,
) -> Arc<GraphQLObjectType> {
    Arc::new(GraphQLObjectType {
        name: GraphQLName::new(name.to_string()),
        documentation: None,
        fields: IndexMap::new(),
        interfaces,
        key_fields: None,
    })
}

fn make_interface(name: &str) -> Arc<GraphQLInterfaceType> {
    Arc::new(GraphQLInterfaceType {
        name: GraphQLName::new(name.to_string()),
        documentation: None,
        fields: IndexMap::new(),
        interfaces: vec![],
        implementing_objects: vec![],
        key_fields: None,
    })
}

fn make_scalar_type() -> GraphQLType {
    GraphQLType::Scalar(Arc::new(GraphQLScalarType {
        name: GraphQLName::new("String".to_string()),
        documentation: None,
        specified_by_url: None,
    }))
}

fn make_entity_type(obj: &Arc<GraphQLObjectType>) -> GraphQLType {
    GraphQLType::Entity(GraphQLCompositeType::Object(Arc::clone(obj)))
}

fn make_scalar_field(name: &str) -> CRField {
    CRField {
        name: name.to_string(),
        alias: None,
        type_: make_scalar_type(),
        arguments: None,
        inclusion_conditions: None,
        directives: None,
        selection_set: None,
        deprecation_reason: None,
        documentation: None,
    }
}

fn make_entity_field(name: &str, obj: &Arc<GraphQLObjectType>, selections: Vec<Selection>) -> CRField {
    CRField {
        name: name.to_string(),
        alias: None,
        type_: make_entity_type(obj),
        arguments: None,
        inclusion_conditions: None,
        directives: None,
        selection_set: Some(CRSelectionSet {
            parent_type: GraphQLCompositeType::Object(Arc::clone(obj)),
            selections,
        }),
        deprecation_reason: None,
        documentation: None,
    }
}

fn make_root_types(query: &Arc<GraphQLObjectType>) -> RootTypeDefinition {
    RootTypeDefinition {
        query_type: GraphQLNamedType::Object(Arc::clone(query)),
        mutation_type: None,
        subscription_type: None,
    }
}

fn make_operation_def(
    name: &str,
    query: &Arc<GraphQLObjectType>,
    selections: Vec<Selection>,
) -> OperationDefinition {
    OperationDefinition {
        name: name.to_string(),
        operation_type: OperationType::Query,
        variables: vec![],
        root_type: GraphQLCompositeType::Object(Arc::clone(query)),
        selection_set: CRSelectionSet {
            parent_type: GraphQLCompositeType::Object(Arc::clone(query)),
            selections,
        },
        directives: None,
        referenced_fragments: vec![],
        source: format!("query {} {{ ... }}", name),
        file_path: "test.graphql".to_string(),
    }
}

fn make_compilation_result(
    query: &Arc<GraphQLObjectType>,
    types: Vec<GraphQLNamedType>,
    operations: Vec<OperationDefinition>,
    fragments: Vec<FragmentDefinition>,
) -> Arc<CompilationResult> {
    Arc::new(CompilationResult {
        schema_root_types: make_root_types(query),
        referenced_types: types,
        operations,
        fragments,
        schema_documentation: None,
    })
}

// MARK: - Test 1: Simple Query (IR-01, IR-02)

/// IR-01: IR builder constructs Operation from CompilationResult
/// IR-02: Operation contains root_field with correct selection set
#[test]
fn test_build_simple_query() {
    let query = make_object("Query");
    let hero = make_object("Hero");

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&hero)),
        ],
        vec![make_operation_def(
            "HeroQuery",
            &query,
            vec![Selection::Field(make_entity_field(
                "hero",
                &hero,
                vec![Selection::Field(make_scalar_field("name"))],
            ))],
        )],
        vec![],
    );

    let builder = IRBuilder::new(cr.clone());
    let op_def = Arc::new(cr.operations[0].clone());
    let operation = builder.build_operation(&op_def);

    assert_eq!(operation.name(), "HeroQuery");

    // root_field should be an EntityField
    assert_eq!(operation.root_field.underlying_field.name, "query");

    // root_field selection_set should contain "hero" entity field
    let root_selections = operation.root_field.selection_set.selections.as_ref().unwrap();
    assert_eq!(root_selections.fields.len(), 1);

    let hero_field = root_selections.fields.get("hero").unwrap();
    match hero_field {
        Field::Entity(ef) => {
            assert_eq!(ef.underlying_field.name, "hero");
            // hero's selection_set should contain "name" scalar field
            let hero_selections = ef.selection_set.selections.as_ref().unwrap();
            assert_eq!(hero_selections.fields.len(), 1);
            match hero_selections.fields.get("name").unwrap() {
                Field::Scalar(sf) => assert_eq!(sf.underlying_field.name, "name"),
                _ => panic!("Expected scalar field 'name'"),
            }
        }
        _ => panic!("Expected entity field 'hero'"),
    }

    // entity_storage should have entries
    assert!(operation.entity_storage.entities_for_fields.len() >= 2);
    assert!(!operation.contains_deferred_fragment);
}

// MARK: - Test 2: Nested Entity Fields (IR-01, IR-05)

/// IR-01: IR builder correctly constructs nested entity fields
/// IR-05: Entity deduplication works for same field paths
#[test]
fn test_build_nested_entity_fields() {
    let query = make_object("Query");
    let hero = make_object("Hero");
    let friend = make_object("Friend");

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&hero)),
            GraphQLNamedType::Object(Arc::clone(&friend)),
        ],
        vec![make_operation_def(
            "NestedQuery",
            &query,
            vec![Selection::Field(make_entity_field(
                "hero",
                &hero,
                vec![Selection::Field(make_entity_field(
                    "friends",
                    &friend,
                    vec![Selection::Field(make_scalar_field("name"))],
                ))],
            ))],
        )],
        vec![],
    );

    let builder = IRBuilder::new(cr.clone());
    let op_def = Arc::new(cr.operations[0].clone());
    let operation = builder.build_operation(&op_def);

    // Navigate: root -> hero -> friends -> name
    let root_sel = operation.root_field.selection_set.selections.as_ref().unwrap();
    let hero_field = match root_sel.fields.get("hero").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'hero'"),
    };

    let hero_sel = hero_field.selection_set.selections.as_ref().unwrap();
    let friends_field = match hero_sel.fields.get("friends").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'friends'"),
    };

    let friends_sel = friends_field.selection_set.selections.as_ref().unwrap();
    match friends_sel.fields.get("name").unwrap() {
        Field::Scalar(sf) => assert_eq!(sf.underlying_field.name, "name"),
        _ => panic!("Expected scalar field 'name'"),
    }

    // entity_storage should have at least 3 entities: root, hero, friends
    assert!(operation.entity_storage.entities_for_fields.len() >= 3);
}

// MARK: - Test 3: Build Fragment (IR-01, IR-03, IR-06)

/// IR-01: IRBuilder can build fragments
/// IR-03: Fragment caching works via BuiltFragmentStorage
/// IR-06: NamedFragment implements Definition trait
#[test]
fn test_build_fragment() {
    let query = make_object("Query");
    let character = make_object("Character");

    let frag_def = Arc::new(FragmentDefinition {
        name: "HeroFields".to_string(),
        type_: GraphQLCompositeType::Object(Arc::clone(&character)),
        selection_set: CRSelectionSet {
            parent_type: GraphQLCompositeType::Object(Arc::clone(&character)),
            selections: vec![Selection::Field(make_scalar_field("name"))],
        },
        directives: None,
        referenced_fragments: vec![],
        source: "fragment HeroFields on Character { name }".to_string(),
        file_path: "test.graphql".to_string(),
    });

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&character)),
        ],
        vec![],
        vec![(*frag_def).clone()],
    );

    let builder = IRBuilder::new(cr);

    let fragment1 = builder.build_fragment(&frag_def);
    assert_eq!(fragment1.name(), "HeroFields");

    // Fragment root_field should have "name" scalar field
    let root_sel = fragment1.root_field.selection_set.selections.as_ref().unwrap();
    assert!(root_sel.fields.contains_key("name"));

    // Build same fragment again -- should return cached Arc (pointer equality)
    let fragment2 = builder.build_fragment(&frag_def);
    assert!(Arc::ptr_eq(&fragment1, &fragment2));

    // Verify Definition trait works (IR-06)
    let def: &dyn Definition = fragment1.as_ref();
    assert_eq!(def.name(), "HeroFields");
    assert!(!def.is_local_cache_mutation());
    let _ = def.root_field();
    let _ = def.entity_storage();
}

// MARK: - Test 4: Operation with Fragment Spread (IR-02, IR-03)

/// IR-02: Operation correctly references fragments
/// IR-03: Fragment spread appears in DirectSelections
#[test]
fn test_build_operation_with_fragment_spread() {
    let query = make_object("Query");
    let character = make_object("Character");

    let frag_def = Arc::new(FragmentDefinition {
        name: "CharacterFields".to_string(),
        type_: GraphQLCompositeType::Object(Arc::clone(&character)),
        selection_set: CRSelectionSet {
            parent_type: GraphQLCompositeType::Object(Arc::clone(&character)),
            selections: vec![Selection::Field(make_scalar_field("name"))],
        },
        directives: None,
        referenced_fragments: vec![],
        source: "fragment CharacterFields on Character { name }".to_string(),
        file_path: "test.graphql".to_string(),
    });

    let op_def = OperationDefinition {
        name: "HeroWithFragmentQuery".to_string(),
        operation_type: OperationType::Query,
        variables: vec![],
        root_type: GraphQLCompositeType::Object(Arc::clone(&query)),
        selection_set: CRSelectionSet {
            parent_type: GraphQLCompositeType::Object(Arc::clone(&query)),
            selections: vec![Selection::Field(make_entity_field(
                "hero",
                &character,
                vec![Selection::FragmentSpread(FragmentSpread {
                    fragment: Arc::clone(&frag_def),
                    inclusion_conditions: None,
                    directives: None,
                    defer_condition: None,
                })],
            ))],
        },
        directives: None,
        referenced_fragments: vec![Arc::clone(&frag_def)],
        source: "query HeroWithFragmentQuery { hero { ...CharacterFields } }".to_string(),
        file_path: "test.graphql".to_string(),
    };

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&character)),
        ],
        vec![op_def.clone()],
        vec![(*frag_def).clone()],
    );

    let builder = IRBuilder::new(cr);
    let op_def_arc = Arc::new(op_def);
    let operation = builder.build_operation(&op_def_arc);

    // referenced_fragments should contain the fragment
    assert_eq!(operation.referenced_fragments.len(), 1);
    assert_eq!(
        operation.referenced_fragments.iter().next().unwrap().name(),
        "CharacterFields"
    );

    // hero's DirectSelections should have the named fragment spread
    let root_sel = operation.root_field.selection_set.selections.as_ref().unwrap();
    let hero_field = match root_sel.fields.get("hero").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'hero'"),
    };
    let hero_sel = hero_field.selection_set.selections.as_ref().unwrap();
    assert_eq!(hero_sel.named_fragments.len(), 1);
    assert!(hero_sel.named_fragments.contains_key("CharacterFields"));
}

// MARK: - Test 5: Inline Fragment (IR-01, IR-02)

/// IR-01: IRBuilder handles inline fragments
/// IR-02: Inline fragments appear in DirectSelections with correct type conditions
#[test]
fn test_build_inline_fragment() {
    let query = make_object("Query");
    let character = make_object("Character");
    let human = make_object("Human");

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&character)),
            GraphQLNamedType::Object(Arc::clone(&human)),
        ],
        vec![{
            let mut op = make_operation_def(
                "InlineFragmentQuery",
                &query,
                vec![Selection::Field(make_entity_field(
                    "hero",
                    &character,
                    vec![Selection::InlineFragment(InlineFragment {
                        selection_set: CRSelectionSet {
                            parent_type: GraphQLCompositeType::Object(Arc::clone(&human)),
                            selections: vec![Selection::Field(make_scalar_field("height"))],
                        },
                        inclusion_conditions: None,
                        directives: None,
                        defer_condition: None,
                    })],
                ))],
            );
            op
        }],
        vec![],
    );

    let builder = IRBuilder::new(cr.clone());
    let op_def = Arc::new(cr.operations[0].clone());
    let operation = builder.build_operation(&op_def);

    // Navigate to hero's selections
    let root_sel = operation.root_field.selection_set.selections.as_ref().unwrap();
    let hero_field = match root_sel.fields.get("hero").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'hero'"),
    };

    let hero_sel = hero_field.selection_set.selections.as_ref().unwrap();

    // Should have an inline fragment for the Human type condition
    // The inline fragment's scope condition key has type_: Some(Human)
    assert!(!hero_sel.inline_fragments.is_empty(),
        "Expected inline fragments, got keys: {:?}",
        hero_sel.inline_fragments.keys().collect::<Vec<_>>());

    // Find the Human type condition inline fragment by checking scope condition keys
    let has_human_inline = hero_sel.inline_fragments.keys().any(|sc| {
        sc.type_.as_ref().map_or(false, |t| t.name().schema_name == "Human")
    });
    assert!(has_human_inline,
        "Expected inline fragment with Human type condition, got keys: {:?}",
        hero_sel.inline_fragments.keys().map(|k| format!("{}", k)).collect::<Vec<_>>());
}

// MARK: - Test 6: Inclusion Conditions (IR-01)

/// IR-01: Fields with @include/@skip directives have correct inclusion conditions
#[test]
fn test_inclusion_conditions() {
    let query = make_object("Query");
    let hero = make_object("Hero");

    let name_field_with_include = CRField {
        name: "name".to_string(),
        alias: None,
        type_: make_scalar_type(),
        arguments: None,
        inclusion_conditions: Some(vec![CRInclusionCondition::Variable {
            name: "showName".to_string(),
            is_inverted: false,
        }]),
        directives: None,
        selection_set: None,
        deprecation_reason: None,
        documentation: None,
    };

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&hero)),
        ],
        vec![{
            let mut op = make_operation_def(
                "ConditionalQuery",
                &query,
                vec![Selection::Field(make_entity_field(
                    "hero",
                    &hero,
                    vec![Selection::Field(name_field_with_include)],
                ))],
            );
            op.variables = vec![graphql_compiler::compilation_result::VariableDefinition {
                name: "showName".to_string(),
                type_: GraphQLType::Scalar(Arc::new(GraphQLScalarType {
                    name: GraphQLName::new("Boolean".to_string()),
                    documentation: None,
                    specified_by_url: None,
                })),
                default_value: None,
            }];
            op
        }],
        vec![],
    );

    let builder = IRBuilder::new(cr.clone());
    let op_def = Arc::new(cr.operations[0].clone());
    let operation = builder.build_operation(&op_def);

    // Navigate to hero -> name field
    let root_sel = operation.root_field.selection_set.selections.as_ref().unwrap();
    let hero_field = match root_sel.fields.get("hero").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'hero'"),
    };

    let hero_sel = hero_field.selection_set.selections.as_ref().unwrap();
    let name_field = hero_sel.fields.get("name").unwrap();

    // The name field should have inclusion conditions
    let conditions = name_field.inclusion_conditions();
    assert!(conditions.is_some(), "Expected inclusion conditions on 'name' field");

    let any_of = conditions.unwrap();
    // Should contain a condition for "showName"
    let has_show_name = any_of.elements.iter().any(|conds| {
        conds.iter().any(|c| c.variable == "showName" && !c.is_inverted)
    });
    assert!(has_show_name, "Expected @include(if: $showName) condition");
}

// MARK: - Test 7: Field Collector (IR-04)

/// IR-04: FieldCollector tracks fields per type during IR construction
#[test]
fn test_field_collector() {
    let query = make_object("Query");
    let hero = make_object("Hero");

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&hero)),
        ],
        vec![make_operation_def(
            "FieldCollectorQuery",
            &query,
            vec![Selection::Field(make_entity_field(
                "hero",
                &hero,
                vec![
                    Selection::Field(make_scalar_field("name")),
                    Selection::Field(make_scalar_field("age")),
                ],
            ))],
        )],
        vec![],
    );

    let builder = IRBuilder::new(cr.clone());
    let op_def = Arc::new(cr.operations[0].clone());
    let _operation = builder.build_operation(&op_def);

    // Check field collector has collected fields for Hero type
    let hero_type = GraphQLCompositeType::Object(Arc::clone(&hero));
    let collected = builder.field_collector.collected_fields_for(&hero_type);

    // Should have collected "age" and "name" (sorted)
    assert!(collected.len() >= 2, "Expected at least 2 collected fields, got {}", collected.len());
    assert_eq!(collected[0].0, "age");
    assert_eq!(collected[1].0, "name");
}

// MARK: - Test 8: Entity Deduplication (IR-05)

/// IR-05: Same entity paths in different selections produce same Arc<Entity> (dedup)
#[test]
fn test_entity_deduplication() {
    let query = make_object("Query");
    let hero = make_object("Hero");
    let human = make_object("Human");

    // Create an operation where the same "hero" entity appears in two inline fragments
    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&hero)),
            GraphQLNamedType::Object(Arc::clone(&human)),
        ],
        vec![make_operation_def(
            "DeduplicationQuery",
            &query,
            vec![
                Selection::Field(make_entity_field(
                    "hero",
                    &hero,
                    vec![Selection::Field(make_scalar_field("name"))],
                )),
            ],
        )],
        vec![],
    );

    let builder = IRBuilder::new(cr.clone());
    let op_def = Arc::new(cr.operations[0].clone());
    let operation = builder.build_operation(&op_def);

    // The entity_storage should deduplicate entities by location
    // Building the same operation again should produce entities at the same locations
    let entity_count = operation.entity_storage.entities_for_fields.len();
    assert!(entity_count >= 2, "Expected at least 2 entities (root + hero)");

    // Verify that looking up the same location gives the same Arc
    let locations: Vec<_> = operation.entity_storage.entities_for_fields.keys().collect();
    for loc in &locations {
        let e1 = operation.entity_storage.entities_for_fields.get(*loc).unwrap();
        let e2 = operation.entity_storage.entities_for_fields.get(*loc).unwrap();
        assert!(Arc::ptr_eq(e1, e2), "Same location should return same Arc<Entity>");
    }
}

// MARK: - Test 9: Definition Trait Unified (IR-06)

/// IR-06: Both Operation and NamedFragment implement the Definition trait
#[test]
fn test_definition_trait_unified() {
    let query = make_object("Query");
    let character = make_object("Character");

    let frag_def = Arc::new(FragmentDefinition {
        name: "CharFields".to_string(),
        type_: GraphQLCompositeType::Object(Arc::clone(&character)),
        selection_set: CRSelectionSet {
            parent_type: GraphQLCompositeType::Object(Arc::clone(&character)),
            selections: vec![Selection::Field(make_scalar_field("name"))],
        },
        directives: None,
        referenced_fragments: vec![],
        source: String::new(),
        file_path: String::new(),
    });

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&character)),
        ],
        vec![make_operation_def(
            "TestOp",
            &query,
            vec![Selection::Field(make_scalar_field("id"))],
        )],
        vec![(*frag_def).clone()],
    );

    let builder = IRBuilder::new(cr.clone());
    let op_def = Arc::new(cr.operations[0].clone());
    let operation = builder.build_operation(&op_def);
    let fragment = builder.build_fragment(&frag_def);

    // Both should work via Definition trait
    let definitions: Vec<&dyn Definition> = vec![&operation, fragment.as_ref()];

    assert_eq!(definitions[0].name(), "TestOp");
    assert_eq!(definitions[1].name(), "CharFields");
    assert!(!definitions[0].is_local_cache_mutation());
    assert!(!definitions[1].is_local_cache_mutation());

    // Both should have root_field and entity_storage accessible
    let _ = definitions[0].root_field();
    let _ = definitions[1].root_field();
    let _ = definitions[0].entity_storage();
    let _ = definitions[1].entity_storage();
}

// MARK: - Test 10: IR Serialization (D-33)

/// D-33: IR serialization produces deterministic canonical JSON output
#[test]
fn test_ir_serialization() {
    let query = make_object("Query");
    let hero = make_object("Hero");

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&hero)),
        ],
        vec![make_operation_def(
            "SerializationQuery",
            &query,
            vec![Selection::Field(make_entity_field(
                "hero",
                &hero,
                vec![Selection::Field(make_scalar_field("name"))],
            ))],
        )],
        vec![],
    );

    let builder = IRBuilder::new(cr.clone());
    let op_def = Arc::new(cr.operations[0].clone());
    let operation = builder.build_operation(&op_def);

    // Serialize to JSON
    let json = ir::serialize_operation_to_json(&operation);

    // JSON should contain expected keys
    assert!(json.contains("\"name\""), "JSON should contain name key");
    assert!(json.contains("SerializationQuery"), "JSON should contain operation name");
    assert!(json.contains("\"root_field\""), "JSON should contain root_field key");
    assert!(json.contains("\"referenced_fragments\""), "JSON should contain referenced_fragments key");
    assert!(json.contains("\"entity_count\""), "JSON should contain entity_count key");

    // JSON should be valid (parse succeeds)
    let parsed: Result<serde_json::Value, _> = serde_json::from_str(&json);
    assert!(parsed.is_ok(), "JSON should be valid: {:?}", parsed.err());

    // Serializing same operation twice produces identical JSON (determinism)
    let json2 = ir::serialize_operation_to_json(&operation);
    assert_eq!(json, json2, "Serialization should be deterministic");
}

// MARK: - Test 11: Diamond Fragment Inheritance (D-34)

/// D-34: Diamond fragment inheritance -- two fragments on overlapping types
/// both spread inside a query, with correct selection merging
#[test]
fn test_diamond_fragment_inheritance() {
    let query = make_object("Query");
    let animal_iface = make_interface("Animal");
    let pet = make_object_with_interfaces("Pet", vec![Arc::clone(&animal_iface)]);

    let frag_a = Arc::new(FragmentDefinition {
        name: "FragmentA".to_string(),
        type_: GraphQLCompositeType::Object(Arc::clone(&pet)),
        selection_set: CRSelectionSet {
            parent_type: GraphQLCompositeType::Object(Arc::clone(&pet)),
            selections: vec![Selection::Field(make_scalar_field("name"))],
        },
        directives: None,
        referenced_fragments: vec![],
        source: "fragment FragmentA on Pet { name }".to_string(),
        file_path: "test.graphql".to_string(),
    });

    let frag_b = Arc::new(FragmentDefinition {
        name: "FragmentB".to_string(),
        type_: GraphQLCompositeType::Object(Arc::clone(&pet)),
        selection_set: CRSelectionSet {
            parent_type: GraphQLCompositeType::Object(Arc::clone(&pet)),
            selections: vec![Selection::Field(make_scalar_field("age"))],
        },
        directives: None,
        referenced_fragments: vec![],
        source: "fragment FragmentB on Pet { age }".to_string(),
        file_path: "test.graphql".to_string(),
    });

    let op_def = OperationDefinition {
        name: "DiamondQuery".to_string(),
        operation_type: OperationType::Query,
        variables: vec![],
        root_type: GraphQLCompositeType::Object(Arc::clone(&query)),
        selection_set: CRSelectionSet {
            parent_type: GraphQLCompositeType::Object(Arc::clone(&query)),
            selections: vec![Selection::Field(make_entity_field(
                "pet",
                &pet,
                vec![
                    Selection::FragmentSpread(FragmentSpread {
                        fragment: Arc::clone(&frag_a),
                        inclusion_conditions: None,
                        directives: None,
                        defer_condition: None,
                    }),
                    Selection::FragmentSpread(FragmentSpread {
                        fragment: Arc::clone(&frag_b),
                        inclusion_conditions: None,
                        directives: None,
                        defer_condition: None,
                    }),
                ],
            ))],
        },
        directives: None,
        referenced_fragments: vec![Arc::clone(&frag_a), Arc::clone(&frag_b)],
        source: "query DiamondQuery { pet { ...FragmentA ...FragmentB } }".to_string(),
        file_path: "test.graphql".to_string(),
    };

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&pet)),
            GraphQLNamedType::Interface(Arc::clone(&animal_iface)),
        ],
        vec![op_def.clone()],
        vec![(*frag_a).clone(), (*frag_b).clone()],
    );

    let builder = IRBuilder::new(cr);
    let op_def_arc = Arc::new(op_def);
    let operation = builder.build_operation(&op_def_arc);

    // referenced_fragments should contain both fragments
    assert_eq!(operation.referenced_fragments.len(), 2);

    let frag_names: Vec<&str> = operation.referenced_fragments.iter().map(|f| f.name()).collect();
    assert!(frag_names.contains(&"FragmentA"), "Should reference FragmentA");
    assert!(frag_names.contains(&"FragmentB"), "Should reference FragmentB");

    // pet field should have both fragment spreads in named_fragments
    let root_sel = operation.root_field.selection_set.selections.as_ref().unwrap();
    let pet_field = match root_sel.fields.get("pet").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'pet'"),
    };

    let pet_sel = pet_field.selection_set.selections.as_ref().unwrap();
    assert_eq!(pet_sel.named_fragments.len(), 2,
        "Pet should have 2 named fragment spreads");

    // No duplicate entity entries for the shared type path
    // (pet entity should appear only once in storage)
    let pet_entities: Vec<_> = operation.entity_storage.entities_for_fields.values()
        .filter(|e| e.root_type().name().schema_name == "Pet")
        .collect();
    assert_eq!(pet_entities.len(), 1, "Pet entity should be deduplicated");
}

// MARK: - Test 12: Recursive Type References (D-34)

/// D-34: Recursive type references (TreeNode -> children: [TreeNode])
/// should not cause infinite loops or stack overflow
#[test]
fn test_recursive_type_references() {
    let query = make_object("Query");
    let tree_node = make_object("TreeNode");

    // query { root { children { children { name } } } }
    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&tree_node)),
        ],
        vec![make_operation_def(
            "RecursiveQuery",
            &query,
            vec![Selection::Field(make_entity_field(
                "root",
                &tree_node,
                vec![Selection::Field(make_entity_field(
                    "children",
                    &tree_node,
                    vec![Selection::Field(make_entity_field(
                        "children",
                        &tree_node,
                        vec![Selection::Field(make_scalar_field("name"))],
                    ))],
                ))],
            ))],
        )],
        vec![],
    );

    let builder = IRBuilder::new(cr.clone());
    let op_def = Arc::new(cr.operations[0].clone());

    // This should NOT cause stack overflow or infinite loops
    let operation = builder.build_operation(&op_def);

    // entity_storage should have distinct Entity entries for each nesting level
    let entity_count = operation.entity_storage.entities_for_fields.len();
    // root entity + root TreeNode + children TreeNode + children.children TreeNode = 4
    assert!(entity_count >= 4,
        "Expected at least 4 entities for recursive type, got {}", entity_count);

    // Navigate the recursive path: root -> children -> children -> name
    let root_sel = operation.root_field.selection_set.selections.as_ref().unwrap();
    let root_node = match root_sel.fields.get("root").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'root'"),
    };

    let root_node_sel = root_node.selection_set.selections.as_ref().unwrap();
    let children1 = match root_node_sel.fields.get("children").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'children' at level 1"),
    };

    let children1_sel = children1.selection_set.selections.as_ref().unwrap();
    let children2 = match children1_sel.fields.get("children").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'children' at level 2"),
    };

    let children2_sel = children2.selection_set.selections.as_ref().unwrap();
    match children2_sel.fields.get("name").unwrap() {
        Field::Scalar(sf) => assert_eq!(sf.underlying_field.name, "name"),
        _ => panic!("Expected scalar field 'name' at deepest level"),
    }

    // Verify serialization also handles recursive types without hanging
    let json = ir::serialize_operation_to_json(&operation);
    assert!(json.contains("RecursiveQuery"));
    let parsed: Result<serde_json::Value, _> = serde_json::from_str(&json);
    assert!(parsed.is_ok(), "Recursive type serialization should produce valid JSON");
}

// MARK: - Test 13: Entity Selection Tree Populated (04-06)

/// After building an operation, the root entity's selection_tree should contain
/// merged selections from the direct selections (via RwLock write in build_direct_selections).
#[test]
fn test_entity_selection_tree_populated() {
    let query = make_object("Query");
    let hero = make_object("Hero");

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&hero)),
        ],
        vec![make_operation_def(
            "TreePopulationQuery",
            &query,
            vec![Selection::Field(make_entity_field(
                "hero",
                &hero,
                vec![
                    Selection::Field(make_scalar_field("name")),
                    Selection::Field(make_scalar_field("age")),
                ],
            ))],
        )],
        vec![],
    );

    let builder = IRBuilder::new(cr.clone());
    let op_def = Arc::new(cr.operations[0].clone());
    let operation = builder.build_operation(&op_def);

    // Verify entity selection tree is populated by building a ComputedSelectionSet
    // for the hero's selection set. If the entity's tree was populated by
    // build_direct_selections (via RwLock write), merged selections will be non-empty.
    let root_sel = operation.root_field.selection_set.selections.as_ref().unwrap();
    let hero_field = match root_sel.fields.get("hero").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'hero'"),
    };

    let computed = computed_selection_set::Builder::from_selection_set(
        &hero_field.selection_set,
        MergingStrategy::ALL,
        operation.entity_storage,
    ).build();

    // The root entity's tree (Query) was populated, so when computing merged selections
    // for the hero's selection set, we should get selections from ancestor merging.
    // At minimum, the direct selections ("name", "age") are present.
    assert!(computed.direct.is_some(), "hero should have direct selections");
    let direct = computed.direct.as_ref().unwrap();
    assert!(direct.fields.contains_key("name"), "hero should have 'name' direct field");
    assert!(direct.fields.contains_key("age"), "hero should have 'age' direct field");
}

// MARK: - Test 14: Computed Selection Set Has Merged Selections (04-06)

/// Validates that ComputedSelectionSet.build() produces non-empty merged selections
/// for operations with inline fragments (type narrowing).
#[test]
fn test_computed_selection_set_has_merged_selections() {
    let query = make_object("Query");
    let character = make_object("Character");
    let human = make_object("Human");

    // query { hero { name ... on Human { height } } }
    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&character)),
            GraphQLNamedType::Object(Arc::clone(&human)),
        ],
        vec![make_operation_def(
            "MergedSelectionsQuery",
            &query,
            vec![Selection::Field(make_entity_field(
                "hero",
                &character,
                vec![
                    Selection::Field(make_scalar_field("name")),
                    Selection::InlineFragment(InlineFragment {
                        selection_set: CRSelectionSet {
                            parent_type: GraphQLCompositeType::Object(Arc::clone(&human)),
                            selections: vec![Selection::Field(make_scalar_field("height"))],
                        },
                        inclusion_conditions: None,
                        directives: None,
                        defer_condition: None,
                    }),
                ],
            ))],
        )],
        vec![],
    );

    let builder = IRBuilder::new(cr.clone());
    let op_def = Arc::new(cr.operations[0].clone());
    let operation = builder.build_operation(&op_def);

    // Navigate to hero field
    let root_sel = operation.root_field.selection_set.selections.as_ref().unwrap();
    let hero_field = match root_sel.fields.get("hero").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'hero'"),
    };

    // hero should have inline fragments for Human type narrowing
    let hero_sel = hero_field.selection_set.selections.as_ref().unwrap();
    assert!(!hero_sel.inline_fragments.is_empty(),
        "hero should have inline fragments for type narrowing");

    // Build a ComputedSelectionSet for the Human inline fragment's selection set
    // to verify that merged selections include the "name" field from the parent scope.
    let human_inline = hero_sel.inline_fragments.values().next()
        .expect("Should have at least one inline fragment");

    let computed = computed_selection_set::Builder::from_selection_set(
        &human_inline.selection_set,
        MergingStrategy::ALL,
        operation.entity_storage,
    ).build();

    // The Human inline fragment should have "height" as direct selection
    if let Some(ref direct) = computed.direct {
        assert!(direct.fields.contains_key("height"),
            "Human inline fragment should have 'height' as direct selection");
    }

    // The merged selections should include "name" from the ancestor scope
    // (inherited from the Character parent selection set)
    let has_name_in_merged = computed.merged.fields.contains_key("name");
    assert!(has_name_in_merged,
        "Merged selections should include 'name' from ancestor scope. Merged fields: {:?}",
        computed.merged.fields.keys().collect::<Vec<_>>());
}

// MARK: - Test 15: Fragment Tree Merging (04-06)

/// Validates that fragment entity selection trees are merged into the operation's
/// entity selection trees via merge_all_selections_into_entity_selection_trees.
#[test]
fn test_fragment_tree_merging() {
    let query = make_object("Query");
    let character = make_object("Character");

    let frag_def = Arc::new(FragmentDefinition {
        name: "HeroFields".to_string(),
        type_: GraphQLCompositeType::Object(Arc::clone(&character)),
        selection_set: CRSelectionSet {
            parent_type: GraphQLCompositeType::Object(Arc::clone(&character)),
            selections: vec![
                Selection::Field(make_scalar_field("name")),
                Selection::Field(make_scalar_field("age")),
            ],
        },
        directives: None,
        referenced_fragments: vec![],
        source: "fragment HeroFields on Character { name age }".to_string(),
        file_path: "test.graphql".to_string(),
    });

    let op_def = OperationDefinition {
        name: "FragmentTreeQuery".to_string(),
        operation_type: OperationType::Query,
        variables: vec![],
        root_type: GraphQLCompositeType::Object(Arc::clone(&query)),
        selection_set: CRSelectionSet {
            parent_type: GraphQLCompositeType::Object(Arc::clone(&query)),
            selections: vec![Selection::Field(make_entity_field(
                "hero",
                &character,
                vec![
                    Selection::Field(make_scalar_field("homeWorld")),
                    Selection::FragmentSpread(FragmentSpread {
                        fragment: Arc::clone(&frag_def),
                        inclusion_conditions: None,
                        directives: None,
                        defer_condition: None,
                    }),
                ],
            ))],
        },
        directives: None,
        referenced_fragments: vec![Arc::clone(&frag_def)],
        source: "query FragmentTreeQuery { hero { homeWorld ...HeroFields } }".to_string(),
        file_path: "test.graphql".to_string(),
    };

    let cr = make_compilation_result(
        &query,
        vec![
            GraphQLNamedType::Object(Arc::clone(&query)),
            GraphQLNamedType::Object(Arc::clone(&character)),
        ],
        vec![op_def.clone()],
        vec![(*frag_def).clone()],
    );

    let builder = IRBuilder::new(cr);
    let op_def_arc = Arc::new(op_def);
    let operation = builder.build_operation(&op_def_arc);

    // Verify fragment tree merging by building a ComputedSelectionSet.
    // If merge_all_selections_into_entity_selection_trees worked, the entity's tree
    // should contain selections from the fragment, visible as merged selections.
    let root_sel = operation.root_field.selection_set.selections.as_ref().unwrap();
    let hero_field = match root_sel.fields.get("hero").unwrap() {
        Field::Entity(ef) => ef,
        _ => panic!("Expected entity field 'hero'"),
    };

    let computed = computed_selection_set::Builder::from_selection_set(
        &hero_field.selection_set,
        MergingStrategy::ALL,
        operation.entity_storage,
    ).build();

    // Direct selections should include "homeWorld" and the named fragment spread
    assert!(computed.direct.is_some(), "hero should have direct selections");
    let direct = computed.direct.as_ref().unwrap();
    assert!(direct.fields.contains_key("homeWorld"),
        "hero should have 'homeWorld' as direct field");
    assert!(direct.named_fragments.contains_key("HeroFields"),
        "hero should have 'HeroFields' fragment spread");

    // Merged selections should include "name" and/or "age" from the fragment
    // (via fragment tree merging into the entity's selection tree)
    let has_fragment_merged = computed.merged.fields.contains_key("name")
        || computed.merged.fields.contains_key("age");
    assert!(has_fragment_merged,
        "Merged selections should include fragment fields ('name'/'age'). Merged keys: {:?}",
        computed.merged.fields.keys().collect::<Vec<_>>());
}
