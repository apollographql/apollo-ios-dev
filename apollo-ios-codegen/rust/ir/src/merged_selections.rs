use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use crate::named_fragment::NamedFragment;
use crate::selection_set::TypeInfo;

// MARK: - MergedSource

/// The source of merged selections.
///
/// Mirrors `MergedSelections.MergedSource` from `IR+MergedSelections.swift`.
#[derive(Clone, Debug)]
pub struct MergedSource {
    /// The `TypeInfo` of the `SelectionSet` that is the source of the merged selections.
    pub type_info: Arc<TypeInfo>,

    /// The `NamedFragment` that the merged `SelectionSet` was contained in.
    ///
    /// - Note: If `fragment` is present, the `typeInfo` is relative to the fragment,
    /// instead of the operation directly.
    pub fragment: Option<Arc<NamedFragment>>,
}

impl PartialEq for MergedSource {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.type_info, &other.type_info)
            && match (&self.fragment, &other.fragment) {
                (Some(a), Some(b)) => Arc::ptr_eq(a, b),
                (None, None) => true,
                _ => false,
            }
    }
}

impl Eq for MergedSource {}

impl Hash for MergedSource {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Arc::as_ptr(&self.type_info).hash(state);
        self.fragment.as_ref().map(|f| Arc::as_ptr(f)).hash(state);
    }
}

impl fmt::Display for MergedSource {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.type_info)?;
        if let Some(ref fragment) = self.fragment {
            write!(f, ", fragment: {}", fragment.name())?;
        } else {
            write!(f, ", fragment: nil")?;
        }
        Ok(())
    }
}

// MARK: - MergingStrategy

bitflags::bitflags! {
    /// The `MergingStrategy` is used to determine what merged fields and named fragment
    /// accessors are merged into the `MergedSelections`.
    ///
    /// `MergedSelections` can compute which selections from a selection set's parents, sibling
    /// inline fragments, and named fragment spreads will also be included on the response object,
    /// given the selection set's `TypeInfo`.
    ///
    /// Mirrors `MergedSelections.MergingStrategy` from `IR+MergedSelections.swift`.
    #[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
    pub struct MergingStrategy: u32 {
        /// Merges fields and fragment accessors from the selection set's direct ancestors.
        const ANCESTORS       = 1 << 0;

        /// Merges fields and fragment accessors from sibling inline fragments that match
        /// the selection set's scope.
        const SIBLINGS        = 1 << 1;

        /// Merges fields and fragment accessors from named fragments that have been spread
        /// into the selection set.
        const NAMED_FRAGMENTS = 1 << 2;

        /// Merges all possible fields and fragment accessors from all sources.
        ///
        /// This includes all selections from other related `SelectionSet`s on the same entity
        /// that match the selection set's type scope.
        const ALL = Self::ANCESTORS.bits() | Self::SIBLINGS.bits() | Self::NAMED_FRAGMENTS.bits();
    }
}

impl fmt::Display for MergingStrategy {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if *self == MergingStrategy::ALL {
            return write!(f, ".all");
        }

        let mut values: Vec<&str> = Vec::new();
        if self.contains(MergingStrategy::ANCESTORS) {
            values.push(".ancestors");
        }
        if self.contains(MergingStrategy::SIBLINGS) {
            values.push(".siblings");
        }
        if self.contains(MergingStrategy::NAMED_FRAGMENTS) {
            values.push(".namedFragments");
        }
        write!(f, "[{}]", values.join(", "))
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_contains_all_three_flags() {
        assert!(MergingStrategy::ALL.contains(MergingStrategy::ANCESTORS));
        assert!(MergingStrategy::ALL.contains(MergingStrategy::SIBLINGS));
        assert!(MergingStrategy::ALL.contains(MergingStrategy::NAMED_FRAGMENTS));
    }

    #[test]
    fn individual_flags_are_distinct() {
        assert_ne!(MergingStrategy::ANCESTORS, MergingStrategy::SIBLINGS);
        assert_ne!(MergingStrategy::SIBLINGS, MergingStrategy::NAMED_FRAGMENTS);
        assert_ne!(MergingStrategy::ANCESTORS, MergingStrategy::NAMED_FRAGMENTS);
    }

    #[test]
    fn intersection_works_correctly() {
        let strategy = MergingStrategy::ANCESTORS | MergingStrategy::SIBLINGS;
        assert!(strategy.contains(MergingStrategy::ANCESTORS));
        assert!(strategy.contains(MergingStrategy::SIBLINGS));
        assert!(!strategy.contains(MergingStrategy::NAMED_FRAGMENTS));
    }

    #[test]
    fn display_all() {
        assert_eq!(MergingStrategy::ALL.to_string(), ".all");
    }

    #[test]
    fn display_single_flag() {
        assert_eq!(MergingStrategy::ANCESTORS.to_string(), "[.ancestors]");
    }

    #[test]
    fn display_two_flags() {
        let strategy = MergingStrategy::ANCESTORS | MergingStrategy::NAMED_FRAGMENTS;
        assert_eq!(strategy.to_string(), "[.ancestors, .namedFragments]");
    }

    #[test]
    fn empty_strategy() {
        let empty = MergingStrategy::empty();
        assert!(!empty.contains(MergingStrategy::ANCESTORS));
        assert!(!empty.contains(MergingStrategy::SIBLINGS));
        assert!(!empty.contains(MergingStrategy::NAMED_FRAGMENTS));
    }
}
