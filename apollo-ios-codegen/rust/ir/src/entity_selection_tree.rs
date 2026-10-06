//! EntitySelectionTree -- a tree structure representing the selection sets for an entity
//! across all type scopes.
//!
//! This data structure is used to memoize the selections for an `Entity` to quickly compute
//! the `mergedSelections` for `SelectionSet`s.
//!
//! During the creation of `SelectionSet`s, their `selections` are added to their entities
//! mergedSelectionTree at the appropriate type scope. After all `SelectionSet`s have been added
//! to the `EntitySelectionTree`, the tree can be quickly traversed to collect the selections
//! that will be selected for a given `SelectionSet`'s type scope.
//!
//! Mirrors `IR.EntitySelectionTree` from `IR+EntitySelectionTree.swift` (604 lines).

use std::fmt;
use std::sync::Arc;

use graphql_compiler::GraphQLCompositeType;
use indexmap::IndexMap;
use utilities::linked_list::{LinkedList, NodeRef};

use crate::direct_selections::DirectSelections;
use crate::fields::Field;
use crate::merged_selections::{MergedSource, MergingStrategy};
use crate::named_fragment_spread::NamedFragmentSpread;
use crate::scope_descriptor::{ScopeCondition, ScopeDescriptor};
use crate::scoped_selection_set_hashable::ScopedSelectionSetHashable;
use crate::selection_set::TypeInfo;

// MARK: - EntitySelectionTree

/// Represents the selections for an entity at different nested type scopes in a tree.
///
/// Mirrors `EntitySelectionTree` from Swift's IR module.
#[derive(Debug)]
pub struct EntitySelectionTree {
    pub(crate) root_type_path: LinkedList<GraphQLCompositeType>,
    pub(crate) root_node: EntityNode,
}

impl EntitySelectionTree {
    pub(crate) fn new(root_type_path: LinkedList<GraphQLCompositeType>) -> Self {
        let root_node = EntityNode::from_root_type_path(&root_type_path);
        EntitySelectionTree {
            root_type_path,
            root_node,
        }
    }

    // MARK: - Merge Selection Sets Into Tree

    /// Merges direct selections into the tree at the appropriate scope.
    pub(crate) fn merge_in_selections(
        &mut self,
        selections: &DirectSelections,
        type_info: &Arc<TypeInfo>,
    ) {
        let source = MergedSource {
            type_info: Arc::clone(type_info),
            fragment: None,
        };
        self.merge_in_selections_from_source(selections, source);
    }

    fn merge_in_selections_from_source(
        &mut self,
        selections: &DirectSelections,
        source: MergedSource,
    ) {
        if selections.fields.is_empty() && selections.named_fragments.is_empty() {
            return;
        }

        let scope_path = &source.type_info.scope_path;
        let root_type_path = &self.root_type_path;

        // Navigate to the target node using scope path information
        let target_node = Self::find_or_create_node(
            scope_path.head_node(),
            scope_path.head_node().value().scope_path.head_node(),
            &mut self.root_node,
            self.root_type_path.head_node(),
            root_type_path,
            0, // recursion depth
        );

        target_node.merge_in_selections(selections, source);
    }

    /// Recursive tree traversal to find or create the node at the correct scope position.
    ///
    /// Uses NodeRef for three cursors:
    /// - `current_entity_scope`: position in the scope path (LinkedList<ScopeDescriptor>)
    /// - `current_condition_path`: position in the entity's condition path (LinkedList<ScopeCondition>)
    /// - `current_root_type_path`: position in the root type path (LinkedList<GraphQLCompositeType>)
    fn find_or_create_node<'a>(
        current_entity_scope: NodeRef<'_, ScopeDescriptor>,
        current_condition_path: NodeRef<'_, ScopeCondition>,
        node: &'a mut EntityNode,
        current_root_type_path: NodeRef<'_, GraphQLCompositeType>,
        root_type_path: &LinkedList<GraphQLCompositeType>,
        depth: usize,
    ) -> &'a mut EntityNode {
        // T-04-08: Recursion limit check
        assert!(
            depth <= 100,
            "EntitySelectionTree recursion depth exceeded 100. No valid GraphQL query nests this deep."
        );

        // Swift: guard let nextEntityTypePath = currentRootTypePathNode.next
        let Some(next_root_type) = current_root_type_path.next() else {
            // Advance to field node in current entity & type case
            return Self::find_or_create_node_by_condition(
                current_entity_scope.value().scope_path.head_node(),
                node,
                depth,
            );
        };

        // Swift: guard let nextConditionPathForCurrentEntity = currentEntityConditionPath.next
        let Some(next_condition_path) = current_condition_path.next() else {
            // Advance to next entity
            let next_entity_scope = current_entity_scope
                .next()
                .expect("Expected next entity scope");

            let next_entity_node = node.child_as_entity_node(root_type_path);
            let condition_path = next_entity_scope.value().scope_path.head_node();

            return Self::find_or_create_node(
                next_entity_scope,
                condition_path,
                next_entity_node,
                next_root_type,
                root_type_path,
                depth + 1,
            );
        };

        // Advance to next type case in current entity
        let next_condition = next_condition_path.value();

        let next_node = if node.scope != *next_condition {
            node.scope_condition_node(next_condition)
        } else {
            node
        };

        Self::find_or_create_node(
            current_entity_scope,
            next_condition_path,
            next_node,
            current_root_type_path,
            root_type_path,
            depth + 1,
        )
    }

    /// Walks the condition scope path to find/create nodes for type cases and inclusion conditions.
    fn find_or_create_node_by_condition<'a>(
        selections_scope_path: NodeRef<'_, ScopeCondition>,
        node: &'a mut EntityNode,
        depth: usize,
    ) -> &'a mut EntityNode {
        assert!(
            depth <= 100,
            "EntitySelectionTree recursion depth exceeded 100."
        );

        // If scopes don't match, navigate to the scope condition child first
        let node = if *selections_scope_path.value() != node.scope {
            node.scope_condition_node(selections_scope_path.value())
        } else {
            node
        };

        let Some(next_condition) = selections_scope_path.next() else {
            return node;
        };

        Self::find_or_create_node_by_condition(next_condition, node, depth + 1)
    }

    // MARK: - Merge Other Entity Trees

    /// Merges an `EntitySelectionTree` from a matching `Entity` in the given `NamedFragmentSpread`
    /// into the receiver.
    ///
    /// Precondition: This function assumes that the `EntitySelectionTree` being merged in
    /// represents the same entity in the response.
    pub(crate) fn merge_in_tree(
        &mut self,
        other_tree: &EntitySelectionTree,
        from_fragment_spread: &NamedFragmentSpread,
    ) {
        let other_tree_count = other_tree.root_type_path.count();
        let diff_to_root = self.root_type_path.count() as isize - other_tree_count as isize;

        assert!(
            diff_to_root >= 0,
            "Cannot merge in tree shallower than current tree."
        );

        let root_type_path = &self.root_type_path;
        let mut current = &mut self.root_node;
        for _ in 0..diff_to_root {
            current = current.child_as_entity_node(root_type_path);
        }
        current.merge_in_fragment_tree(other_tree, from_fragment_spread);
    }

    // MARK: - Calculate Merged Selections From Tree

    /// Adds merged selections from this tree into the ComputedSelectionSet builder.
    pub(crate) fn add_merged_selections(
        &self,
        type_info: &TypeInfo,
        merge_fn: &mut dyn FnMut(
            &EntityTreeScopeSelections,
            &MergedSource,
            MergingStrategy,
        ),
        inline_fragment_fn: &mut dyn FnMut(
            &ScopeCondition,
            &IndexMap<MergedSource, EntityTreeScopeSelections>,
            MergingStrategy,
        ),
    ) {
        let root_type_path = type_info.scope_path.head_node();
        let entity_type_scope_path = root_type_path.value().scope_path.head_node();
        self.root_node.merge_selections(
            root_type_path,
            entity_type_scope_path,
            type_info,
            MergingStrategy::ANCESTORS,
            None,
            merge_fn,
            inline_fragment_fn,
        );
    }
}

// MARK: - EntityNode

/// A node in the entity selection tree.
///
/// Mirrors Swift's `EntitySelectionTree.EntityNode`.
#[derive(Debug)]
pub struct EntityNode {
    /// The root type path node index for this entity node.
    root_type_path_index: usize,
    /// The type of this entity node.
    pub(crate) type_: GraphQLCompositeType,
    /// The scope condition at this node.
    pub(crate) scope: ScopeCondition,
    /// The child of this node -- either an entity node (for nested entities) or selections.
    child: Option<EntityNodeChild>,
    /// Scope condition children (type cases, inclusion conditions).
    scope_conditions: Option<IndexMap<ScopeCondition, EntityNode>>,
    /// Fragment trees that have been merged into this node.
    merged_fragment_trees: IndexMap<NamedFragmentSpreadKey, (NamedFragmentSpread, EntitySelectionTree)>,
}

/// Key type for fragment spread lookups in merged_fragment_trees.
/// Uses the fragment spread's type_info for identity, matching Swift's Hashable conformance.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct NamedFragmentSpreadKey {
    fragment_name: String,
    type_info_scope_path: utilities::linked_list::LinkedList<ScopeCondition>,
}

impl NamedFragmentSpreadKey {
    fn new(spread: &NamedFragmentSpread) -> Self {
        NamedFragmentSpreadKey {
            fragment_name: spread.fragment.name().to_string(),
            type_info_scope_path: LinkedList::from_collection(
                spread
                    .type_info
                    .scope_path
                    .iter()
                    .map(|sd| sd.scope_path.last().clone())
                    .collect::<Vec<_>>(),
            ),
        }
    }
}

/// The child content of an entity node.
#[derive(Debug)]
enum EntityNodeChild {
    /// A child entity node (for nested entity fields).
    Entity(Box<EntityNode>),
    /// Selections stored at this leaf node.
    Selections(IndexMap<MergedSource, EntityTreeScopeSelections>),
}

impl EntityNode {
    /// Creates an entity node from a root type path, building the chain of entity nodes.
    fn from_root_type_path(root_type_path: &LinkedList<GraphQLCompositeType>) -> Self {
        Self::from_type_node(root_type_path, 0)
    }

    /// Creates an entity node for a specific position in the root type path.
    fn from_type_node(root_type_path: &LinkedList<GraphQLCompositeType>, index: usize) -> Self {
        let type_ = root_type_path.node_at(index).clone();
        let scope = ScopeCondition::with_type(type_.clone());

        let child = if index + 1 < root_type_path.count() {
            Some(EntityNodeChild::Entity(Box::new(Self::from_type_node(
                root_type_path,
                index + 1,
            ))))
        } else {
            Some(EntityNodeChild::Selections(IndexMap::new()))
        };

        EntityNode {
            root_type_path_index: index,
            type_,
            scope,
            child,
            scope_conditions: None,
            merged_fragment_trees: IndexMap::new(),
        }
    }

    /// Creates an entity node with a specific scope condition (for type case/inclusion children).
    fn with_scope(
        scope: ScopeCondition,
        type_: GraphQLCompositeType,
        root_type_path_index: usize,
    ) -> Self {
        EntityNode {
            root_type_path_index,
            type_,
            scope,
            child: None,
            scope_conditions: None,
            merged_fragment_trees: IndexMap::new(),
        }
    }

    // MARK: - Merge selections into node

    fn merge_in_selections(&mut self, selections: &DirectSelections, source: MergedSource) {
        self.update_selections(|entity_selections| {
            let scope_selections = entity_selections
                .entry(source)
                .or_insert_with(EntityTreeScopeSelections::new);
            scope_selections.merge_in_direct(selections);
        });
    }

    fn merge_in_scope_selections(
        &mut self,
        selections: &EntityTreeScopeSelections,
        source: MergedSource,
    ) {
        self.update_selections(|entity_selections| {
            let scope_selections = entity_selections
                .entry(source)
                .or_insert_with(EntityTreeScopeSelections::new);
            scope_selections.merge_in(selections);
        });
    }

    fn update_selections(
        &mut self,
        block: impl FnOnce(&mut IndexMap<MergedSource, EntityTreeScopeSelections>),
    ) {
        let mut entity_selections = match self.child.take() {
            Some(EntityNodeChild::Selections(selections)) => selections,
            Some(EntityNodeChild::Entity(_)) => {
                panic!("Selection Merging Error. Please create an issue on Github to report this.");
            }
            None => IndexMap::new(),
        };

        block(&mut entity_selections);
        self.child = Some(EntityNodeChild::Selections(entity_selections));
    }

    // MARK: - Create/Get Child Nodes

    /// Returns the child as an entity node (for navigating to the next entity in the path).
    /// Lazily creates the child entity chain from the root type path if it doesn't exist yet.
    /// This matches Swift's `childAsEntityNode` which creates nodes on-demand.
    fn child_as_entity_node(
        &mut self,
        root_type_path: &LinkedList<GraphQLCompositeType>,
    ) -> &mut EntityNode {
        match &self.child {
            Some(EntityNodeChild::Entity(_)) => {}
            Some(EntityNodeChild::Selections(_)) => {
                panic!("Selection Merging Error. Please create an issue on Github to report this.");
            }
            None => {
                // Lazily create the child entity chain from the root type path,
                // matching Swift's EntityNode(typeNode: self.rootTypePathNode.next!)
                let next_type_index = self.root_type_path_index + 1;
                self.child = Some(EntityNodeChild::Entity(Box::new(
                    EntityNode::from_type_node(root_type_path, next_type_index),
                )));
            }
        }
        match &mut self.child {
            Some(EntityNodeChild::Entity(node)) => node,
            _ => unreachable!(),
        }
    }

    /// Returns (or creates) the scope condition child node for the given condition.
    fn scope_condition_node(&mut self, condition: &ScopeCondition) -> &mut EntityNode {
        // Normalize the condition: if the type matches this node's type, remove it
        let node_condition = ScopeCondition::new(
            if condition.type_.as_ref() == Some(&self.type_) {
                None
            } else {
                condition.type_.clone()
            },
            condition.conditions.clone(),
            condition.defer_condition.clone(),
        );

        let scope_conditions = self.scope_conditions.get_or_insert_with(IndexMap::new);

        if scope_conditions.contains_key(&node_condition) {
            return scope_conditions.get_mut(&node_condition).unwrap();
        }

        // When initializing as a conditional scope node, if the scope does not have a
        // type condition, we should inherit the parent node's type.
        let node_type = node_condition
            .type_
            .clone()
            .unwrap_or_else(|| self.type_.clone());

        let new_node = EntityNode::with_scope(
            node_condition.clone(),
            node_type,
            self.root_type_path_index,
        );

        scope_conditions.insert(node_condition.clone(), new_node);
        scope_conditions.get_mut(&node_condition).unwrap()
    }

    // MARK: - Merge In Fragment Trees

    fn find_or_create_from_fragment_scope<'a>(
        fragment_scope_path: NodeRef<'_, ScopeCondition>,
        root_node: &'a mut EntityNode,
    ) -> &'a mut EntityNode {
        let Some(next_fragment_node) = fragment_scope_path.next() else {
            return root_node;
        };
        let next_node = root_node.scope_condition_node(next_fragment_node.value());
        Self::find_or_create_from_fragment_scope(next_fragment_node, next_node)
    }

    fn merge_in_fragment_tree(
        &mut self,
        fragment_tree: &EntitySelectionTree,
        fragment_spread: &NamedFragmentSpread,
    ) {
        let fragment_scope_path = fragment_spread
            .type_info
            .scope_path
            .last_node()
            .value()
            .scope_path
            .head_node();

        let root_node_ref = Self::find_or_create_from_fragment_scope(
            fragment_scope_path,
            self,
        );

        let fragment_type = fragment_spread.type_info.parent_type();
        let root_types_match = root_node_ref.type_ == *fragment_type;

        if let Some(ref inclusion_conditions) = fragment_spread.inclusion_conditions {
            for condition_group in &inclusion_conditions.elements {
                let scope = ScopeCondition::new(
                    if root_types_match {
                        None
                    } else {
                        Some(fragment_type.clone())
                    },
                    Some(condition_group.clone()),
                    None,
                );
                let node_for_merge = root_node_ref.scope_condition_node(&scope);
                let key = NamedFragmentSpreadKey::new(fragment_spread);
                node_for_merge
                    .merged_fragment_trees
                    .insert(key, (fragment_spread.clone(), clone_tree(fragment_tree)));
            }
        } else {
            let node_for_merge = if root_types_match {
                root_node_ref
            } else {
                root_node_ref.scope_condition_node(&ScopeCondition::with_type(
                    fragment_type.clone(),
                ))
            };
            let key = NamedFragmentSpreadKey::new(fragment_spread);
            node_for_merge
                .merged_fragment_trees
                .insert(key, (fragment_spread.clone(), clone_tree(fragment_tree)));
        }
    }

    // MARK: - Calculate Merged Selections

    #[allow(clippy::too_many_arguments)]
    fn merge_selections(
        &self,
        entity_path_node: NodeRef<'_, ScopeDescriptor>,
        entity_type_scope_path: NodeRef<'_, ScopeCondition>,
        target_type_info: &TypeInfo,
        current_merge_strategy: MergingStrategy,
        transform_source: Option<&dyn Fn(&MergedSource) -> MergedSource>,
        merge_fn: &mut dyn FnMut(
            &EntityTreeScopeSelections,
            &MergedSource,
            MergingStrategy,
        ),
        inline_fragment_fn: &mut dyn FnMut(
            &ScopeCondition,
            &IndexMap<MergedSource, EntityTreeScopeSelections>,
            MergingStrategy,
        ),
    ) {
        match &self.child {
            Some(EntityNodeChild::Entity(entity_node)) => {
                let Some(next_scope_path_node) = entity_path_node.next() else {
                    return;
                };

                let merge_strategy = self.calculate_merge_strategy_for_next_entity_node(
                    current_merge_strategy,
                    entity_type_scope_path,
                );

                entity_node.merge_selections(
                    next_scope_path_node,
                    next_scope_path_node.value().scope_path.head_node(),
                    target_type_info,
                    merge_strategy,
                    transform_source,
                    merge_fn,
                    inline_fragment_fn,
                );
            }
            Some(EntityNodeChild::Selections(selections)) => {
                // Returns `true` if the current selection node represents the target's typeInfo exactly.
                let is_targets_exact_scope =
                    entity_type_scope_path.next().is_none()
                        && current_merge_strategy == MergingStrategy::ANCESTORS;
                let merge_strategy = if is_targets_exact_scope {
                    MergingStrategy::empty()
                } else {
                    current_merge_strategy
                };

                for (source, scope_selections) in selections {
                    let effective_source = if let Some(transform) = &transform_source {
                        transform(source)
                    } else {
                        source.clone()
                    };
                    merge_fn(scope_selections, &effective_source, merge_strategy);
                }
            }
            None => {}
        }

        // Process scope condition children
        if let Some(ref scope_conditions) = self.scope_conditions {
            for (condition, node) in scope_conditions {
                // Skip deferred nodes
                if node.scope.is_deferred() {
                    continue;
                }

                if let Some(next_type_path) = entity_type_scope_path.next() {
                    if *next_type_path.value() == *condition {
                        // Ancestor
                        node.merge_selections(
                            entity_path_node,
                            next_type_path,
                            target_type_info,
                            MergingStrategy::ANCESTORS,
                            transform_source,
                            merge_fn,
                            inline_fragment_fn,
                        );
                        continue;
                    }
                }

                if entity_path_node.value().matches_scope_condition(condition) {
                    // Sibling
                    node.merge_selections(
                        entity_path_node,
                        entity_type_scope_path,
                        target_type_info,
                        MergingStrategy::SIBLINGS,
                        transform_source,
                        merge_fn,
                        inline_fragment_fn,
                    );
                } else if let Some(EntityNodeChild::Selections(_)) = &self.child {
                    if let Some(EntityNodeChild::Selections(condition_selections)) = &node.child {
                        inline_fragment_fn(
                            condition,
                            condition_selections,
                            current_merge_strategy,
                        );
                    }
                }
            }
        }

        // Add selections from merged fragments
        for (_, (fragment_spread, merged_fragment_tree)) in &self.merged_fragment_trees {
            // If typeInfo is equal, we are merging the fragment's selections into the selection set
            // that directly selected the fragment. The merge strategy should be just .namedFragments.
            let merge_strategy = if *fragment_spread.type_info == *target_type_info {
                MergingStrategy::NAMED_FRAGMENTS
            } else {
                current_merge_strategy | MergingStrategy::NAMED_FRAGMENTS
            };

            let add_fragment_transform = |source: &MergedSource| -> MergedSource {
                if source.fragment.is_some() {
                    source.clone()
                } else {
                    MergedSource {
                        type_info: source.type_info.clone(),
                        fragment: Some(fragment_spread.fragment.clone()),
                    }
                }
            };

            merged_fragment_tree.root_node.merge_selections(
                entity_path_node,
                entity_type_scope_path,
                target_type_info,
                merge_strategy,
                Some(&add_fragment_transform),
                merge_fn,
                inline_fragment_fn,
            );
        }
    }

    fn calculate_merge_strategy_for_next_entity_node(
        &self,
        current_merge_strategy: MergingStrategy,
        current_entity_type_scope_path: NodeRef<'_, ScopeCondition>,
    ) -> MergingStrategy {
        if current_merge_strategy.contains(MergingStrategy::SIBLINGS) {
            return current_merge_strategy;
        }

        // If the current entity type scope is at the end of its path, we are traversing a direct
        // ancestor of the target selection set. Otherwise, we are traversing siblings.
        let mut new_merge_strategy = if current_entity_type_scope_path.next().is_none() {
            MergingStrategy::ANCESTORS
        } else {
            MergingStrategy::SIBLINGS
        };

        // If we are currently traversing through a named fragment, we need to keep that as part of
        // the merge strategy
        if current_merge_strategy.contains(MergingStrategy::NAMED_FRAGMENTS) {
            new_merge_strategy.insert(MergingStrategy::NAMED_FRAGMENTS);
        }

        new_merge_strategy
    }
}

// MARK: - EntityTreeScopeSelections

/// Selections stored at a specific scope in the entity selection tree.
///
/// Mirrors `EntityTreeScopeSelections` from `IR+EntitySelectionTree.swift`.
#[derive(Clone, Debug)]
pub struct EntityTreeScopeSelections {
    pub(crate) fields: IndexMap<String, Field>,
    pub(crate) named_fragments: IndexMap<String, NamedFragmentSpread>,
}

impl EntityTreeScopeSelections {
    pub fn new() -> Self {
        EntityTreeScopeSelections {
            fields: IndexMap::new(),
            named_fragments: IndexMap::new(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.fields.is_empty() && self.named_fragments.is_empty()
    }

    fn merge_in_field(&mut self, field: &Field) {
        self.fields
            .insert(field.hash_for_selection_set_scope().to_string(), field.clone());
    }

    fn merge_in_fragment(&mut self, fragment: &NamedFragmentSpread) {
        self.named_fragments.insert(
            fragment.hash_for_selection_set_scope().to_string(),
            fragment.clone(),
        );
    }

    pub fn merge_in_direct(&mut self, selections: &DirectSelections) {
        for field in selections.fields.values() {
            self.merge_in_field(field);
        }
        for fragment in selections.named_fragments.values() {
            self.merge_in_fragment(fragment);
        }
    }

    pub fn merge_in(&mut self, other: &EntityTreeScopeSelections) {
        for field in other.fields.values() {
            self.merge_in_field(field);
        }
        for fragment in other.named_fragments.values() {
            self.merge_in_fragment(fragment);
        }
    }
}

impl Default for EntityTreeScopeSelections {
    fn default() -> Self {
        Self::new()
    }
}

impl PartialEq for EntityTreeScopeSelections {
    fn eq(&self, other: &Self) -> bool {
        self.fields == other.fields && self.named_fragments == other.named_fragments
    }
}

impl Eq for EntityTreeScopeSelections {}

impl fmt::Display for EntityTreeScopeSelections {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Fields: {:?}, Fragments: {:?}",
            self.fields.keys().collect::<Vec<_>>(),
            self.named_fragments.keys().collect::<Vec<_>>()
        )
    }
}

// MARK: - Helper Functions

/// Clones an EntitySelectionTree (deep clone of the tree structure).
fn clone_tree(tree: &EntitySelectionTree) -> EntitySelectionTree {
    EntitySelectionTree {
        root_type_path: tree.root_type_path.clone(),
        root_node: clone_node(&tree.root_node),
    }
}

fn clone_node(node: &EntityNode) -> EntityNode {
    EntityNode {
        root_type_path_index: node.root_type_path_index,
        type_: node.type_.clone(),
        scope: node.scope.clone(),
        child: node.child.as_ref().map(|c| match c {
            EntityNodeChild::Entity(e) => EntityNodeChild::Entity(Box::new(clone_node(e))),
            EntityNodeChild::Selections(s) => EntityNodeChild::Selections(s.clone()),
        }),
        scope_conditions: node.scope_conditions.as_ref().map(|sc| {
            sc.iter()
                .map(|(k, v)| (k.clone(), clone_node(v)))
                .collect()
        }),
        merged_fragment_trees: node
            .merged_fragment_trees
            .iter()
            .map(|(k, (spread, tree))| (k.clone(), (spread.clone(), clone_tree(tree))))
            .collect(),
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entity::Entity;
    use crate::entity::SourceDefinition;
    use crate::fields::ScalarField;
    use crate::schema::ReferencedTypes;
    use graphql_compiler::compilation_result;
    use graphql_compiler::{
        GraphQLCompositeType, GraphQLName, GraphQLNamedType, GraphQLObjectType,
        GraphQLScalarType, GraphQLType, RootTypeDefinition,
    };
    use std::sync::Arc;

    fn make_object(name: &str) -> Arc<GraphQLObjectType> {
        Arc::new(GraphQLObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        })
    }

    fn make_root_types() -> RootTypeDefinition {
        RootTypeDefinition {
            query_type: GraphQLNamedType::Object(make_object("Query")),
            mutation_type: None,
            subscription_type: None,
        }
    }

    fn make_referenced_types(types: &[GraphQLNamedType]) -> Arc<ReferencedTypes> {
        Arc::new(ReferencedTypes::new(types, make_root_types()))
    }

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

    #[test]
    fn tree_new_creates_entity_node_chain() {
        let query = make_object("Query");
        let root_type_path = LinkedList::new(GraphQLCompositeType::Object(query));
        let tree = EntitySelectionTree::new(root_type_path);

        // Root node should have selections child (single type in path)
        match &tree.root_node.child {
            Some(EntityNodeChild::Selections(s)) => assert!(s.is_empty()),
            _ => panic!("Expected selections child on single-element root type path"),
        }
    }

    #[test]
    fn tree_new_nested_creates_entity_chain() {
        let query = make_object("Query");
        let user = make_object("User");
        let mut root_type_path = LinkedList::new(GraphQLCompositeType::Object(query));
        root_type_path.append(GraphQLCompositeType::Object(user));
        let tree = EntitySelectionTree::new(root_type_path);

        // Root node should have entity child
        match &tree.root_node.child {
            Some(EntityNodeChild::Entity(child)) => {
                // Child should have selections
                match &child.child {
                    Some(EntityNodeChild::Selections(s)) => assert!(s.is_empty()),
                    _ => panic!("Expected selections child on second entity node"),
                }
            }
            _ => panic!("Expected entity child on root with multi-element type path"),
        }
    }

    #[test]
    fn merge_in_single_scope_stores_selections() {
        let query_obj = make_object("Query");
        let query_type = GraphQLCompositeType::Object(Arc::clone(&query_obj));
        let root_type_path = LinkedList::new(query_type.clone());

        let mut tree = EntitySelectionTree::new(root_type_path);

        let all_types = make_referenced_types(&[GraphQLNamedType::Object(Arc::clone(&query_obj))]);
        let scope = ScopeDescriptor::descriptor(&query_type, None, &all_types);

        let op_def = Arc::new(compilation_result::OperationDefinition {
            name: "TestOp".to_string(),
            operation_type: compilation_result::OperationType::Query,
            variables: vec![],
            root_type: query_type.clone(),
            selection_set: compilation_result::SelectionSet {
                parent_type: query_type.clone(),
                selections: vec![],
            },
            directives: None,
            referenced_fragments: vec![],
            source: String::new(),
            file_path: String::new(),
        });

        let source = SourceDefinition::Operation(op_def);
        let entity = Arc::new(Entity::new_root(source));
        let type_info = Arc::new(TypeInfo::new(Arc::clone(&entity), LinkedList::new(scope)));

        let mut selections = DirectSelections::new();
        selections.merge_in_field(make_scalar_field("name"));
        selections.merge_in_field(make_scalar_field("age"));

        tree.merge_in_selections(&selections, &type_info);

        // Verify selections were stored
        match &tree.root_node.child {
            Some(EntityNodeChild::Selections(stored)) => {
                assert_eq!(stored.len(), 1); // One source
                let scope_sel = stored.values().next().unwrap();
                assert_eq!(scope_sel.fields.len(), 2);
                assert!(scope_sel.fields.contains_key("name"));
                assert!(scope_sel.fields.contains_key("age"));
            }
            _ => panic!("Expected selections child after merge"),
        }
    }

    #[test]
    fn tree_scope_condition_node_creates_child() {
        let query_obj = make_object("Query");
        let query_type = GraphQLCompositeType::Object(Arc::clone(&query_obj));
        let root_type_path = LinkedList::new(query_type.clone());

        let mut tree = EntitySelectionTree::new(root_type_path);

        let user_obj = make_object("User");
        let user_type = GraphQLCompositeType::Object(user_obj);
        let condition = ScopeCondition::with_type(user_type.clone());

        let scope_node = tree.root_node.scope_condition_node(&condition);
        assert_eq!(scope_node.type_, user_type);

        // Verify it's stored
        assert!(tree.root_node.scope_conditions.is_some());
        assert_eq!(tree.root_node.scope_conditions.as_ref().unwrap().len(), 1);
    }

    #[test]
    fn scope_condition_node_returns_existing() {
        let query_obj = make_object("Query");
        let query_type = GraphQLCompositeType::Object(Arc::clone(&query_obj));
        let root_type_path = LinkedList::new(query_type.clone());

        let mut tree = EntitySelectionTree::new(root_type_path);

        let user_obj = make_object("User");
        let user_type = GraphQLCompositeType::Object(user_obj);
        let condition = ScopeCondition::with_type(user_type.clone());

        // Create first
        let _node1 = tree.root_node.scope_condition_node(&condition);
        // Get same
        let _node2 = tree.root_node.scope_condition_node(&condition);

        // Should still be just 1 entry
        assert_eq!(tree.root_node.scope_conditions.as_ref().unwrap().len(), 1);
    }
}
