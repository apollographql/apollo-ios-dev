use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use crate::inclusion_conditions::InclusionConditions;
use crate::selection_set::{SelectionSet, TypeInfo};

// MARK: - InlineFragmentSpread

/// Represents an Inline Fragment that has been "spread into" another SelectionSet using the
/// spread operator (`...`).
///
/// Mirrors `IR.InlineFragmentSpread` from `IR+InlineFragmentSpread.swift`.
#[derive(Clone, Debug)]
pub struct InlineFragmentSpread {
    /// The `SelectionSet` representing the inline fragment that has been "spread into" its
    /// enclosing operation/fragment.
    pub selection_set: Arc<SelectionSet>,
}

impl InlineFragmentSpread {
    pub fn new(selection_set: Arc<SelectionSet>) -> Self {
        InlineFragmentSpread { selection_set }
    }

    /// Indicates the location where the inline fragment has been "spread into" its enclosing
    /// operation/fragment.
    pub fn type_info(&self) -> &TypeInfo {
        &self.selection_set.type_info
    }

    /// The inclusion conditions from the selection set's scope.
    pub fn inclusion_conditions(&self) -> Option<&InclusionConditions> {
        self.selection_set.inclusion_conditions()
    }
}

impl PartialEq for InlineFragmentSpread {
    fn eq(&self, other: &Self) -> bool {
        self.selection_set == other.selection_set
    }
}

impl Eq for InlineFragmentSpread {}

impl Hash for InlineFragmentSpread {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.selection_set.hash(state);
    }
}

impl fmt::Display for InlineFragmentSpread {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.type_info().parent_type())?;
        if let Some(conditions) = self.type_info().inclusion_conditions() {
            write!(f, " {}", conditions)?;
        }
        if let Some(defer_condition) = self.type_info().defer_condition() {
            write!(f, " {:?}", defer_condition)?;
        }
        Ok(())
    }
}
