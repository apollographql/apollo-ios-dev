use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use graphql_compiler::{compilation_result, GraphQLCompositeType};
use indexmap::IndexSet;

use crate::definition::Definition;
use crate::definition_entity_storage::DefinitionEntityStorage;
use crate::fields::EntityField;

// MARK: - NamedFragment

/// A built named fragment in the IR.
///
/// Mirrors `IR.NamedFragment` from `IR+NamedFragment.swift`.
#[derive(Debug)]
pub struct NamedFragment {
    pub definition: Arc<compilation_result::FragmentDefinition>,
    pub root_field: EntityField,

    /// All of the fragments that are referenced by this fragment's selection set.
    pub referenced_fragments: IndexSet<Arc<NamedFragment>>,

    /// All of the Entities that exist in the fragment's selection set,
    /// keyed by their relative location (ie. path) within the fragment.
    ///
    /// - Note: The FieldPath for an entity within a fragment will begin with a path component
    /// with the fragment's name and type.
    pub entity_storage: DefinitionEntityStorage,

    /// `True` if any selection set, or nested selection set, within the fragment contains any
    /// fragment marked with the `@defer` directive.
    pub contains_deferred_fragment: bool,
}

impl NamedFragment {
    /// Indicates if a field named `id` is selected directly on the fragment and
    /// the fragment's parent type is identifiable (single key field `id`).
    ///
    /// Mirrors Swift `IR.NamedFragment.isIdentifiable` (1.18.0).
    pub fn is_identifiable(&self) -> bool {
        use graphql_compiler::compilation_result::Selection;
        let selects_id = self.definition.selection_set.selections.iter().any(|sel| {
            matches!(sel, Selection::Field(f) if f.name == "id")
        });
        if !selects_id {
            return false;
        }
        match &self.definition.type_ {
            graphql_compiler::GraphQLCompositeType::Object(o) => {
                o.key_fields.as_deref() == Some(&["id".to_string()][..])
            }
            graphql_compiler::GraphQLCompositeType::Interface(i) => {
                i.key_fields.as_deref() == Some(&["id".to_string()][..])
            }
            graphql_compiler::GraphQLCompositeType::Union(_) => false,
        }
    }

    pub fn new(
        definition: Arc<compilation_result::FragmentDefinition>,
        root_field: EntityField,
        referenced_fragments: IndexSet<Arc<NamedFragment>>,
        entity_storage: DefinitionEntityStorage,
        contains_deferred_fragment: bool,
    ) -> Self {
        NamedFragment {
            definition,
            root_field,
            referenced_fragments,
            entity_storage,
            contains_deferred_fragment,
        }
    }

    pub fn name(&self) -> &str {
        &self.definition.name
    }

    pub fn type_(&self) -> &GraphQLCompositeType {
        &self.definition.type_
    }
}

impl Definition for NamedFragment {
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

impl PartialEq for NamedFragment {
    fn eq(&self, other: &Self) -> bool {
        self.definition == other.definition
    }
}

impl Eq for NamedFragment {}

impl Hash for NamedFragment {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.definition.hash(state);
    }
}

impl fmt::Display for NamedFragment {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.definition)
    }
}
