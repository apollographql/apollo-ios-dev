//! ComputedSelectionSet -- represents the computed selections for a `SelectionSet`.
//! This includes both the direct and merged selections.
//!
//! Mirrors `IR.ComputedSelectionSet` from `IR+ComputedSelectionSet.swift` (255 lines).

use std::fmt;
use std::sync::Arc;

use indexmap::IndexMap;

use graphql_compiler::GraphQLCompositeType;

use crate::direct_selections::DirectSelections;
use crate::entity_selection_tree::EntityTreeScopeSelections;
use crate::fields::{EntityField, Field};
use crate::inline_fragment_spread::InlineFragmentSpread;
use crate::merged_selections::{MergedSource, MergingStrategy};
use crate::named_fragment_spread::NamedFragmentSpread;
use crate::scope_descriptor::ScopeCondition;
use crate::scoped_selection_set_hashable::ScopedSelectionSetHashable;
use crate::selection_set::{SelectionSet, TypeInfo};
use crate::definition_entity_storage::DefinitionEntityStorage;

use indexmap::IndexSet;

// MARK: - ComputedSelectionSet

/// A data structure representing the computed selections for a `SelectionSet`.
/// This includes both the direct and merged selections.
///
/// Mirrors `ComputedSelectionSet` from `IR+ComputedSelectionSet.swift`.
pub struct ComputedSelectionSet {
    pub direct: Option<Arc<DirectSelections>>,
    pub merged: MergedSelections,
    pub type_info: Arc<TypeInfo>,
}

impl ComputedSelectionSet {
    /// Returns an iterator over all fields (direct first, then merged).
    /// Mirrors Swift's `makeFieldIterator()`.
    pub fn make_field_iterator(&self) -> impl Iterator<Item = &Field> {
        let direct_iter = self.direct.iter()
            .flat_map(|d| d.fields.values());
        let merged_iter = self.merged.fields.values();
        direct_iter.chain(merged_iter)
    }

    /// Returns an iterator over fields matching the given filter (direct first, then merged).
    /// Mirrors Swift's `makeFieldIterator(filter:)`.
    pub fn make_field_iterator_filtered<'a, F: Fn(&Field) -> bool + 'a>(
        &'a self,
        filter: F,
    ) -> impl Iterator<Item = &'a Field> {
        let direct_iter = self.direct.iter()
            .flat_map(|d| d.fields.values());
        let merged_iter = self.merged.fields.values();
        direct_iter.chain(merged_iter).filter(move |f| filter(f))
    }

    /// Returns an iterator over all inline fragments (direct first, then merged).
    /// Mirrors Swift's `makeInlineFragmentIterator()`.
    pub fn make_inline_fragment_iterator(&self) -> impl Iterator<Item = &InlineFragmentSpread> {
        let direct_iter = self.direct.iter()
            .flat_map(|d| d.inline_fragments.values());
        let merged_iter = self.merged.inline_fragments.values();
        direct_iter.chain(merged_iter)
    }

    /// Returns an iterator over all named fragments (direct first, then merged).
    /// Mirrors Swift's `makeNamedFragmentIterator()`.
    pub fn make_named_fragment_iterator(&self) -> impl Iterator<Item = &NamedFragmentSpread> {
        let direct_iter = self.direct.iter()
            .flat_map(|d| d.named_fragments.values());
        let merged_iter = self.merged.named_fragments.values();
        direct_iter.chain(merged_iter)
    }

    /// Returns true if this selection set selects an "id" field and the parent type
    /// is identifiable (has key_fields == ["id"]).
    /// Mirrors Swift's `ComputedSelectionSet.isIdentifiable`.
    pub fn is_identifiable(&self) -> bool {
        let has_id_field = self.direct.as_ref().map_or(false, |d| d.fields.contains_key("id"))
            || self.merged.fields.contains_key("id");
        if !has_id_field {
            return false;
        }
        is_composite_type_identifiable(self.type_info.parent_type())
    }
}

/// Returns true if the composite type has key_fields == ["id"].
/// Mirrors Swift's `GraphQLCompositeType.isIdentifiable`.
fn is_composite_type_identifiable(ty: &GraphQLCompositeType) -> bool {
    match ty {
        GraphQLCompositeType::Object(obj) => {
            obj.key_fields.as_ref().map_or(false, |kf| kf.len() == 1 && kf[0] == "id")
        }
        GraphQLCompositeType::Interface(iface) => {
            iface.key_fields.as_ref().map_or(false, |kf| kf.len() == 1 && kf[0] == "id")
        }
        GraphQLCompositeType::Union(_) => false,
    }
}

impl fmt::Debug for ComputedSelectionSet {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ComputedSelectionSet")
            .field("direct", &self.direct.is_some())
            .field("merged", &self.merged)
            .finish()
    }
}

// MARK: - MergedSelections

/// Represents the selections that are merged into a selection set from other selection sets.
///
/// Mirrors `MergedSelections` from `IR+MergedSelections.swift`.
#[derive(Debug)]
pub struct MergedSelections {
    pub merged_sources: IndexSet<MergedSource>,
    pub merging_strategy: MergingStrategy,
    pub fields: IndexMap<String, Field>,
    pub inline_fragments: IndexMap<ScopeCondition, InlineFragmentSpread>,
    pub named_fragments: IndexMap<String, NamedFragmentSpread>,
}

impl MergedSelections {
    pub fn is_empty(&self) -> bool {
        self.fields.is_empty()
            && self.inline_fragments.is_empty()
            && self.named_fragments.is_empty()
    }
}

// MARK: - ComputedSelectionSet Builder

/// Builder that computes merged selections by walking the EntitySelectionTree.
///
/// Mirrors `ComputedSelectionSet.Builder` from `IR+ComputedSelectionSet.swift`.
pub struct Builder {
    pub type_info: Arc<TypeInfo>,
    direct_selections: Option<Arc<DirectSelections>>,
    entity_storage: DefinitionEntityStorage,
    pub merging_strategy: MergingStrategy,

    pub merged_sources: IndexSet<MergedSource>,
    pub fields: IndexMap<String, Field>,
    pub inline_fragments: IndexMap<ScopeCondition, InlineFragmentSpread>,
    pub named_fragments: IndexMap<String, NamedFragmentSpread>,
}

impl Builder {
    pub fn new(
        direct_selections: Option<Arc<DirectSelections>>,
        type_info: Arc<TypeInfo>,
        merging_strategy: MergingStrategy,
        entity_storage: DefinitionEntityStorage,
    ) -> Self {
        assert!(
            type_info.entity.location.source == entity_storage.source_definition,
            "typeInfo and entityStorage must originate from the same definition."
        );
        Builder {
            type_info,
            direct_selections,
            entity_storage,
            merging_strategy,
            merged_sources: IndexSet::new(),
            fields: IndexMap::new(),
            inline_fragments: IndexMap::new(),
            named_fragments: IndexMap::new(),
        }
    }

    pub fn from_selection_set(
        selection_set: &SelectionSet,
        merging_strategy: MergingStrategy,
        entity_storage: DefinitionEntityStorage,
    ) -> Self {
        Self::new(
            selection_set.selections.clone(),
            Arc::clone(&selection_set.type_info),
            merging_strategy,
            entity_storage,
        )
    }

    // MARK: Build

    pub fn build(mut self) -> ComputedSelectionSet {
        // Walk the entity selection tree to collect merged selections.
        // We need to collect the merge operations first, then apply them,
        // because add_merged_selections borrows the entity immutably while
        // we need to mutate self.
        let type_info = Arc::clone(&self.type_info);

        // Collect all merge operations into vectors
        let mut merge_ops: Vec<(EntityTreeScopeSelections, MergedSource, MergingStrategy)> =
            Vec::new();
        let mut inline_ops: Vec<(
            ScopeCondition,
            IndexMap<MergedSource, EntityTreeScopeSelections>,
            MergingStrategy,
        )> = Vec::new();

        type_info.entity.selection_tree.read().expect("selection_tree lock poisoned").add_merged_selections(
            &type_info,
            &mut |scope_selections, source, source_merge_strategy| {
                merge_ops.push((
                    scope_selections.clone(),
                    source.clone(),
                    source_merge_strategy,
                ));
            },
            &mut |condition, condition_selections, merge_strategy| {
                inline_ops.push((
                    condition.clone(),
                    condition_selections.clone(),
                    merge_strategy,
                ));
            },
        );

        // Now apply all collected operations
        for (scope_selections, source, strategy) in &merge_ops {
            self.merge_in(scope_selections, source, strategy);
        }
        for (condition, condition_selections, strategy) in &inline_ops {
            self.add_merged_inline_fragment(condition, condition_selections, *strategy);
        }

        self.finalize()
    }

    fn merge_in(
        &mut self,
        selections_to_merge: &EntityTreeScopeSelections,
        source: &MergedSource,
        source_merge_strategy: &MergingStrategy,
    ) {
        if !self.should_merge_in_source(source, *source_merge_strategy) {
            return;
        }

        let mut did_merge_any = false;

        for field in selections_to_merge.fields.values() {
            if self.merge_in_field(field, source) {
                did_merge_any = true;
            }
        }

        for fragment in selections_to_merge.named_fragments.values() {
            if self.merge_in_fragment(fragment) {
                did_merge_any = true;
            }
        }

        if did_merge_any {
            self.merged_sources.insert(source.clone());
        }
    }

    fn should_merge_in_source(
        &self,
        source: &MergedSource,
        source_merge_strategy: MergingStrategy,
    ) -> bool {
        self.should_merge_in_sources(&[source.clone()], source_merge_strategy)
    }

    fn should_merge_in_sources(
        &self,
        sources: &[MergedSource],
        source_merge_strategy: MergingStrategy,
    ) -> bool {
        if self.merging_strategy.contains(source_merge_strategy) {
            return true;
        }

        for source in sources {
            if self.type_info.derived_from_merged_sources.iter().any(|derived| {
                derived.type_info.scope_path == source.type_info.scope_path
                    && derived.fragment == source.fragment
            }) {
                return true;
            }
        }
        false
    }

    fn merge_in_field(&mut self, field: &Field, merged_source: &MergedSource) -> bool {
        let key_in_scope = field.hash_for_selection_set_scope().to_string();
        if let Some(ref direct) = self.direct_selections {
            if direct.fields.contains_key(&key_in_scope) {
                return false;
            }
        }

        let field_to_merge = match field {
            Field::Entity(entity_field) => {
                let mut new_entity_field =
                    self.create_or_find_shallowly_merged_nested_entity_field(entity_field);
                let field_merged_source = MergedSource {
                    type_info: Arc::clone(&entity_field.selection_set.type_info),
                    fragment: merged_source.fragment.clone(),
                };
                // Mutate derived_from_merged_sources on the new entity field's type info
                // to track which sources contributed to this merged field.
                let mut new_type_info_data = TypeInfo::new(
                    Arc::clone(&new_entity_field.selection_set.type_info.entity),
                    new_entity_field.selection_set.type_info.scope_path.clone(),
                );
                new_type_info_data.derived_from_merged_sources =
                    new_entity_field.selection_set.type_info.derived_from_merged_sources.clone();
                // Deduplicate: only add the source if it's not already present
                // (same fragment + same scope path). The entity selection tree can
                // provide the same field from the same source multiple times.
                let already_present = new_type_info_data.derived_from_merged_sources.iter().any(|existing| {
                    existing.fragment == field_merged_source.fragment
                        && existing.type_info.scope_path == field_merged_source.type_info.scope_path
                });
                if !already_present {
                    new_type_info_data.derived_from_merged_sources.push(field_merged_source);
                }
                let new_type_info = Arc::new(new_type_info_data);
                new_entity_field.selection_set = Arc::new(SelectionSet::new(
                    new_type_info,
                    new_entity_field.selection_set.selections.clone(),
                ));
                Field::Entity(new_entity_field)
            }
            _ => field.clone(),
        };

        self.fields.insert(key_in_scope, field_to_merge);
        true
    }

    fn create_or_find_shallowly_merged_nested_entity_field(
        &self,
        field: &EntityField,
    ) -> EntityField {
        let field_key = field.underlying_field.response_key();
        if let Some(Field::Entity(existing)) = self.fields.get(field_key) {
            return existing.clone();
        }

        let entity = self
            .entity_storage
            .entity_for_field_readonly(&field.underlying_field, &self.type_info.entity);

        let type_info = Arc::new(TypeInfo::new(
            entity,
            self.type_info
                .scope_path
                .appending(field.selection_set.type_info.scope().clone()),
        ));

        let new_selection_set = Arc::new(SelectionSet::new(type_info, None));

        EntityField::new(
            Arc::clone(&field.underlying_field),
            field.inclusion_conditions.clone(),
            new_selection_set,
        )
    }

    fn merge_in_fragment(&mut self, fragment: &NamedFragmentSpread) -> bool {
        let key_in_scope = fragment.hash_for_selection_set_scope().to_string();
        if let Some(ref direct) = self.direct_selections {
            if direct.named_fragments.contains_key(&key_in_scope) {
                return false;
            }
        }

        self.named_fragments
            .insert(key_in_scope, fragment.clone());
        true
    }

    fn add_merged_inline_fragment(
        &mut self,
        condition: &ScopeCondition,
        merged_sources: &IndexMap<MergedSource, EntityTreeScopeSelections>,
        merge_strategy: MergingStrategy,
    ) {
        if !self.type_info.is_entity_root() {
            return;
        }

        let sources: Vec<MergedSource> = merged_sources.keys().cloned().collect();
        if !self.should_merge_in_sources(&sources, merge_strategy) {
            return;
        }

        if let Some(ref direct) = self.direct_selections {
            if direct.inline_fragments.contains_key(condition) {
                return;
            }
        }

        let inline_fragment = self.create_or_find_shallowly_merged_composite_inline_fragment(condition, &sources);
        self.inline_fragments
            .insert(condition.clone(), inline_fragment);
    }

    fn create_or_find_shallowly_merged_composite_inline_fragment(
        &self,
        condition: &ScopeCondition,
        merged_sources: &[MergedSource],
    ) -> InlineFragmentSpread {
        if let Some(existing) = self.inline_fragments.get(condition) {
            return existing.clone();
        }

        let mut type_info_data = TypeInfo::new(
            Arc::clone(&self.type_info.entity),
            self.type_info
                .scope_path
                .mutating_last(|scope| scope.appending(condition.clone())),
        );
        type_info_data.derived_from_merged_sources = merged_sources.to_vec();
        let type_info = Arc::new(type_info_data);

        let selection_set = Arc::new(SelectionSet::new(type_info, None));

        InlineFragmentSpread::new(selection_set)
    }

    fn finalize(self) -> ComputedSelectionSet {
        let merged = MergedSelections {
            merged_sources: self.merged_sources,
            merging_strategy: self.merging_strategy,
            fields: self.fields,
            inline_fragments: self.inline_fragments,
            named_fragments: self.named_fragments,
        };

        ComputedSelectionSet {
            direct: self.direct_selections,
            merged,
            type_info: self.type_info,
        }
    }
}

impl fmt::Display for ComputedSelectionSet {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Direct: {:?}, Merged fields: {}, fragments: {}",
            self.direct.is_some(),
            self.merged.fields.len(),
            self.merged.named_fragments.len()
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    use graphql_compiler::{
        compilation_result, GraphQLName, GraphQLNamedType, GraphQLObjectType,
        GraphQLInterfaceType, GraphQLScalarType, GraphQLType, GraphQLUnionType,
    };
    use indexmap::IndexMap;

    use crate::direct_selections::DirectSelections;
    use crate::entity::Entity;
    use crate::fields::{Field, ScalarField};
    use crate::schema::ReferencedTypes;
    use crate::scope_descriptor::ScopeDescriptor;
    use utilities::linked_list::LinkedList;

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

    fn make_scalar_field(name: &str) -> Field {
        Field::Scalar(ScalarField::new(make_compilation_field(name), None))
    }

    fn make_object(name: &str, key_fields: Option<Vec<String>>) -> Arc<GraphQLObjectType> {
        Arc::new(GraphQLObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: Vec::new(),
            key_fields,
        })
    }

    fn make_interface(name: &str, key_fields: Option<Vec<String>>) -> Arc<GraphQLInterfaceType> {
        Arc::new(GraphQLInterfaceType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: Vec::new(),
            key_fields,
            implementing_objects: Vec::new(),
        })
    }

    fn make_root_types() -> compilation_result::RootTypeDefinition {
        let query_obj = Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Query".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: Vec::new(),
            key_fields: None,
        });
        compilation_result::RootTypeDefinition {
            query_type: GraphQLNamedType::Object(query_obj),
            mutation_type: None,
            subscription_type: None,
        }
    }

    fn make_type_info_with_parent(parent_type: GraphQLCompositeType) -> Arc<TypeInfo> {
        // Build a referenced types set containing the parent type
        let named_types: Vec<GraphQLNamedType> = match &parent_type {
            GraphQLCompositeType::Object(obj) => vec![GraphQLNamedType::Object(Arc::clone(obj))],
            GraphQLCompositeType::Interface(iface) => vec![GraphQLNamedType::Interface(Arc::clone(iface))],
            GraphQLCompositeType::Union(u) => vec![GraphQLNamedType::Union(Arc::clone(u))],
        };
        let all_types = Arc::new(ReferencedTypes::new(&named_types, make_root_types()));

        let scope = ScopeDescriptor::descriptor(&parent_type, None, &all_types);
        let scope_path = LinkedList::new(scope);

        let op_def = Arc::new(compilation_result::OperationDefinition {
            name: "TestOp".to_string(),
            operation_type: compilation_result::OperationType::Query,
            variables: Vec::new(),
            root_type: parent_type.clone(),
            selection_set: compilation_result::SelectionSet {
                parent_type: parent_type.clone(),
                selections: Vec::new(),
            },
            directives: None,
            referenced_fragments: Vec::new(),
            source: "query TestOp { id }".to_string(),
            file_path: "test.graphql".to_string(),
        });

        let source = crate::entity::SourceDefinition::Operation(op_def);
        let entity = Arc::new(Entity::new_root(source));

        Arc::new(TypeInfo::new(entity, scope_path))
    }

    fn make_computed_selection_set(
        direct_fields: Vec<(&str, Field)>,
        merged_fields: Vec<(&str, Field)>,
        type_info: Arc<TypeInfo>,
    ) -> ComputedSelectionSet {
        let direct = if direct_fields.is_empty() {
            None
        } else {
            let mut ds = DirectSelections::new();
            for (k, f) in direct_fields {
                ds.fields.insert(k.to_string(), f);
            }
            Some(Arc::new(ds))
        };

        let mut merged = MergedSelections {
            merged_sources: IndexSet::new(),
            merging_strategy: MergingStrategy::empty(),
            fields: IndexMap::new(),
            inline_fragments: IndexMap::new(),
            named_fragments: IndexMap::new(),
        };
        for (k, f) in merged_fields {
            merged.fields.insert(k.to_string(), f);
        }

        ComputedSelectionSet {
            direct,
            merged,
            type_info,
        }
    }

    // -- make_field_iterator tests --

    #[test]
    fn make_field_iterator_direct_only() {
        let obj = make_object("Dog", None);
        let ti = make_type_info_with_parent(GraphQLCompositeType::Object(obj));
        let css = make_computed_selection_set(
            vec![("name", make_scalar_field("name")), ("age", make_scalar_field("age"))],
            vec![],
            ti,
        );
        let names: Vec<&str> = css.make_field_iterator().map(|f| f.name()).collect();
        assert_eq!(names, vec!["name", "age"]);
    }

    #[test]
    fn make_field_iterator_merged_only() {
        let obj = make_object("Dog", None);
        let ti = make_type_info_with_parent(GraphQLCompositeType::Object(obj));
        let css = make_computed_selection_set(
            vec![],
            vec![("species", make_scalar_field("species"))],
            ti,
        );
        let names: Vec<&str> = css.make_field_iterator().map(|f| f.name()).collect();
        assert_eq!(names, vec!["species"]);
    }

    #[test]
    fn make_field_iterator_direct_then_merged() {
        let obj = make_object("Dog", None);
        let ti = make_type_info_with_parent(GraphQLCompositeType::Object(obj));
        let css = make_computed_selection_set(
            vec![("name", make_scalar_field("name"))],
            vec![("species", make_scalar_field("species"))],
            ti,
        );
        let names: Vec<&str> = css.make_field_iterator().map(|f| f.name()).collect();
        assert_eq!(names, vec!["name", "species"]);
    }

    #[test]
    fn make_field_iterator_filtered_entity_fields_only() {
        let obj = make_object("Dog", None);
        let ti = make_type_info_with_parent(GraphQLCompositeType::Object(obj));
        let css = make_computed_selection_set(
            vec![("name", make_scalar_field("name")), ("age", make_scalar_field("age"))],
            vec![("species", make_scalar_field("species"))],
            ti,
        );
        // Filter for entity fields only -- none exist, so result should be empty
        let result: Vec<&Field> = css
            .make_field_iterator_filtered(|f| matches!(f, Field::Entity(_)))
            .collect();
        assert!(result.is_empty());

        // Filter for scalar fields -- should get all 3
        let result: Vec<&str> = css
            .make_field_iterator_filtered(|f| matches!(f, Field::Scalar(_)))
            .map(|f| f.name())
            .collect();
        assert_eq!(result, vec!["name", "age", "species"]);
    }

    // -- make_inline_fragment_iterator tests --

    #[test]
    fn make_inline_fragment_iterator_empty() {
        let obj = make_object("Dog", None);
        let ti = make_type_info_with_parent(GraphQLCompositeType::Object(obj));
        let css = make_computed_selection_set(vec![], vec![], ti);
        assert_eq!(css.make_inline_fragment_iterator().count(), 0);
    }

    // -- make_named_fragment_iterator tests --

    #[test]
    fn make_named_fragment_iterator_empty() {
        let obj = make_object("Dog", None);
        let ti = make_type_info_with_parent(GraphQLCompositeType::Object(obj));
        let css = make_computed_selection_set(vec![], vec![], ti);
        assert_eq!(css.make_named_fragment_iterator().count(), 0);
    }

    // -- is_identifiable tests --

    #[test]
    fn is_identifiable_true_with_id_field_and_identifiable_object() {
        let obj = make_object("Dog", Some(vec!["id".to_string()]));
        let ti = make_type_info_with_parent(GraphQLCompositeType::Object(obj));
        let css = make_computed_selection_set(
            vec![("id", make_scalar_field("id"))],
            vec![],
            ti,
        );
        assert!(css.is_identifiable());
    }

    #[test]
    fn is_identifiable_true_with_id_in_merged() {
        let obj = make_object("Dog", Some(vec!["id".to_string()]));
        let ti = make_type_info_with_parent(GraphQLCompositeType::Object(obj));
        let css = make_computed_selection_set(
            vec![],
            vec![("id", make_scalar_field("id"))],
            ti,
        );
        assert!(css.is_identifiable());
    }

    #[test]
    fn is_identifiable_false_no_id_field() {
        let obj = make_object("Dog", Some(vec!["id".to_string()]));
        let ti = make_type_info_with_parent(GraphQLCompositeType::Object(obj));
        let css = make_computed_selection_set(
            vec![("name", make_scalar_field("name"))],
            vec![],
            ti,
        );
        assert!(!css.is_identifiable());
    }

    #[test]
    fn is_identifiable_false_no_key_fields() {
        let obj = make_object("Dog", None);
        let ti = make_type_info_with_parent(GraphQLCompositeType::Object(obj));
        let css = make_computed_selection_set(
            vec![("id", make_scalar_field("id"))],
            vec![],
            ti,
        );
        assert!(!css.is_identifiable());
    }

    #[test]
    fn is_identifiable_false_wrong_key_fields() {
        let obj = make_object("Dog", Some(vec!["uuid".to_string()]));
        let ti = make_type_info_with_parent(GraphQLCompositeType::Object(obj));
        let css = make_computed_selection_set(
            vec![("id", make_scalar_field("id"))],
            vec![],
            ti,
        );
        assert!(!css.is_identifiable());
    }

    #[test]
    fn is_identifiable_interface_type() {
        let iface = make_interface("Animal", Some(vec!["id".to_string()]));
        let ti = make_type_info_with_parent(GraphQLCompositeType::Interface(iface));
        let css = make_computed_selection_set(
            vec![("id", make_scalar_field("id"))],
            vec![],
            ti,
        );
        assert!(css.is_identifiable());
    }

    #[test]
    fn is_identifiable_union_type_always_false() {
        let union_type = Arc::new(GraphQLUnionType {
            name: GraphQLName::new("SearchResult".to_string()),
            documentation: None,
            types: Vec::new(),
        });
        let ti = make_type_info_with_parent(GraphQLCompositeType::Union(union_type));
        let css = make_computed_selection_set(
            vec![("id", make_scalar_field("id"))],
            vec![],
            ti,
        );
        assert!(!css.is_identifiable());
    }

    // -- is_composite_type_identifiable tests --

    #[test]
    fn is_composite_type_identifiable_object_with_id() {
        let obj = make_object("Dog", Some(vec!["id".to_string()]));
        assert!(is_composite_type_identifiable(&GraphQLCompositeType::Object(obj)));
    }

    #[test]
    fn is_composite_type_identifiable_object_without_key_fields() {
        let obj = make_object("Dog", None);
        assert!(!is_composite_type_identifiable(&GraphQLCompositeType::Object(obj)));
    }

    #[test]
    fn is_composite_type_identifiable_interface_with_id() {
        let iface = make_interface("Animal", Some(vec!["id".to_string()]));
        assert!(is_composite_type_identifiable(&GraphQLCompositeType::Interface(iface)));
    }

    #[test]
    fn is_composite_type_identifiable_multiple_key_fields() {
        let obj = make_object("Dog", Some(vec!["id".to_string(), "name".to_string()]));
        assert!(!is_composite_type_identifiable(&GraphQLCompositeType::Object(obj)));
    }
}
