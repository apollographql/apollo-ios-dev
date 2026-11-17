use crate::definition_entity_storage::DefinitionEntityStorage;
use crate::fields::EntityField;

// MARK: - Definition

/// A top level GraphQL definition, which can be an operation or a named fragment.
///
/// Mirrors `IR.Definition` protocol from `IR+Definition.swift`.
pub trait Definition {
    fn name(&self) -> &str;
    fn root_field(&self) -> &EntityField;
    fn entity_storage(&self) -> &DefinitionEntityStorage;
    fn is_local_cache_mutation(&self) -> bool;
}
