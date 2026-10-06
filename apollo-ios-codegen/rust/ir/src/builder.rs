//! IRBuilder -- the main entry point for building IR from a CompilationResult.
//!
//! Mirrors `IRBuilder` from `IRBuilder.swift` (118 lines).
//! All async functions become synchronous per D-32.

use std::sync::{Arc, Mutex};

use graphql_compiler::compilation_result;
use indexmap::IndexMap;

use crate::entity::{Entity, SourceDefinition};
use crate::field_collector::FieldCollector;
use crate::named_fragment::NamedFragment;
use crate::operation::Operation;
use crate::root_field_builder::RootFieldBuilder;
use crate::schema::{ReferencedTypes, Schema};

// MARK: - BuiltFragmentStorage

/// Cache for built fragments to avoid rebuilding the same fragment multiple times.
///
/// In Swift this is an `actor` with a CacheEntry enum (.inProgress, .ready).
/// In Rust, we use `Mutex<IndexMap>` per D-31. Since we're synchronous (D-32),
/// we don't need the .inProgress variant -- we just need deadlock prevention.
///
/// CRITICAL: The lock must be dropped before calling the builder closure to avoid
/// deadlock. Pattern: lock -> check cache -> if found, return clone -> drop lock ->
/// call builder -> re-lock -> insert if absent -> return.
/// (per RESEARCH.md Pitfall 1 / T-04-09)
struct BuiltFragmentStorage {
    cache: Mutex<IndexMap<String, Arc<NamedFragment>>>,
}

impl BuiltFragmentStorage {
    fn new() -> Self {
        BuiltFragmentStorage {
            cache: Mutex::new(IndexMap::new()),
        }
    }

    /// Gets a fragment from cache, or builds it using the provided closure.
    ///
    /// T-04-09: Lock is dropped before calling builder to prevent deadlock.
    /// On re-acquire, checks if another thread inserted while we were building.
    fn get_or_build(
        &self,
        name: &str,
        builder: impl FnOnce() -> Arc<NamedFragment>,
    ) -> Arc<NamedFragment> {
        // Phase 1: Check cache (lock held briefly)
        {
            let cache = self.cache.lock().expect("lock poisoned");
            if let Some(fragment) = cache.get(name) {
                return Arc::clone(fragment);
            }
        } // Lock dropped here before calling builder -- T-04-09 deadlock prevention

        // Phase 2: Build the fragment (no lock held)
        let fragment = builder();

        // Phase 3: Re-acquire lock and insert (double-check pattern)
        {
            let mut cache = self.cache.lock().expect("lock poisoned");
            // Double-check: another thread may have built it while we were building
            if let Some(existing) = cache.get(name) {
                return Arc::clone(existing);
            }
            cache.insert(name.to_string(), Arc::clone(&fragment));
        }

        fragment
    }

    /// Gets a fragment if it was already built, without building it.
    #[allow(dead_code)]
    fn get_if_built(&self, name: &str) -> Option<Arc<NamedFragment>> {
        let cache = self.cache.lock().expect("lock poisoned");
        cache.get(name).cloned()
    }
}

impl std::fmt::Debug for BuiltFragmentStorage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BuiltFragmentStorage").finish()
    }
}

// MARK: - IRBuilder

/// The main builder that constructs IR from a CompilationResult.
///
/// Mirrors `IRBuilder` from `IRBuilder.swift`.
#[derive(Debug)]
pub struct IRBuilder {
    pub compilation_result: Arc<compilation_result::CompilationResult>,
    pub schema: Schema,
    pub field_collector: FieldCollector,
    built_fragment_storage: BuiltFragmentStorage,
}

impl IRBuilder {
    /// Creates a new IRBuilder from a CompilationResult.
    pub fn new(compilation_result: Arc<compilation_result::CompilationResult>) -> Self {
        let schema = Schema::new(
            Arc::new(ReferencedTypes::new(
                &compilation_result.referenced_types,
                compilation_result.schema_root_types.clone(),
            )),
            compilation_result.schema_documentation.clone(),
        );

        IRBuilder {
            compilation_result,
            schema,
            field_collector: FieldCollector::new(),
            built_fragment_storage: BuiltFragmentStorage::new(),
        }
    }

    /// Builds an IR Operation from a CompilationResult OperationDefinition.
    ///
    /// Mirrors Swift's `build(operation:)`. Synchronous per D-32.
    pub fn build_operation(
        &self,
        operation_definition: &Arc<compilation_result::OperationDefinition>,
    ) -> Operation {
        let root_field = compilation_result::Field {
            name: operation_definition.operation_type.to_string(),
            alias: None,
            type_: graphql_compiler::GraphQLType::NonNull(Box::new(
                graphql_compiler::GraphQLType::from_composite(
                    &operation_definition.root_type,
                ),
            )),
            arguments: None,
            inclusion_conditions: None,
            directives: None,
            selection_set: Some(operation_definition.selection_set.clone()),
            deprecation_reason: None,
            documentation: None,
        };

        let root_entity = Arc::new(Entity::new_root(
            SourceDefinition::Operation(Arc::clone(operation_definition)),
        ));

        let result = RootFieldBuilder::build_root_entity_field(
            &root_field,
            root_entity,
            self,
        );

        Operation::new(
            Arc::clone(operation_definition),
            result.root_field,
            result.referenced_fragments,
            result.entity_storage,
            result.contains_deferred_fragment,
        )
    }

    /// Builds an IR NamedFragment from a CompilationResult FragmentDefinition.
    ///
    /// Uses BuiltFragmentStorage to cache and deduplicate fragment builds.
    /// Mirrors Swift's `build(fragment:)`. Synchronous per D-32.
    ///
    /// NOTE: The passed-in `fragment_definition` may be a stale reference (e.g., a stub
    /// from the first pass of fragment compilation). We always look up the canonical
    /// definition from `compilation_result.fragments` by name to ensure we use the
    /// fully-populated version with all selections.
    pub fn build_fragment(
        &self,
        fragment_definition: &Arc<compilation_result::FragmentDefinition>,
    ) -> Arc<NamedFragment> {
        let name = fragment_definition.name.clone();

        // Look up the canonical fragment definition from the compilation result.
        // The passed-in Arc may be a stale stub from the two-pass fragment compilation;
        // the compilation_result.fragments list always has the fully-populated definitions.
        let def = self
            .compilation_result
            .fragments
            .iter()
            .find(|f| f.name == name)
            .map(|f| Arc::new(f.clone()))
            .unwrap_or_else(|| Arc::clone(fragment_definition));

        self.built_fragment_storage.get_or_build(&name, || {
            let root_field = compilation_result::Field {
                name: def.name.clone(),
                alias: None,
                type_: graphql_compiler::GraphQLType::NonNull(Box::new(
                    graphql_compiler::GraphQLType::from_composite(&def.type_),
                )),
                arguments: None,
                inclusion_conditions: None,
                directives: None,
                selection_set: Some(def.selection_set.clone()),
                deprecation_reason: None,
                documentation: None,
            };

            let root_entity = Arc::new(Entity::new_root(
                SourceDefinition::NamedFragment(Arc::clone(&def)),
            ));

            let result = RootFieldBuilder::build_root_entity_field(
                &root_field,
                root_entity,
                self,
            );

            Arc::new(NamedFragment::new(
                Arc::clone(&def),
                result.root_field,
                result.referenced_fragments,
                result.entity_storage,
                result.contains_deferred_fragment,
            ))
        })
    }
}

// MARK: - GraphQLType from_composite helper

/// Extension to create a GraphQLType from a GraphQLCompositeType.
trait GraphQLTypeFromComposite {
    fn from_composite(composite: &graphql_compiler::GraphQLCompositeType) -> Self;
}

impl GraphQLTypeFromComposite for graphql_compiler::GraphQLType {
    fn from_composite(composite: &graphql_compiler::GraphQLCompositeType) -> Self {
        graphql_compiler::GraphQLType::Entity(composite.clone())
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    use graphql_compiler::{
        GraphQLCompositeType, GraphQLName, GraphQLNamedType, GraphQLObjectType,
        RootTypeDefinition,
    };
    use indexmap::IndexMap;

    fn make_object(name: &str) -> Arc<GraphQLObjectType> {
        Arc::new(GraphQLObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        })
    }

    fn make_compilation_result() -> Arc<compilation_result::CompilationResult> {
        let query = make_object("Query");

        Arc::new(compilation_result::CompilationResult {
            schema_root_types: RootTypeDefinition {
                query_type: GraphQLNamedType::Object(Arc::clone(&query)),
                mutation_type: None,
                subscription_type: None,
            },
            referenced_types: vec![GraphQLNamedType::Object(Arc::clone(&query))],
            operations: vec![],
            fragments: vec![],
            schema_documentation: None,
        })
    }

    #[test]
    fn ir_builder_new_creates_valid_schema() {
        let cr = make_compilation_result();
        let builder = IRBuilder::new(cr);

        assert!(builder.schema.referenced_types.objects.len() >= 1);
        assert!(builder.schema.documentation.is_none());
    }

    #[test]
    fn built_fragment_storage_caches_fragment() {
        let storage = BuiltFragmentStorage::new();

        let frag_def = Arc::new(compilation_result::FragmentDefinition {
            name: "TestFragment".to_string(),
            type_: GraphQLCompositeType::Object(make_object("User")),
            selection_set: compilation_result::SelectionSet {
                parent_type: GraphQLCompositeType::Object(make_object("User")),
                selections: vec![],
            },
            directives: None,
            referenced_fragments: vec![],
            source: String::new(),
            file_path: String::new(),
        });

        let def_clone = Arc::clone(&frag_def);

        let mut build_count = 0u32;

        let frag1 = storage.get_or_build("TestFragment", || {
            build_count += 1;
            let root_entity = Arc::new(Entity::new_root(
                SourceDefinition::NamedFragment(Arc::clone(&def_clone)),
            ));
            let entity_storage = crate::definition_entity_storage::DefinitionEntityStorage::new(
                Arc::clone(&root_entity),
            );
            let all_types = Arc::new(ReferencedTypes::new(
                &[GraphQLNamedType::Object(make_object("User"))],
                RootTypeDefinition {
                    query_type: GraphQLNamedType::Object(make_object("Query")),
                    mutation_type: None,
                    subscription_type: None,
                },
            ));
            let scope = crate::scope_descriptor::ScopeDescriptor::descriptor(
                &GraphQLCompositeType::Object(make_object("User")),
                None,
                &all_types,
            );
            let type_info = Arc::new(crate::selection_set::TypeInfo::new(
                Arc::clone(&root_entity),
                utilities::linked_list::LinkedList::new(scope),
            ));
            let ss = Arc::new(crate::selection_set::SelectionSet::new(
                type_info,
                Some(Arc::new(crate::direct_selections::DirectSelections::new())),
            ));
            let root_field = crate::fields::EntityField::new(
                Arc::new(compilation_result::Field {
                    name: "TestFragment".to_string(),
                    alias: None,
                    type_: graphql_compiler::GraphQLType::Entity(GraphQLCompositeType::Object(make_object("User"))),
                    arguments: None,
                    inclusion_conditions: None,
                    directives: None,
                    selection_set: Some(compilation_result::SelectionSet {
                        parent_type: GraphQLCompositeType::Object(make_object("User")),
                        selections: vec![],
                    }),
                    deprecation_reason: None,
                    documentation: None,
                }),
                None,
                ss,
            );
            Arc::new(NamedFragment::new(
                Arc::clone(&def_clone),
                root_field,
                indexmap::IndexSet::new(),
                entity_storage,
                false,
            ))
        });

        assert_eq!(build_count, 1);

        // Second call should return cached
        let frag2 = storage.get_or_build("TestFragment", || {
            build_count += 1;
            panic!("Should not be called");
        });

        assert_eq!(build_count, 1);
        assert!(Arc::ptr_eq(&frag1, &frag2));
    }

    #[test]
    fn built_fragment_storage_builds_different_names() {
        let storage = BuiltFragmentStorage::new();

        let make_fragment = |name: &str| -> Arc<NamedFragment> {
            let frag_def = Arc::new(compilation_result::FragmentDefinition {
                name: name.to_string(),
                type_: GraphQLCompositeType::Object(make_object("User")),
                selection_set: compilation_result::SelectionSet {
                    parent_type: GraphQLCompositeType::Object(make_object("User")),
                    selections: vec![],
                },
                directives: None,
                referenced_fragments: vec![],
                source: String::new(),
                file_path: String::new(),
            });

            let root_entity = Arc::new(Entity::new_root(
                SourceDefinition::NamedFragment(Arc::clone(&frag_def)),
            ));
            let entity_storage = crate::definition_entity_storage::DefinitionEntityStorage::new(
                Arc::clone(&root_entity),
            );
            let all_types = Arc::new(ReferencedTypes::new(
                &[GraphQLNamedType::Object(make_object("User"))],
                RootTypeDefinition {
                    query_type: GraphQLNamedType::Object(make_object("Query")),
                    mutation_type: None,
                    subscription_type: None,
                },
            ));
            let scope = crate::scope_descriptor::ScopeDescriptor::descriptor(
                &GraphQLCompositeType::Object(make_object("User")),
                None,
                &all_types,
            );
            let type_info = Arc::new(crate::selection_set::TypeInfo::new(
                Arc::clone(&root_entity),
                utilities::linked_list::LinkedList::new(scope),
            ));
            let ss = Arc::new(crate::selection_set::SelectionSet::new(
                type_info,
                Some(Arc::new(crate::direct_selections::DirectSelections::new())),
            ));
            let root_field = crate::fields::EntityField::new(
                Arc::new(compilation_result::Field {
                    name: name.to_string(),
                    alias: None,
                    type_: graphql_compiler::GraphQLType::Entity(GraphQLCompositeType::Object(make_object("User"))),
                    arguments: None,
                    inclusion_conditions: None,
                    directives: None,
                    selection_set: Some(compilation_result::SelectionSet {
                        parent_type: GraphQLCompositeType::Object(make_object("User")),
                        selections: vec![],
                    }),
                    deprecation_reason: None,
                    documentation: None,
                }),
                None,
                ss,
            );
            Arc::new(NamedFragment::new(
                frag_def,
                root_field,
                indexmap::IndexSet::new(),
                entity_storage,
                false,
            ))
        };

        let frag_a = storage.get_or_build("FragA", || make_fragment("FragA"));
        let frag_b = storage.get_or_build("FragB", || make_fragment("FragB"));

        assert!(!Arc::ptr_eq(&frag_a, &frag_b));
        assert_eq!(frag_a.name(), "FragA");
        assert_eq!(frag_b.name(), "FragB");
    }
}
