//! RootFieldBuilder -- constructs entity fields and selection sets from CompilationResult.
//!
//! Mirrors `IR.RootFieldBuilder` from `IR+RootFieldBuilder.swift` (457 lines).
//! All Swift `async` functions are synchronous in Rust per D-32.

use std::sync::Arc;

use graphql_compiler::{compilation_result, GraphQLCompositeType, GraphQLType};
use indexmap::IndexSet;
use utilities::linked_list::LinkedList;

use crate::definition_entity_storage::DefinitionEntityStorage;
use crate::direct_selections::DirectSelections;
use crate::entity::{Entity, SourceDefinition};
use crate::fields::{EntityField, Field, ScalarField};
use crate::inclusion_conditions::{AnyOf, InclusionConditions, InclusionResult};
use crate::inline_fragment_spread::InlineFragmentSpread;
use crate::named_fragment::NamedFragment;
use crate::named_fragment_spread::NamedFragmentSpread;
use crate::schema::Schema;
use crate::scope_descriptor::{ScopeCondition, ScopeDescriptor};
use crate::selection_set::{SelectionSet, TypeInfo};

// MARK: - Result

/// The result of building a root entity field.
pub(crate) struct BuildResult {
    pub root_field: EntityField,
    pub referenced_fragments: IndexSet<Arc<NamedFragment>>,
    pub entity_storage: DefinitionEntityStorage,
    pub contains_deferred_fragment: bool,
}

// MARK: - RootFieldBuilder

/// Builds the IR entity field graph from a CompilationResult field.
///
/// Mirrors `IR.RootFieldBuilder` from `IR+RootFieldBuilder.swift`.
/// All async functions from Swift are synchronous per D-32.
pub(crate) struct RootFieldBuilder<'a> {
    ir: &'a crate::builder::IRBuilder,
    root_entity: Arc<Entity>,
    entity_storage: DefinitionEntityStorage,
    referenced_fragments: IndexSet<Arc<NamedFragment>>,
    contains_deferred_fragment: bool,
}

impl<'a> RootFieldBuilder<'a> {
    /// Static entry point. Builds a root entity field from a CompilationResult field.
    pub(crate) fn build_root_entity_field(
        root_field: &compilation_result::Field,
        root_entity: Arc<Entity>,
        ir: &'a crate::builder::IRBuilder,
    ) -> BuildResult {
        let mut builder = RootFieldBuilder {
            ir,
            root_entity: Arc::clone(&root_entity),
            entity_storage: DefinitionEntityStorage::new(Arc::clone(&root_entity)),
            referenced_fragments: IndexSet::new(),
            contains_deferred_fragment: false,
        };

        builder.build(root_field)
    }

    fn schema(&self) -> &Schema {
        &self.ir.schema
    }

    fn build(
        &mut self,
        root_field: &compilation_result::Field,
    ) -> BuildResult {
        let root_selection_set = root_field
            .selection_set
            .as_ref()
            .expect("Root field must have a selection set.");

        let root_type_path = ScopeDescriptor::descriptor(
            &self.root_entity.root_type().clone(),
            None,
            &self.schema().referenced_types,
        );

        let root_ir_selection_set = self.build_selection_set(
            root_selection_set,
            &self.root_entity.clone(),
            LinkedList::new(root_type_path),
        );

        self.referenced_fragments.sort_by(|a, b| a.name().cmp(b.name()));

        BuildResult {
            root_field: EntityField::new(
                Arc::new(root_field.clone()),
                None,
                Arc::new(root_ir_selection_set),
            ),
            referenced_fragments: std::mem::take(&mut self.referenced_fragments),
            entity_storage: std::mem::replace(
                &mut self.entity_storage,
                DefinitionEntityStorage::new(Arc::clone(&self.root_entity)),
            ),
            contains_deferred_fragment: self.contains_deferred_fragment,
        }
    }

    fn build_selection_set(
        &mut self,
        compiled_selection_set: &compilation_result::SelectionSet,
        entity: &Arc<Entity>,
        scope_path: LinkedList<ScopeDescriptor>,
    ) -> SelectionSet {
        let type_info = Arc::new(TypeInfo::new(
            Arc::clone(entity),
            scope_path,
        ));

        let mut direct_selections = DirectSelections::new();

        self.build_direct_selections(
            &mut direct_selections,
            &type_info,
            compiled_selection_set,
        );

        SelectionSet::new(
            type_info,
            Some(Arc::new(direct_selections)),
        )
    }

    fn build_direct_selections(
        &mut self,
        target: &mut DirectSelections,
        type_info: &Arc<TypeInfo>,
        selection_set: &compilation_result::SelectionSet,
    ) {
        self.add_selections(selection_set, target, type_info);

        if type_info.defer_condition().is_none() {
            // Merge direct selections into the entity's selection tree (per D-30).
            // The entity's selection_tree is behind RwLock, allowing mutation through Arc.
            type_info
                .entity
                .selection_tree
                .write()
                .expect("selection_tree lock poisoned")
                .merge_in_selections(target, type_info);
        }
    }

    fn add_selections(
        &mut self,
        selection_set: &compilation_result::SelectionSet,
        target: &mut DirectSelections,
        type_info: &Arc<TypeInfo>,
    ) {
        for selection in &selection_set.selections {
            self.add_selection(selection, target, type_info);
        }

        self.ir.field_collector.collect_fields(selection_set);
    }

    fn add_selection(
        &mut self,
        selection: &compilation_result::Selection,
        target: &mut DirectSelections,
        type_info: &Arc<TypeInfo>,
    ) {
        match selection {
            compilation_result::Selection::Field(field) => {
                if let Some(ir_field) = self.build_field(field, type_info) {
                    target.merge_in_field(ir_field);
                }
            }
            compilation_result::Selection::InlineFragment(inline_fragment) => {
                self.add_inline_fragment(inline_fragment, selection, target, type_info);
            }
            compilation_result::Selection::FragmentSpread(fragment_spread) => {
                self.add_fragment_spread(fragment_spread, selection, target, type_info);
            }
        }
    }

    fn add_inline_fragment(
        &mut self,
        inline_fragment: &compilation_result::InlineFragment,
        selection: &compilation_result::Selection,
        target: &mut DirectSelections,
        type_info: &Arc<TypeInfo>,
    ) {
        let is_deferred = inline_fragment.defer_condition.is_some();

        let Some(scope) = self.scope_condition_for_inline_fragment(inline_fragment, type_info, is_deferred) else {
            return;
        };

        let inline_selection_set = &inline_fragment.selection_set;
        let matches_scope = type_info.scope().matches_scope_condition(&scope);

        match (matches_scope, &inline_fragment.defer_condition) {
            (true, Some(_)) | (false, None) => {
                let defer_condition = inline_fragment.defer_condition.clone();

                let ir_type_case = self.build_inline_fragment_spread_from_selection_set(
                    inline_selection_set,
                    &scope,
                    type_info,
                    defer_condition,
                );
                target.merge_in_inline_fragment(ir_type_case);
            }
            (true, None) => {
                self.add_selections(inline_selection_set, target, type_info);
            }
            (false, Some(_)) => {
                let ir_type_case = self.build_inline_fragment_spread_wrapping_selection(
                    selection,
                    &scope,
                    type_info,
                );
                target.merge_in_inline_fragment(ir_type_case);
            }
        }
    }

    fn add_fragment_spread(
        &mut self,
        fragment_spread: &compilation_result::FragmentSpread,
        selection: &compilation_result::Selection,
        target: &mut DirectSelections,
        type_info: &Arc<TypeInfo>,
    ) {
        let is_deferred = fragment_spread.defer_condition.is_some();

        let Some(scope) = self.scope_condition_for_fragment_spread(fragment_spread, type_info, is_deferred) else {
            return;
        };

        let selection_set_scope = type_info.scope();
        let matches_scope = selection_set_scope.matches_scope_condition(&scope);

        match (matches_scope, &fragment_spread.defer_condition) {
            (true, Some(_)) | (true, None) => {
                let defer_condition = fragment_spread.defer_condition.clone();

                let ir_fragment_spread = self.build_named_fragment_spread(
                    fragment_spread,
                    &scope,
                    type_info,
                    defer_condition,
                );
                target.merge_in_named_fragment(ir_fragment_spread);
            }
            (false, Some(_)) => {
                let ir_type_case = self.build_inline_fragment_spread_wrapping_selection(
                    selection,
                    &scope,
                    type_info,
                );
                target.merge_in_inline_fragment(ir_type_case);
            }
            (false, None) => {
                let inline_ss = compilation_result::SelectionSet {
                    parent_type: fragment_spread.parent_type().clone(),
                    selections: vec![selection.clone()],
                };

                let ir_type_case = self.build_inline_fragment_spread_from_selection_set(
                    &inline_ss,
                    &scope,
                    type_info,
                    None,
                );

                // Extract selections for entity tree merge before moving ir_type_case
                let inline_selections = ir_type_case.selection_set.selections.clone();

                target.merge_in_inline_fragment(ir_type_case);

                // Check if the type matches (not the conditions)
                let matches_type = match &scope.type_ {
                    Some(type_condition) => selection_set_scope.matches(type_condition),
                    None => true,
                };

                if matches_type {
                    // Merge the inline fragment's direct selections into the entity selection tree.
                    if let Some(ref direct_selections) = inline_selections {
                        type_info
                            .entity
                            .selection_tree
                            .write()
                            .expect("selection_tree lock poisoned")
                            .merge_in_selections(direct_selections, type_info);
                    }
                }
            }
        }
    }

    // MARK: - Scope Condition Computation

    fn scope_condition_for_inline_fragment(
        &self,
        inline_fragment: &compilation_result::InlineFragment,
        parent_type_info: &Arc<TypeInfo>,
        _is_deferred: bool,
    ) -> Option<ScopeCondition> {
        let inclusion_result = self.inclusion_result(&inline_fragment.inclusion_conditions);
        if inclusion_result == InclusionResult::Skipped {
            return None;
        }

        let parent_type = &inline_fragment.selection_set.parent_type;
        let type_ = if parent_type_info.scope().matches(parent_type) {
            None
        } else {
            Some(parent_type.clone())
        };

        Some(ScopeCondition::new(
            type_,
            inclusion_result.conditions().cloned(),
            None,
        ))
    }

    fn scope_condition_for_fragment_spread(
        &self,
        fragment_spread: &compilation_result::FragmentSpread,
        parent_type_info: &Arc<TypeInfo>,
        _is_deferred: bool,
    ) -> Option<ScopeCondition> {
        let inclusion_result = self.inclusion_result(&fragment_spread.inclusion_conditions);
        if inclusion_result == InclusionResult::Skipped {
            return None;
        }

        let parent_type = fragment_spread.parent_type();
        let type_ = if parent_type_info.scope().matches(parent_type) {
            None
        } else {
            Some(parent_type.clone())
        };

        Some(ScopeCondition::new(
            type_,
            inclusion_result.conditions().cloned(),
            None,
        ))
    }

    fn inclusion_result(
        &self,
        conditions: &Option<Vec<compilation_result::InclusionCondition>>,
    ) -> InclusionResult {
        match conditions {
            None => InclusionResult::Included,
            Some(conditions) => InclusionResult::all_of_compilation(conditions.iter().cloned()),
        }
    }

    // MARK: - Build Fields

    fn build_field(
        &mut self,
        field: &compilation_result::Field,
        enclosing_type_info: &Arc<TypeInfo>,
    ) -> Option<Field> {
        let inclusion_result = self.inclusion_result(&field.inclusion_conditions);
        if inclusion_result == InclusionResult::Skipped {
            return None;
        }

        let inclusion_conditions = inclusion_result.conditions().cloned();

        if field.type_.is_composite_type() {
            let ir_selection_set = self.build_selection_set_for_field(
                field,
                &inclusion_conditions,
                enclosing_type_info,
            );

            Some(Field::Entity(EntityField::new(
                Arc::new(field.clone()),
                AnyOf::from_option(inclusion_conditions),
                Arc::new(ir_selection_set),
            )))
        } else {
            Some(Field::Scalar(ScalarField::new(
                Arc::new(field.clone()),
                AnyOf::from_option(inclusion_conditions),
            )))
        }
    }

    fn build_selection_set_for_field(
        &mut self,
        field: &compilation_result::Field,
        inclusion_conditions: &Option<InclusionConditions>,
        enclosing_type_info: &Arc<TypeInfo>,
    ) -> SelectionSet {
        let field_selection_set = field
            .selection_set
            .as_ref()
            .unwrap_or_else(|| {
                panic!(
                    "SelectionSet cannot be created for non-entity type field {}.",
                    field.name
                )
            });

        let entity = self
            .entity_storage
            .entity_for_field(field, &enclosing_type_info.entity);

        let type_scope = ScopeDescriptor::descriptor(
            &field_selection_set.parent_type,
            inclusion_conditions.as_ref(),
            &self.schema().referenced_types,
        );
        let type_path = enclosing_type_info.scope_path.appending(type_scope);

        self.build_selection_set(field_selection_set, &entity, type_path)
    }

    // MARK: - Build Inline Fragment Spreads

    fn build_inline_fragment_spread_from_selection_set(
        &mut self,
        compiled_selection_set: &compilation_result::SelectionSet,
        scope_condition: &ScopeCondition,
        enclosing_type_info: &Arc<TypeInfo>,
        defer_condition: Option<compilation_result::DeferCondition>,
    ) -> InlineFragmentSpread {
        let scope = ScopeCondition::new(
            scope_condition.type_.clone(),
            if defer_condition.is_none() {
                scope_condition.conditions.clone()
            } else {
                None
            },
            defer_condition.clone(),
        );

        if scope.defer_condition.is_some() {
            self.contains_deferred_fragment = true;
        }

        let type_path = enclosing_type_info
            .scope_path
            .mutating_last(|s| s.appending(scope));

        let ir_selection_set = self.build_selection_set(
            compiled_selection_set,
            &enclosing_type_info.entity,
            type_path,
        );

        InlineFragmentSpread::new(Arc::new(ir_selection_set))
    }

    fn build_inline_fragment_spread_wrapping_selection(
        &mut self,
        selection: &compilation_result::Selection,
        scope_condition: &ScopeCondition,
        enclosing_type_info: &Arc<TypeInfo>,
    ) -> InlineFragmentSpread {
        let type_path = enclosing_type_info
            .scope_path
            .mutating_last(|s| s.appending(scope_condition.clone()));

        let wrapping_ss = compilation_result::SelectionSet {
            parent_type: enclosing_type_info.parent_type().clone(),
            selections: vec![selection.clone()],
        };

        let ir_selection_set = self.build_selection_set(
            &wrapping_ss,
            &enclosing_type_info.entity,
            type_path,
        );

        InlineFragmentSpread::new(Arc::new(ir_selection_set))
    }

    // MARK: - Build Named Fragment Spreads

    fn build_named_fragment_spread(
        &mut self,
        fragment_spread: &compilation_result::FragmentSpread,
        scope_condition: &ScopeCondition,
        parent_type_info: &Arc<TypeInfo>,
        defer_condition: Option<compilation_result::DeferCondition>,
    ) -> NamedFragmentSpread {
        let fragment = self.ir.build_fragment(&fragment_spread.fragment);
        self.referenced_fragments.insert(Arc::clone(&fragment));
        for ref_frag in &fragment.referenced_fragments {
            self.referenced_fragments.insert(Arc::clone(ref_frag));
        }

        let scope = ScopeCondition::new(
            scope_condition.type_.clone(),
            if defer_condition.is_none() {
                scope_condition.conditions.clone()
            } else {
                None
            },
            defer_condition.clone(),
        );

        if fragment.contains_deferred_fragment || scope.defer_condition.is_some() {
            self.contains_deferred_fragment = true;
        }

        let scope_path = if scope.is_empty() {
            parent_type_info.scope_path.clone()
        } else {
            parent_type_info
                .scope_path
                .mutating_last(|s| s.appending(scope.clone()))
        };

        let type_info = Arc::new(TypeInfo::new(
            Arc::clone(&parent_type_info.entity),
            scope_path,
        ));

        let fragment_spread_ir = NamedFragmentSpread::new(
            Arc::clone(&fragment),
            type_info,
            AnyOf::from_option(scope.conditions),
        );

        if fragment_spread_ir.type_info.defer_condition().is_none() {
            self.merge_all_selections_into_entity_selection_trees(&fragment_spread_ir);
        }

        fragment_spread_ir
    }

    fn merge_all_selections_into_entity_selection_trees(
        &mut self,
        fragment_spread: &NamedFragmentSpread,
    ) {
        for (_, fragment_entity) in &fragment_spread.fragment.entity_storage.entities_for_fields {
            let entity = self.entity_storage.entity_for_fragment_entity(
                fragment_entity,
                &fragment_spread.type_info,
            );

            // Merge the fragment entity's selection tree into the operation entity's tree.
            // Both selection_trees are behind RwLock per D-30.
            let fragment_tree = fragment_entity
                .selection_tree
                .read()
                .expect("fragment selection_tree lock poisoned");
            entity
                .selection_tree
                .write()
                .expect("entity selection_tree lock poisoned")
                .merge_in_tree(&fragment_tree, fragment_spread);
        }
    }
}

// MARK: - GraphQLType named_type extension

/// Extension trait to check if a GraphQLType's inner named type is a composite type.
trait GraphQLTypeExt {
    fn is_composite_type(&self) -> bool;
}

impl GraphQLTypeExt for GraphQLType {
    fn is_composite_type(&self) -> bool {
        match self {
            GraphQLType::Entity(_) => true,
            GraphQLType::Scalar(_) | GraphQLType::Enum(_) | GraphQLType::InputObject(_) => false,
            GraphQLType::NonNull(inner) | GraphQLType::List(inner) => inner.is_composite_type(),
        }
    }
}
