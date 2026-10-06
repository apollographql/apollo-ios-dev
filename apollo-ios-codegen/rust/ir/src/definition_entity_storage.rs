use std::sync::Arc;

use graphql_compiler::compilation_result;
use indexmap::IndexMap;
use utilities::linked_list::LinkedList;

use crate::entity::{Entity, FieldComponent, Location, SourceDefinition};
use crate::selection_set::TypeInfo;

// MARK: - DefinitionEntityStorage

/// Storage for all entities within a single definition (operation or fragment).
///
/// Ensures that only one `Entity` instance exists per location (dedup by location).
/// Entity constructors are `pub(crate)` to enforce that only `DefinitionEntityStorage`
/// creates entities (per RESEARCH.md Pitfall 2 / T-04-07).
///
/// Mirrors `IR.DefinitionEntityStorage` from `IR+DefinitionEntityStorage.swift`.
#[derive(Debug, Clone)]
pub struct DefinitionEntityStorage {
    pub(crate) source_definition: SourceDefinition,
    pub entities_for_fields: IndexMap<Location, Arc<Entity>>,
}

impl DefinitionEntityStorage {
    /// Creates a new storage initialized with the root entity.
    pub(crate) fn new(root_entity: Arc<Entity>) -> Self {
        let source_definition = root_entity.location.source.clone();
        let mut entities_for_fields = IndexMap::new();
        entities_for_fields.insert(root_entity.location.clone(), Arc::clone(&root_entity));
        DefinitionEntityStorage {
            source_definition,
            entities_for_fields,
        }
    }

    /// Returns the entity for a field on the given enclosing entity.
    ///
    /// If an entity at the computed location already exists, returns the existing one.
    /// Otherwise, creates a new entity and stores it.
    ///
    /// Panics if the field has no selection set (non-entity type field).
    pub fn entity_for_field(
        &mut self,
        field: &compilation_result::Field,
        on_enclosing_entity: &Entity,
    ) -> Arc<Entity> {
        assert!(
            on_enclosing_entity.location.source == self.source_definition,
            "Enclosing entity from other source definition is invalid."
        );

        let location = on_enclosing_entity
            .location
            .appending(FieldComponent::new(
                field.response_key().to_string(),
                field.type_.clone(),
            ));

        if let Some(existing) = self.entities_for_fields.get(&location) {
            return Arc::clone(existing);
        }

        let field_type = field
            .selection_set
            .as_ref()
            .map(|ss| &ss.parent_type)
            .unwrap_or_else(|| {
                panic!(
                    "Entity cannot be created for non-entity type field {}.",
                    field.name
                )
            });

        let root_type_path = on_enclosing_entity
            .root_type_path()
            .appending(field_type.clone());

        self.create_entity(location, root_type_path)
    }

    /// Returns the entity corresponding to a fragment entity, mapped to the operation's
    /// entity location space.
    ///
    /// If an entity at the computed location already exists, returns the existing one.
    /// Otherwise, creates a new entity and stores it.
    pub fn entity_for_fragment_entity(
        &mut self,
        entity_in_fragment: &Entity,
        fragment_spread_type_info: &TypeInfo,
    ) -> Arc<Entity> {
        assert!(
            fragment_spread_type_info.entity.location.source == self.source_definition,
            "Enclosing entity from fragment spread in other source definition is invalid."
        );

        let mut location = fragment_spread_type_info.entity.location.clone();
        if let Some(ref path_in_fragment) = entity_in_fragment.location.field_path {
            location = location.appending_path(path_in_fragment.iter().cloned());
        }

        if let Some(existing) = self.entities_for_fields.get(&location) {
            return Arc::clone(existing);
        }

        // Build root type path: take the spread entity's path and append
        // the fragment entity's path (minus the first element which is the fragment root)
        let other_root_type_path_iter = entity_in_fragment
            .root_type_path()
            .iter()
            .skip(1)
            .cloned();
        let root_type_path = fragment_spread_type_info
            .entity
            .root_type_path()
            .appending_sequence(other_root_type_path_iter);

        self.create_entity(location, root_type_path)
    }

    /// Returns the entity for a field on the given enclosing entity (read-only lookup).
    ///
    /// If the entity exists, returns it. Otherwise returns the enclosing entity.
    /// Used by ComputedSelectionSet builder which needs lookup without mutation.
    pub fn entity_for_field_readonly(
        &self,
        field: &compilation_result::Field,
        on_enclosing_entity: &Entity,
    ) -> Arc<Entity> {
        let location = on_enclosing_entity
            .location
            .appending(FieldComponent::new(
                field.response_key().to_string(),
                field.type_.clone(),
            ));

        if let Some(existing) = self.entities_for_fields.get(&location) {
            return Arc::clone(existing);
        }

        // If not found, return the enclosing entity -- this matches the fallback behavior
        // during merged selection computation where entities may not yet be in storage.
        // The caller (ComputedSelectionSet builder) is creating shallow merged fields that
        // reference the correct entity from the existing storage.
        Arc::new(Entity::new(
            location,
            on_enclosing_entity.root_type_path().appending(
                field
                    .selection_set
                    .as_ref()
                    .map(|ss| ss.parent_type.clone())
                    .unwrap_or_else(|| on_enclosing_entity.root_type().clone()),
            ),
        ))
    }

    /// Creates a new entity at the given location and stores it.
    fn create_entity(
        &mut self,
        location: Location,
        root_type_path: LinkedList<graphql_compiler::GraphQLCompositeType>,
    ) -> Arc<Entity> {
        let entity = Arc::new(Entity::new(location.clone(), root_type_path));
        self.entities_for_fields
            .insert(location, Arc::clone(&entity));
        entity
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    use graphql_compiler::{
        GraphQLCompositeType, GraphQLName, GraphQLObjectType, GraphQLScalarType,
        GraphQLType,
    };
    use graphql_compiler::compilation_result::{self, OperationDefinition, OperationType, SelectionSet as CRSelectionSet};
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

    fn make_operation_def(name: &str, root_type: Arc<GraphQLObjectType>) -> Arc<OperationDefinition> {
        Arc::new(OperationDefinition {
            name: name.to_string(),
            operation_type: OperationType::Query,
            variables: vec![],
            root_type: GraphQLCompositeType::Object(root_type),
            selection_set: CRSelectionSet {
                parent_type: GraphQLCompositeType::Object(make_object("Query")),
                selections: vec![],
            },
            directives: None,
            referenced_fragments: vec![],
            source: String::new(),
            file_path: String::new(),
        })
    }

    fn make_cr_field(name: &str, has_selection_set: bool) -> compilation_result::Field {
        let selection_set = if has_selection_set {
            Some(CRSelectionSet {
                parent_type: GraphQLCompositeType::Object(make_object(name)),
                selections: vec![],
            })
        } else {
            None
        };
        compilation_result::Field {
            name: name.to_string(),
            alias: None,
            type_: GraphQLType::Scalar(Arc::new(GraphQLScalarType {
                name: GraphQLName::new("String".to_string()),
                documentation: None,
                specified_by_url: None,
            })),
            arguments: None,
            inclusion_conditions: None,
            directives: None,
            selection_set,
            deprecation_reason: None,
            documentation: None,
        }
    }

    #[test]
    fn new_storage_contains_root_entity() {
        let query = make_object("Query");
        let op_def = make_operation_def("TestOp", Arc::clone(&query));
        let source = SourceDefinition::Operation(op_def);
        let root_entity = Arc::new(Entity::new_root(source));

        let storage = DefinitionEntityStorage::new(Arc::clone(&root_entity));
        assert_eq!(storage.entities_for_fields.len(), 1);
        assert!(Arc::ptr_eq(
            storage.entities_for_fields.get(&root_entity.location).unwrap(),
            &root_entity,
        ));
    }

    #[test]
    fn entity_for_field_returns_same_arc_for_same_location() {
        let query = make_object("Query");
        let op_def = make_operation_def("TestOp", Arc::clone(&query));
        let source = SourceDefinition::Operation(op_def);
        let root_entity = Arc::new(Entity::new_root(source));

        let mut storage = DefinitionEntityStorage::new(Arc::clone(&root_entity));

        let field = make_cr_field("user", true);
        let entity1 = storage.entity_for_field(&field, &root_entity);
        let entity2 = storage.entity_for_field(&field, &root_entity);

        // Same location should return the same Arc (dedup)
        assert!(Arc::ptr_eq(&entity1, &entity2));
        // Storage should have exactly 2 entities: root + user
        assert_eq!(storage.entities_for_fields.len(), 2);
    }

    #[test]
    fn entity_for_field_creates_different_entities_for_different_fields() {
        let query = make_object("Query");
        let op_def = make_operation_def("TestOp", Arc::clone(&query));
        let source = SourceDefinition::Operation(op_def);
        let root_entity = Arc::new(Entity::new_root(source));

        let mut storage = DefinitionEntityStorage::new(Arc::clone(&root_entity));

        let field_user = make_cr_field("user", true);
        let field_post = make_cr_field("post", true);

        let entity_user = storage.entity_for_field(&field_user, &root_entity);
        let entity_post = storage.entity_for_field(&field_post, &root_entity);

        assert!(!Arc::ptr_eq(&entity_user, &entity_post));
        assert_eq!(storage.entities_for_fields.len(), 3);
    }

    #[test]
    #[should_panic(expected = "Entity cannot be created for non-entity type field")]
    fn entity_for_field_panics_for_non_entity_field() {
        let query = make_object("Query");
        let op_def = make_operation_def("TestOp", Arc::clone(&query));
        let source = SourceDefinition::Operation(op_def);
        let root_entity = Arc::new(Entity::new_root(source));

        let mut storage = DefinitionEntityStorage::new(Arc::clone(&root_entity));

        let scalar_field = make_cr_field("name", false);
        storage.entity_for_field(&scalar_field, &root_entity);
    }
}
