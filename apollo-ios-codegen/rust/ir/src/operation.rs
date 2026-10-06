use std::fmt;
use std::sync::Arc;

use graphql_compiler::compilation_result;
use indexmap::IndexSet;

use crate::definition::Definition;
use crate::definition_entity_storage::DefinitionEntityStorage;
use crate::fields::EntityField;
use crate::named_fragment::NamedFragment;

// MARK: - Operation

/// A built operation in the IR.
///
/// Mirrors `IR.Operation` from `IR+Operation.swift`.
#[derive(Debug)]
pub struct Operation {
    pub definition: Arc<compilation_result::OperationDefinition>,

    /// The root field of the operation. This field must be the root query, mutation, or
    /// subscription field of the schema.
    pub root_field: EntityField,

    /// All of the fragments that are referenced by this operation's selection set.
    pub referenced_fragments: IndexSet<Arc<NamedFragment>>,

    pub entity_storage: DefinitionEntityStorage,

    /// `True` if any selection set, or nested selection set, within the operation contains any
    /// fragment marked with the `@defer` directive.
    pub contains_deferred_fragment: bool,
}

impl Operation {
    pub fn new(
        definition: Arc<compilation_result::OperationDefinition>,
        root_field: EntityField,
        referenced_fragments: IndexSet<Arc<NamedFragment>>,
        entity_storage: DefinitionEntityStorage,
        contains_deferred_fragment: bool,
    ) -> Self {
        Operation {
            definition,
            root_field,
            referenced_fragments,
            entity_storage,
            contains_deferred_fragment,
        }
    }
}

impl Definition for Operation {
    fn name(&self) -> &str {
        &self.definition.name
    }

    fn root_field(&self) -> &EntityField {
        &self.root_field
    }

    fn entity_storage(&self) -> &DefinitionEntityStorage {
        &self.entity_storage
    }

    fn is_local_cache_mutation(&self) -> bool {
        self.definition.is_local_cache_mutation()
    }
}

impl fmt::Display for Operation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} {{\n  {:?}\n}}", self.definition, self.root_field)
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    use crate::definition_entity_storage::DefinitionEntityStorage;
    use crate::direct_selections::DirectSelections;
    use crate::entity::{Entity, SourceDefinition};
    use crate::fields::EntityField;
    use crate::selection_set::{SelectionSet, TypeInfo};
    use graphql_compiler::compilation_result::{
        OperationDefinition, OperationType, SelectionSet as CRSelectionSet,
    };
    use graphql_compiler::{GraphQLCompositeType, GraphQLName, GraphQLObjectType, GraphQLScalarType, GraphQLType};
    use crate::schema::ReferencedTypes;
    use crate::scope_descriptor::ScopeDescriptor;
    use graphql_compiler::{GraphQLNamedType, RootTypeDefinition};
    use indexmap::IndexMap;
    use utilities::linked_list::LinkedList;

    fn make_object(name: &str) -> Arc<GraphQLObjectType> {
        Arc::new(GraphQLObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        })
    }

    fn make_root_types() -> RootTypeDefinition {
        RootTypeDefinition {
            query_type: GraphQLNamedType::Object(make_object("Query")),
            mutation_type: None,
            subscription_type: None,
        }
    }

    fn make_test_operation() -> Operation {
        let query = make_object("Query");
        let query_type = GraphQLCompositeType::Object(Arc::clone(&query));

        let op_def = Arc::new(OperationDefinition {
            name: "TestQuery".to_string(),
            operation_type: OperationType::Query,
            variables: vec![],
            root_type: query_type.clone(),
            selection_set: CRSelectionSet {
                parent_type: query_type.clone(),
                selections: vec![],
            },
            directives: None,
            referenced_fragments: vec![],
            source: "query TestQuery { id }".to_string(),
            file_path: "test.graphql".to_string(),
        });

        let source = SourceDefinition::Operation(Arc::clone(&op_def));
        let root_entity = Arc::new(Entity::new_root(source));

        let all_types = Arc::new(ReferencedTypes::new(
            &[GraphQLNamedType::Object(Arc::clone(&query))],
            make_root_types(),
        ));

        let scope = ScopeDescriptor::descriptor(&query_type, None, &all_types);
        let type_info = Arc::new(TypeInfo::new(
            Arc::clone(&root_entity),
            LinkedList::new(scope),
        ));

        let cr_field = Arc::new(compilation_result::Field {
            name: "testQuery".to_string(),
            alias: None,
            type_: GraphQLType::Scalar(Arc::new(GraphQLScalarType {
                name: GraphQLName::new("String".to_string()),
                documentation: None,
                specified_by_url: None,
            })),
            arguments: None,
            inclusion_conditions: None,
            directives: None,
            selection_set: Some(CRSelectionSet {
                parent_type: query_type,
                selections: vec![],
            }),
            deprecation_reason: None,
            documentation: None,
        });

        let selection_set = Arc::new(SelectionSet::new(
            type_info,
            Some(Arc::new(DirectSelections::new())),
        ));

        let root_field = EntityField::new(cr_field, None, selection_set);
        let entity_storage = DefinitionEntityStorage::new(root_entity);

        Operation::new(op_def, root_field, IndexSet::new(), entity_storage, false)
    }

    #[test]
    fn operation_implements_definition_trait() {
        let op = make_test_operation();
        // Access through the Definition trait
        let def: &dyn Definition = &op;
        assert_eq!(def.name(), "TestQuery");
        assert!(!def.is_local_cache_mutation());
    }

    #[test]
    fn operation_name_delegates_to_definition() {
        let op = make_test_operation();
        assert_eq!(op.name(), "TestQuery");
    }
}
