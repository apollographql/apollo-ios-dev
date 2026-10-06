//! IR Serialization for comparison testing (D-33).
//!
//! Provides canonical JSON serialization for IR types via `serde_json::Value` construction.
//! Uses direct Value construction instead of `serde::Serialize` trait impls to avoid
//! compile-time type recursion caused by mutual references between IR types
//! (SelectionSet <-> DirectSelections <-> Field <-> EntityField <-> SelectionSet).
//!
//! Cycle-breaking strategy:
//! - Operation.referenced_fragments -> Vec<String> of fragment names
//! - NamedFragment.referenced_fragments -> Vec<String> of fragment names
//! - NamedFragmentSpread.fragment -> String (fragment name)
//! - Entity -> location + root_type_path only (skip EntitySelectionTree)
//! - TypeInfo -> entity location path, not Arc pointer; skip derived_from_merged_sources
//! - ScopeDescriptor -> skip all_types_in_schema
//! - GraphQLCompositeType/GraphQLType -> Display string to avoid recursive schema types

use std::sync::Arc;

use serde_json::{json, Map, Value};

use crate::definition_entity_storage::DefinitionEntityStorage;
use crate::direct_selections::DirectSelections;
use crate::entity::{Entity, FieldComponent, Location, SourceDefinition};
use crate::fields::{EntityField, Field, ScalarField};
use crate::inclusion_conditions::{AnyOf, InclusionCondition, InclusionConditions};
use crate::inline_fragment_spread::InlineFragmentSpread;
use crate::named_fragment::NamedFragment;
use crate::named_fragment_spread::NamedFragmentSpread;
use crate::operation::Operation;
use crate::scope_descriptor::{ScopeCondition, ScopeDescriptor};
use crate::selection_set::{SelectionSet, TypeInfo};

// MARK: - Top-level serialization functions

/// Serialize an Operation to canonical JSON for comparison testing (D-33).
pub fn serialize_operation_to_json(operation: &Operation) -> String {
    let value = operation_to_value(operation);
    serde_json::to_string_pretty(&value).expect("IR serialization failed")
}

/// Serialize a NamedFragment to canonical JSON for comparison testing (D-33).
pub fn serialize_fragment_to_json(fragment: &NamedFragment) -> String {
    let value = named_fragment_to_value(fragment);
    serde_json::to_string_pretty(&value).expect("IR serialization failed")
}

// MARK: - Operation & Fragment

fn operation_to_value(op: &Operation) -> Value {
    let fragment_names: Vec<&str> = op.referenced_fragments.iter().map(|f| f.name()).collect();
    json!({
        "name": op.definition.name,
        "operation_type": format!("{}", op.definition.operation_type),
        "root_field": entity_field_to_value(&op.root_field),
        "referenced_fragments": fragment_names,
        "entity_count": op.entity_storage.entities_for_fields.len(),
        "contains_deferred_fragment": op.contains_deferred_fragment,
    })
}

fn named_fragment_to_value(frag: &NamedFragment) -> Value {
    let fragment_names: Vec<&str> = frag.referenced_fragments.iter().map(|f| f.name()).collect();
    json!({
        "name": frag.definition.name,
        "type": frag.definition.type_.to_string(),
        "root_field": entity_field_to_value(&frag.root_field),
        "referenced_fragments": fragment_names,
        "entity_count": frag.entity_storage.entities_for_fields.len(),
        "contains_deferred_fragment": frag.contains_deferred_fragment,
    })
}

// MARK: - Fields

fn field_to_value(field: &Field) -> Value {
    match field {
        Field::Scalar(f) => scalar_field_to_value(f),
        Field::Entity(f) => entity_field_to_value(f),
    }
}

fn scalar_field_to_value(f: &ScalarField) -> Value {
    let mut obj = Map::new();
    obj.insert("kind".to_string(), json!("scalar"));
    obj.insert("name".to_string(), json!(f.underlying_field.name));
    if let Some(ref alias) = f.underlying_field.alias {
        obj.insert("alias".to_string(), json!(alias));
    }
    obj.insert("type".to_string(), json!(f.underlying_field.type_.to_string()));
    if let Some(ref conditions) = f.inclusion_conditions {
        obj.insert("inclusion_conditions".to_string(), any_of_conditions_to_value(conditions));
    }
    Value::Object(obj)
}

fn entity_field_to_value(f: &EntityField) -> Value {
    let mut obj = Map::new();
    obj.insert("kind".to_string(), json!("entity"));
    obj.insert("name".to_string(), json!(f.underlying_field.name));
    if let Some(ref alias) = f.underlying_field.alias {
        obj.insert("alias".to_string(), json!(alias));
    }
    obj.insert("type".to_string(), json!(f.underlying_field.type_.to_string()));
    if let Some(ref conditions) = f.inclusion_conditions {
        obj.insert("inclusion_conditions".to_string(), any_of_conditions_to_value(conditions));
    }
    obj.insert("selection_set".to_string(), selection_set_to_value(&f.selection_set));
    Value::Object(obj)
}

// MARK: - SelectionSet & TypeInfo

fn selection_set_to_value(ss: &SelectionSet) -> Value {
    let mut obj = Map::new();
    obj.insert("type_info".to_string(), type_info_to_value(&ss.type_info));
    if let Some(ref selections) = ss.selections {
        obj.insert("selections".to_string(), direct_selections_to_value(selections));
    }
    Value::Object(obj)
}

fn type_info_to_value(ti: &TypeInfo) -> Value {
    json!({
        "entity_location": location_to_value(&ti.entity.location),
        "entity_root_type": ti.entity.root_type().to_string(),
        "scope_path": ti.scope_path.iter().map(scope_descriptor_to_value).collect::<Vec<_>>(),
    })
}

// MARK: - DirectSelections

fn direct_selections_to_value(ds: &DirectSelections) -> Value {
    let fields: Map<String, Value> = ds.fields.iter()
        .map(|(k, v)| (k.clone(), field_to_value(v)))
        .collect();
    let inlines: Map<String, Value> = ds.inline_fragments.iter()
        .map(|(k, v)| (k.to_string(), inline_fragment_spread_to_value(v)))
        .collect();
    let named: Map<String, Value> = ds.named_fragments.iter()
        .map(|(k, v)| (k.clone(), named_fragment_spread_to_value(v)))
        .collect();
    json!({
        "fields": fields,
        "inline_fragments": inlines,
        "named_fragments": named,
    })
}

// MARK: - Fragment Spreads

fn inline_fragment_spread_to_value(ifs: &InlineFragmentSpread) -> Value {
    selection_set_to_value(&ifs.selection_set)
}

/// Serialize fragment name only (not full Arc<NamedFragment>) to avoid cycles.
fn named_fragment_spread_to_value(nfs: &NamedFragmentSpread) -> Value {
    let mut obj = Map::new();
    obj.insert("fragment_name".to_string(), json!(nfs.fragment.name()));
    obj.insert("type_info".to_string(), type_info_to_value(&nfs.type_info));
    if let Some(ref conditions) = nfs.inclusion_conditions {
        obj.insert("inclusion_conditions".to_string(), any_of_conditions_to_value(conditions));
    }
    Value::Object(obj)
}

// MARK: - Entity & Location

fn entity_to_value(entity: &Entity) -> Value {
    json!({
        "location": location_to_value(&entity.location),
        "root_type_path": entity.root_type_path().iter()
            .map(|t| t.to_string())
            .collect::<Vec<_>>(),
    })
}

fn location_to_value(loc: &Location) -> Value {
    json!({
        "source": source_definition_to_value(&loc.source),
        "field_path": loc.field_path.as_ref().map(|fp|
            fp.iter().map(field_component_to_value).collect::<Vec<_>>()
        ),
    })
}

fn source_definition_to_value(sd: &SourceDefinition) -> Value {
    json!(sd.to_string())
}

fn field_component_to_value(fc: &FieldComponent) -> Value {
    json!({
        "name": fc.name,
        "type": fc.type_.to_string(),
    })
}

// MARK: - Scope

fn scope_descriptor_to_value(sd: &ScopeDescriptor) -> Value {
    let matching_type_names: Vec<String> = sd.matching_types.iter()
        .map(|t| t.to_string())
        .collect();
    json!({
        "type": sd.type_.to_string(),
        "scope_path": sd.scope_path.iter()
            .map(scope_condition_to_value)
            .collect::<Vec<_>>(),
        "matching_types": matching_type_names,
    })
}

fn scope_condition_to_value(sc: &ScopeCondition) -> Value {
    let mut obj = Map::new();
    if let Some(ref t) = sc.type_ {
        obj.insert("type".to_string(), json!(t.to_string()));
    }
    if let Some(ref c) = sc.conditions {
        obj.insert("conditions".to_string(), inclusion_conditions_to_value(c));
    }
    if let Some(ref d) = sc.defer_condition {
        obj.insert("defer_condition".to_string(), json!({
            "label": d.label,
            "variable": d.variable,
        }));
    }
    Value::Object(obj)
}

// MARK: - InclusionConditions

fn inclusion_condition_to_value(ic: &InclusionCondition) -> Value {
    json!({
        "variable": ic.variable,
        "is_inverted": ic.is_inverted,
    })
}

fn inclusion_conditions_to_value(ics: &InclusionConditions) -> Value {
    Value::Array(ics.iter().map(inclusion_condition_to_value).collect())
}

fn any_of_conditions_to_value(any_of: &AnyOf<InclusionConditions>) -> Value {
    Value::Array(any_of.elements.iter().map(inclusion_conditions_to_value).collect())
}

// MARK: - DefinitionEntityStorage

#[allow(dead_code)]
fn definition_entity_storage_to_value(des: &DefinitionEntityStorage) -> Value {
    let entities: Map<String, Value> = des.entities_for_fields.iter()
        .map(|(loc, entity)| (
            format!("{}", loc.source),
            location_to_value(&entity.location),
        ))
        .collect();
    Value::Object(entities)
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inclusion_condition_serializes_correctly() {
        let ic = InclusionCondition::new("showName".to_string(), false);
        let value = inclusion_condition_to_value(&ic);
        assert_eq!(value["variable"], "showName");
        assert_eq!(value["is_inverted"], false);
    }

    #[test]
    fn inclusion_condition_inverted_serializes_correctly() {
        let ic = InclusionCondition::new("hideName".to_string(), true);
        let value = inclusion_condition_to_value(&ic);
        assert_eq!(value["variable"], "hideName");
        assert_eq!(value["is_inverted"], true);
    }
}
