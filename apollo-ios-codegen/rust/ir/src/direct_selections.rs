use std::fmt;
use std::sync::Arc;

use indexmap::IndexMap;

use crate::fields::{EntityField, Field};
use crate::inclusion_conditions::any_of_or;
use crate::inline_fragment_spread::InlineFragmentSpread;
use crate::named_fragment_spread::NamedFragmentSpread;
use crate::scope_descriptor::{ScopeCondition, ScopeDescriptor};
use crate::scoped_selection_set_hashable::ScopedSelectionSetHashable;
use crate::selection_set::{SelectionSet, TypeInfo};
use utilities::linked_list::LinkedList;

// MARK: - DirectSelections

/// The selections that are directly selected by a selection set.
///
/// Mirrors `IR.DirectSelections` from `IR+DirectSelections.swift`.
#[derive(Clone, Debug)]
pub struct DirectSelections {
    pub fields: IndexMap<String, Field>,
    pub inline_fragments: IndexMap<ScopeCondition, InlineFragmentSpread>,
    pub named_fragments: IndexMap<String, NamedFragmentSpread>,
}

impl DirectSelections {
    pub fn new() -> Self {
        DirectSelections {
            fields: IndexMap::new(),
            inline_fragments: IndexMap::new(),
            named_fragments: IndexMap::new(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.fields.is_empty()
            && self.inline_fragments.is_empty()
            && self.named_fragments.is_empty()
    }

    // MARK: - Merge methods

    /// Merges all selections from another `DirectSelections` into this one.
    pub fn merge_in_all(&mut self, other: &DirectSelections) {
        for field in other.fields.values() {
            self.merge_in_field(field.clone());
        }
        for fragment in other.inline_fragments.values() {
            self.merge_in_inline_fragment(fragment.clone());
        }
        for fragment in other.named_fragments.values() {
            self.merge_in_named_fragment(fragment.clone());
        }
    }

    /// Merges a field into the selections.
    ///
    /// If a field with the same response key already exists:
    /// - If both are EntityFields: merge their selection sets and handle inclusion condition wrapping
    /// - Otherwise: OR the inclusion conditions
    pub fn merge_in_field(&mut self, field: Field) {
        let key = field.hash_for_selection_set_scope().to_string();

        if let Some(existing_field) = self.fields.get_mut(&key) {
            match (existing_field, &field) {
                (Field::Entity(existing_ef), Field::Entity(new_ef)) => {
                    let merged = Self::merge_entity_fields(new_ef, existing_ef);
                    self.fields.insert(key, Field::Entity(merged));
                }
                (existing, _) => {
                    let merged_conditions = any_of_or(
                        existing.inclusion_conditions().cloned(),
                        field.inclusion_conditions().cloned(),
                    );
                    existing.set_inclusion_conditions(merged_conditions);
                }
            }
        } else {
            self.fields.insert(key, field);
        }
    }

    /// Merges two entity fields with the same response key.
    fn merge_entity_fields(new_field: &EntityField, existing_field: &EntityField) -> EntityField {
        if existing_field.inclusion_conditions == new_field.inclusion_conditions {
            // Same conditions: merge selections directly
            if let (Some(existing_sel), Some(new_sel)) = (
                &existing_field.selection_set.selections,
                &new_field.selection_set.selections,
            ) {
                // Clone the existing selections and merge in the new ones
                let mut merged = existing_sel.as_ref().clone();
                merged.merge_in_all(new_sel.as_ref());
                let mut result = existing_field.clone();
                result.selection_set = Arc::new(SelectionSet::new(
                    Arc::clone(&existing_field.selection_set.type_info),
                    Some(Arc::new(merged)),
                ));
                result
            } else {
                existing_field.clone()
            }
        } else if existing_field.inclusion_conditions.is_some() {
            // Existing has conditions: create inclusion wrapper
            Self::create_inclusion_wrapper_field(existing_field, new_field)
        } else {
            // Existing is unconditional wrapper: merge new field into it
            let mut result = existing_field.clone();
            Self::merge_field_into_inclusion_wrapper(new_field, &mut result);
            result
        }
    }

    /// Creates a new wrapper entity field that wraps both fields under inclusion conditions.
    fn create_inclusion_wrapper_field(
        existing_field: &EntityField,
        new_field: &EntityField,
    ) -> EntityField {
        let wrapper_scope = existing_field.selection_set.scope_path.mutating_last(|_| {
            ScopeDescriptor::descriptor(
                existing_field.selection_set.parent_type(),
                None,
                &existing_field.selection_set.scope().all_types_in_schema,
            )
        });

        let type_info = Arc::new(TypeInfo::new(
            Arc::clone(existing_field.entity()),
            wrapper_scope,
        ));

        let selection_set = Arc::new(SelectionSet::new(
            Arc::clone(&type_info),
            Some(Arc::new(DirectSelections::new())),
        ));

        let merged_conditions = any_of_or(
            existing_field.inclusion_conditions.clone(),
            new_field.inclusion_conditions.clone(),
        );

        let mut wrapper_field = EntityField::new(
            Arc::clone(&existing_field.underlying_field),
            merged_conditions,
            selection_set,
        );

        Self::merge_field_into_inclusion_wrapper(existing_field, &mut wrapper_field);
        Self::merge_field_into_inclusion_wrapper(new_field, &mut wrapper_field);

        wrapper_field
    }

    /// Merges a field into an inclusion wrapper field.
    fn merge_field_into_inclusion_wrapper(
        new_field: &EntityField,
        wrapper_field: &mut EntityField,
    ) {
        if let Some(new_field_conditions) = new_field.selection_set.inclusion_conditions() {
            let new_scope_path = wrapper_field
                .selection_set
                .scope_path
                .mutating_last(|scope| scope.appending_conditions(new_field_conditions.clone()));

            // Mirrors Swift `newField.selectionSet.updateScopePath(to:)`, which also
            // updates the scope paths of every nested selection set.
            let new_selection_set =
                Arc::new(new_field.selection_set.updating_scope_path(new_scope_path));

            let inline_fragment = InlineFragmentSpread::new(new_selection_set);

            if let Some(ref selections) = wrapper_field.selection_set.selections {
                let mut merged = selections.as_ref().clone();
                merged.merge_in_inline_fragment(inline_fragment);
                wrapper_field.selection_set = Arc::new(SelectionSet::new(
                    Arc::clone(&wrapper_field.selection_set.type_info),
                    Some(Arc::new(merged)),
                ));
            }
        } else if let Some(ref new_selections) = new_field.selection_set.selections {
            if let Some(ref wrapper_selections) = wrapper_field.selection_set.selections {
                let mut merged = wrapper_selections.as_ref().clone();
                merged.merge_in_all(new_selections.as_ref());
                wrapper_field.selection_set = Arc::new(SelectionSet::new(
                    Arc::clone(&wrapper_field.selection_set.type_info),
                    Some(Arc::new(merged)),
                ));
            }
        }
    }

    /// Returns a copy of these selections with every nested selection set's
    /// scope path rebuilt under `new_parent_scope_path`.
    ///
    /// Mirrors Swift `DirectSelections.updateParentScopePath(to:)`.
    pub fn updating_parent_scope_path(
        &self,
        new_parent_scope_path: &LinkedList<ScopeDescriptor>,
    ) -> DirectSelections {
        let mut result = self.clone();

        for field in result.fields.values_mut() {
            if let Field::Entity(ef) = field {
                let child_path = new_parent_scope_path.appending(ef.selection_set.scope().clone());
                ef.selection_set = Arc::new(ef.selection_set.updating_scope_path(child_path));
            }
        }

        for inline_fragment in result.inline_fragments.values_mut() {
            let last_condition = inline_fragment
                .selection_set
                .scope()
                .scope_path
                .last()
                .clone();
            let child_path = new_parent_scope_path
                .mutating_last(|scope| scope.appending(last_condition.clone()));
            inline_fragment.selection_set = Arc::new(
                inline_fragment
                    .selection_set
                    .updating_scope_path(child_path),
            );
        }

        for named_fragment in result.named_fragments.values_mut() {
            let mut type_info = TypeInfo::new(
                Arc::clone(&named_fragment.type_info.entity),
                new_parent_scope_path.clone(),
            );
            type_info.derived_from_merged_sources =
                named_fragment.type_info.derived_from_merged_sources.clone();
            named_fragment.type_info = Arc::new(type_info);
        }

        result
    }

    /// Merges an inline fragment spread into the selections.
    pub fn merge_in_inline_fragment(&mut self, fragment: InlineFragmentSpread) {
        let scope_condition = fragment.selection_set.scope().scope_path.last().clone();

        if let Some(existing) = self.inline_fragments.get(&scope_condition) {
            if let (Some(existing_sel), Some(new_sel)) = (
                &existing.selection_set.selections,
                &fragment.selection_set.selections,
            ) {
                let mut merged = existing_sel.as_ref().clone();
                merged.merge_in_all(new_sel.as_ref());
                let updated = InlineFragmentSpread::new(Arc::new(SelectionSet::new(
                    Arc::clone(&existing.selection_set.type_info),
                    Some(Arc::new(merged)),
                )));
                self.inline_fragments.insert(scope_condition, updated);
            }
        } else {
            self.inline_fragments.insert(scope_condition, fragment);
        }
    }

    /// Merges a named fragment spread into the selections.
    pub fn merge_in_named_fragment(&mut self, fragment: NamedFragmentSpread) {
        let key = fragment.hash_for_selection_set_scope().to_string();

        if let Some(existing) = self.named_fragments.get_mut(&key) {
            existing.inclusion_conditions = any_of_or(
                existing.inclusion_conditions.clone(),
                fragment.inclusion_conditions.clone(),
            );
        } else {
            self.named_fragments.insert(key, fragment);
        }
    }

    /// Merges multiple fields.
    pub fn merge_in_fields(&mut self, fields: impl IntoIterator<Item = Field>) {
        for field in fields {
            self.merge_in_field(field);
        }
    }

    /// Merges multiple inline fragment spreads.
    pub fn merge_in_inline_fragments(
        &mut self,
        fragments: impl IntoIterator<Item = InlineFragmentSpread>,
    ) {
        for fragment in fragments {
            self.merge_in_inline_fragment(fragment);
        }
    }

    /// Merges multiple named fragment spreads.
    pub fn merge_in_named_fragments(
        &mut self,
        fragments: impl IntoIterator<Item = NamedFragmentSpread>,
    ) {
        for fragment in fragments {
            self.merge_in_named_fragment(fragment);
        }
    }

    // MARK: - Scope path updates

    /// Updates the parent scope path for all nested selections.
    #[deprecated(
        note = "Scope path updates handled during IR construction. Will be removed in future cleanup."
    )]
    #[allow(dead_code)]
    pub fn update_parent_scope_path(
        &self,
        new_parent_scope_path: &utilities::linked_list::LinkedList<ScopeDescriptor>,
    ) {
        // Note: This method requires interior mutability or reconstruction patterns.
        // In the IR builder (Plan 04), scope path updates will be handled during construction.
        // For now, this is a placeholder that documents the pattern from Swift.
        let _ = new_parent_scope_path;
    }

    // MARK: - Read-only view

    /// Returns a read-only view of the selections.
    /// In Rust, `&DirectSelections` already provides read-only access via the borrow system.
    pub fn read_only_view(&self) -> &DirectSelections {
        self
    }
}

impl Default for DirectSelections {
    fn default() -> Self {
        Self::new()
    }
}

impl PartialEq for DirectSelections {
    fn eq(&self, other: &Self) -> bool {
        self.fields == other.fields
            && self.inline_fragments == other.inline_fragments
            && self.named_fragments == other.named_fragments
    }
}

impl Eq for DirectSelections {}

impl fmt::Display for DirectSelections {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Fields: {:?}\nInlineFragments: {:?}\nFragments: {:?}",
            self.fields.keys().collect::<Vec<_>>(),
            self.inline_fragments.keys().collect::<Vec<_>>(),
            self.named_fragments.keys().collect::<Vec<_>>()
        )
    }
}

// MARK: - GroupedByInclusionCondition

/// Groups selections by their inclusion conditions.
///
/// Mirrors `DirectSelections.GroupedByInclusionCondition` from `IR+DirectSelections.swift`.
pub struct GroupedByInclusionCondition {
    pub unconditional_selections: DirectSelections,
    pub inclusion_condition_groups: IndexMap<
        crate::inclusion_conditions::AnyOf<crate::inclusion_conditions::InclusionConditions>,
        DirectSelections,
    >,
}

impl GroupedByInclusionCondition {
    pub fn from_selections(selections: &DirectSelections) -> Self {
        let mut unconditional = DirectSelections::new();
        let mut groups: IndexMap<
            crate::inclusion_conditions::AnyOf<crate::inclusion_conditions::InclusionConditions>,
            DirectSelections,
        > = IndexMap::new();

        for (key, field) in &selections.fields {
            if let Some(conditions) = field.inclusion_conditions() {
                groups
                    .entry(conditions.clone())
                    .or_default()
                    .fields
                    .insert(key.clone(), field.clone());
            } else {
                unconditional.fields.insert(key.clone(), field.clone());
            }
        }

        for (key, fragment) in &selections.inline_fragments {
            if let Some(conditions) = fragment.inclusion_conditions() {
                let any_of = crate::inclusion_conditions::AnyOf::new(conditions.clone());
                groups
                    .entry(any_of)
                    .or_default()
                    .inline_fragments
                    .insert(key.clone(), fragment.clone());
            } else {
                unconditional
                    .inline_fragments
                    .insert(key.clone(), fragment.clone());
            }
        }

        for (key, fragment) in &selections.named_fragments {
            if let Some(conditions) = &fragment.inclusion_conditions {
                groups
                    .entry(conditions.clone())
                    .or_default()
                    .named_fragments
                    .insert(key.clone(), fragment.clone());
            } else {
                unconditional
                    .named_fragments
                    .insert(key.clone(), fragment.clone());
            }
        }

        GroupedByInclusionCondition {
            unconditional_selections: unconditional,
            inclusion_condition_groups: groups,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.unconditional_selections.is_empty() && self.inclusion_condition_groups.is_empty()
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fields::{Field, ScalarField};
    use crate::inclusion_conditions::{AnyOf, InclusionCondition, InclusionConditions};
    use graphql_compiler::{compilation_result, GraphQLName, GraphQLScalarType, GraphQLType};

    fn make_scalar_type() -> GraphQLType {
        GraphQLType::Scalar(Arc::new(GraphQLScalarType {
            name: GraphQLName::new("String".to_string()),
            documentation: None,
            specified_by_url: None,
        }))
    }

    fn make_compilation_field(name: &str) -> Arc<compilation_result::Field> {
        Arc::new(compilation_result::Field {
            name: name.to_string(),
            alias: None,
            type_: make_scalar_type(),
            arguments: None,
            inclusion_conditions: None,
            directives: None,
            selection_set: None,
            deprecation_reason: None,
            documentation: None,
        })
    }

    fn make_scalar_field(name: &str, conditions: Option<AnyOf<InclusionConditions>>) -> Field {
        Field::Scalar(ScalarField::new(make_compilation_field(name), conditions))
    }

    #[test]
    fn merge_in_field_inserts_new_field() {
        let mut selections = DirectSelections::new();
        let field = make_scalar_field("name", None);
        selections.merge_in_field(field);
        assert_eq!(selections.fields.len(), 1);
        assert!(selections.fields.contains_key("name"));
    }

    #[test]
    fn merge_two_fields_same_key_ors_inclusion_conditions() {
        let mut selections = DirectSelections::new();

        let cond_a = AnyOf::new(InclusionConditions::new(InclusionCondition::include_if(
            "flagA".to_string(),
        )));
        let cond_b = AnyOf::new(InclusionConditions::new(InclusionCondition::include_if(
            "flagB".to_string(),
        )));

        let field_a = make_scalar_field("name", Some(cond_a));
        let field_b = make_scalar_field("name", Some(cond_b));

        selections.merge_in_field(field_a);
        selections.merge_in_field(field_b);

        assert_eq!(selections.fields.len(), 1);
        let merged_field = selections.fields.get("name").unwrap();
        let merged_conditions = merged_field.inclusion_conditions().unwrap();
        // OR of two AnyOf sets should have 2 elements
        assert_eq!(merged_conditions.elements.len(), 2);
    }

    #[test]
    fn merge_unconditional_field_makes_result_unconditional() {
        let mut selections = DirectSelections::new();

        let cond = AnyOf::new(InclusionConditions::new(InclusionCondition::include_if(
            "flag".to_string(),
        )));

        let field_conditional = make_scalar_field("name", Some(cond));
        let field_unconditional = make_scalar_field("name", None);

        selections.merge_in_field(field_conditional);
        selections.merge_in_field(field_unconditional);

        assert_eq!(selections.fields.len(), 1);
        let merged_field = selections.fields.get("name").unwrap();
        // None || Some = None (unconditional), per any_of_or semantics
        assert!(merged_field.inclusion_conditions().is_none());
    }

    #[test]
    fn merge_in_all_merges_fields_and_fragments() {
        let mut sel_a = DirectSelections::new();
        sel_a.merge_in_field(make_scalar_field("name", None));
        sel_a.merge_in_field(make_scalar_field("age", None));

        let mut sel_b = DirectSelections::new();
        sel_b.merge_in_field(make_scalar_field("email", None));

        sel_a.merge_in_all(&sel_b);
        assert_eq!(sel_a.fields.len(), 3);
    }

    #[test]
    fn is_empty_returns_true_for_new_selections() {
        let selections = DirectSelections::new();
        assert!(selections.is_empty());
    }

    #[test]
    fn is_empty_returns_false_after_adding_field() {
        let mut selections = DirectSelections::new();
        selections.merge_in_field(make_scalar_field("name", None));
        assert!(!selections.is_empty());
    }
}
