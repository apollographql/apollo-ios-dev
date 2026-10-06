use std::fmt;
use std::hash::{Hash, Hasher};
use std::ops::Deref;
use std::sync::Arc;

use graphql_compiler::{DeferCondition, GraphQLCompositeType};
use utilities::linked_list::LinkedList;

use crate::entity::Entity;
use crate::inclusion_conditions::InclusionConditions;
use crate::merged_selections::MergedSource;
use crate::scope_descriptor::{ScopeCondition, ScopeDescriptor};

// MARK: - TypeInfo

/// Contains the type-scope metadata for a `SelectionSet`.
///
/// Mirrors `SelectionSet.TypeInfo` from `IR+SelectionSet.swift`.
#[derive(Debug)]
pub struct TypeInfo {
    /// The entity that the `selections` are being selected on.
    ///
    /// Multiple `SelectionSet`s may reference the same `Entity`.
    pub entity: Arc<Entity>,

    /// A list of the scopes for the `SelectionSet` and its enclosing entities.
    ///
    /// The selection set's `scope` is the last element in the list.
    pub scope_path: LinkedList<ScopeDescriptor>,

    /// Indicates the sources from which this TypeInfo's selections were derived
    /// during merged selection computation.
    ///
    /// If empty, the selection set was created directly from user-defined `.graphql` source.
    pub derived_from_merged_sources: Vec<MergedSource>,
}

impl TypeInfo {
    pub fn new(entity: Arc<Entity>, scope_path: LinkedList<ScopeDescriptor>) -> Self {
        TypeInfo {
            entity,
            scope_path,
            derived_from_merged_sources: Vec::new(),
        }
    }

    /// Indicates if the `SelectionSet` was created directly due to a selection set in the
    /// user defined `.graphql` definition file.
    ///
    /// If `false`, the selection set was artificially created by the IR.
    pub fn is_user_defined(&self) -> bool {
        self.derived_from_merged_sources.is_empty()
    }

    /// Describes all of the types and inclusion conditions the selection set matches.
    /// Derived from all the selection set's parents.
    pub fn scope(&self) -> &ScopeDescriptor {
        self.scope_path.last()
    }

    /// The parent type of the selection set.
    pub fn parent_type(&self) -> &GraphQLCompositeType {
        &self.scope().type_
    }

    /// The inclusion conditions from the scope condition, if any.
    pub fn inclusion_conditions(&self) -> Option<&InclusionConditions> {
        self.scope().scope_path.last().conditions.as_ref()
    }

    /// The defer condition from the scope condition, if any.
    pub fn defer_condition(&self) -> Option<&DeferCondition> {
        self.scope().scope_path.last().defer_condition.as_ref()
    }

    /// Returns `true` if this selection set is deferred.
    pub fn is_deferred(&self) -> bool {
        self.defer_condition().is_some()
    }

    /// Indicates if the `SelectionSet` represents a root selection set.
    /// If `true`, the `SelectionSet` belongs to a field directly.
    /// If `false`, the `SelectionSet` belongs to a conditional selection set enclosed
    /// in a field's `SelectionSet`.
    pub fn is_entity_root(&self) -> bool {
        self.scope().scope_path.count() == 1
    }
}

impl PartialEq for TypeInfo {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.entity, &other.entity) && self.scope_path == other.scope_path
    }
}

impl Eq for TypeInfo {}

impl Hash for TypeInfo {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Arc::as_ptr(&self.entity).hash(state);
        self.scope_path.hash(state);
    }
}

impl fmt::Display for TypeInfo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.scope_path)
    }
}

// MARK: - SelectionSet

/// A set of selections within an operation or fragment, with type information.
///
/// Mirrors `IR.SelectionSet` from `IR+SelectionSet.swift`.
#[derive(Debug)]
pub struct SelectionSet {
    pub type_info: Arc<TypeInfo>,
    /// The selections that are directly selected by this selection set.
    ///
    /// To get the merged selections, use a `MergedSelections::Builder`.
    pub selections: Option<Arc<crate::direct_selections::DirectSelections>>,
}

impl SelectionSet {
    /// Returns a copy of this selection set with its scope path replaced and the
    /// scope paths of all nested selection sets rebuilt accordingly.
    ///
    /// Mirrors Swift `SelectionSet.updateScopePath(to:)`.
    pub fn updating_scope_path(&self, new_scope_path: LinkedList<ScopeDescriptor>) -> SelectionSet {
        let mut type_info =
            TypeInfo::new(Arc::clone(&self.type_info.entity), new_scope_path.clone());
        type_info.derived_from_merged_sources = self.type_info.derived_from_merged_sources.clone();
        let selections = self
            .selections
            .as_ref()
            .map(|sels| Arc::new(sels.updating_parent_scope_path(&new_scope_path)));
        SelectionSet {
            type_info: Arc::new(type_info),
            selections,
        }
    }

    pub fn new(
        type_info: Arc<TypeInfo>,
        selections: Option<Arc<crate::direct_selections::DirectSelections>>,
    ) -> Self {
        SelectionSet {
            type_info,
            selections,
        }
    }
}

impl PartialEq for SelectionSet {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.type_info, &other.type_info)
            && match (&self.selections, &other.selections) {
                (Some(a), Some(b)) => Arc::ptr_eq(a, b),
                (None, None) => true,
                _ => false,
            }
    }
}

impl Eq for SelectionSet {}

impl Hash for SelectionSet {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Arc::as_ptr(&self.type_info).hash(state);
        if let Some(ref selections) = self.selections {
            Arc::as_ptr(selections).hash(state);
        }
    }
}

impl fmt::Display for SelectionSet {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "SelectionSet on {}", self.type_info.parent_type())?;
        if let Some(conditions) = self.type_info.inclusion_conditions() {
            write!(f, " {}", conditions)?;
        }
        Ok(())
    }
}

/// Implements Deref to TypeInfo to match Swift's @dynamicMemberLookup.
impl Deref for SelectionSet {
    type Target = TypeInfo;

    fn deref(&self) -> &Self::Target {
        &self.type_info
    }
}

// MARK: - LinkedList<ScopeCondition> extension

/// Extension trait for LinkedList<ScopeCondition> to check for deferred fragments.
pub trait ScopeConditionListExt {
    fn contains_deferred_fragment(&self) -> bool;
}

impl ScopeConditionListExt for LinkedList<ScopeCondition> {
    fn contains_deferred_fragment(&self) -> bool {
        for scope_condition in self.iter() {
            if scope_condition.defer_condition.is_some() {
                return true;
            }
        }
        false
    }
}
