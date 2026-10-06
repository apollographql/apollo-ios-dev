use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use graphql_compiler::compilation_result;

use crate::inclusion_conditions::{AnyOf, InclusionConditions};
use crate::named_fragment::NamedFragment;
use crate::selection_set::TypeInfo;

// MARK: - NamedFragmentSpread

/// Represents a Named Fragment that has been "spread into" another SelectionSet using the
/// spread operator (`...`).
///
/// While a `NamedFragment` can be shared between operations, a `NamedFragmentSpread` represents a
/// `NamedFragment` included in a specific operation.
///
/// Mirrors `IR.NamedFragmentSpread` from `IR+NamedFragmentSpread.swift`.
#[derive(Clone, Debug)]
pub struct NamedFragmentSpread {
    /// The `NamedFragment` that this fragment refers to.
    ///
    /// This is a fragment that has already been built. To "spread" the fragment in, its entity
    /// selection trees are merged into the entity selection trees of the operation/fragment it is
    /// being spread into. This allows merged field calculations to include the fields merged in
    /// from the fragment.
    pub fragment: Arc<NamedFragment>,

    /// Indicates the location where the fragment has been "spread into" its enclosing
    /// operation/fragment. Its `scopePath` and `entity` reference are scoped to the operation it
    /// belongs to.
    pub type_info: Arc<TypeInfo>,

    /// The inclusion conditions for this fragment spread.
    pub inclusion_conditions: Option<AnyOf<InclusionConditions>>,
}

impl NamedFragmentSpread {
    pub fn new(
        fragment: Arc<NamedFragment>,
        type_info: Arc<TypeInfo>,
        inclusion_conditions: Option<AnyOf<InclusionConditions>>,
    ) -> Self {
        NamedFragmentSpread {
            fragment,
            type_info,
            inclusion_conditions,
        }
    }

    /// The fragment definition from the compilation result.
    pub fn definition(&self) -> &Arc<compilation_result::FragmentDefinition> {
        &self.fragment.definition
    }
}

impl PartialEq for NamedFragmentSpread {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.fragment, &other.fragment)
            && self.type_info == other.type_info
            && self.inclusion_conditions == other.inclusion_conditions
    }
}

impl Eq for NamedFragmentSpread {}

impl Hash for NamedFragmentSpread {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Arc::as_ptr(&self.fragment).hash(state);
        self.type_info.hash(state);
        self.inclusion_conditions.hash(state);
    }
}

impl fmt::Display for NamedFragmentSpread {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.fragment.name())?;
        if let Some(ref conditions) = self.inclusion_conditions {
            write!(f, " {}", conditions)?;
        }
        if let Some(defer_condition) = self.type_info.defer_condition() {
            write!(f, " {:?}", defer_condition)?;
        }
        Ok(())
    }
}
