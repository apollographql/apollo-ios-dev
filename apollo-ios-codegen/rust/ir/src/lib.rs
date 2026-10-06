// Phase 4: IR construction

pub mod definition;
pub mod definition_entity_storage;
pub mod direct_selections;
pub mod entity;
pub mod entity_selection_tree;
pub mod fields;
pub mod inclusion_conditions;
pub mod inline_fragment_spread;
pub mod merged_selections;
pub mod named_fragment;
pub mod named_fragment_spread;
pub mod operation;
pub mod schema;
pub mod scoped_selection_set_hashable;
pub mod scope_descriptor;
pub mod selection_set;
pub mod computed_selection_set;
pub mod builder;
pub(crate) mod root_field_builder;
pub mod field_collector;

pub use definition::Definition;
pub use definition_entity_storage::DefinitionEntityStorage;
pub use direct_selections::DirectSelections;
pub use entity::{Entity, FieldComponent, FieldPath, Location, SourceDefinition};
pub use entity_selection_tree::EntitySelectionTree;
pub use fields::{EntityField, Field, ScalarField};
pub use inclusion_conditions::{
    any_of_or, AnyOf, InclusionCondition, InclusionConditions, InclusionResult,
};
pub use inline_fragment_spread::InlineFragmentSpread;
pub use merged_selections::{MergedSource, MergingStrategy};
pub use named_fragment::NamedFragment;
pub use named_fragment_spread::NamedFragmentSpread;
pub use operation::Operation;
pub use schema::{ReferencedTypes, Schema};
pub use scope_descriptor::{ScopeCondition, ScopeDescriptor, TypeScope};
pub use scoped_selection_set_hashable::ScopedSelectionSetHashable;
pub use selection_set::{SelectionSet, TypeInfo};
pub use computed_selection_set::{ComputedSelectionSet, MergedSelections, Builder as ComputedSelectionSetBuilder};
pub use builder::IRBuilder;
pub use field_collector::FieldCollector;

pub mod serialize;
pub use serialize::{serialize_operation_to_json, serialize_fragment_to_json};
