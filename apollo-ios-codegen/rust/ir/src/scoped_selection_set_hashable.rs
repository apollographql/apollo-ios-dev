use crate::fields::Field;
use crate::named_fragment_spread::NamedFragmentSpread;

// MARK: - ScopedSelectionSetHashable

/// A hash value that will be the same for any selections that should be merged in a given scope.
/// This is not the same as equivalence. Rather objects with an equal `hash_for_selection_set_scope`
/// are considered to be equivalent only if they exist within the same "scope".
///
/// A "scope" is a group of selection sets that all represent the same entity.
/// A scope can include selections from a selection set along with any selections from its
/// parent, siblings, fragments spreads, or other selection sets on the same entity that match
/// the selection set's parent type.
///
/// Mirrors `ScopedSelectionSetHashable` from `IR+ScopedSelectionSetHashable.swift`.
pub trait ScopedSelectionSetHashable {
    fn hash_for_selection_set_scope(&self) -> &str;
}

impl ScopedSelectionSetHashable for Field {
    fn hash_for_selection_set_scope(&self) -> &str {
        self.response_key()
    }
}

impl ScopedSelectionSetHashable for NamedFragmentSpread {
    fn hash_for_selection_set_scope(&self) -> &str {
        &self.fragment.definition.name
    }
}
