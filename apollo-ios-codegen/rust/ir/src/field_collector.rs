//! FieldCollector -- tracks fields per type using Mutex-based interior mutability.
//!
//! Mirrors `IR.FieldCollector` from `IR+FieldCollector.swift` (59 lines).
//! Uses Mutex per D-31 (Swift actor -> Rust Mutex).

use std::sync::Mutex;

use graphql_compiler::{compilation_result, GraphQLCompositeType, GraphQLInterfaceType, GraphQLType};
use indexmap::IndexMap;

// MARK: - FieldCollector

/// Collects fields referenced per type during IR construction.
///
/// In Swift this is an `actor`. In Rust we use `Mutex` per D-31.
/// All async functions become synchronous per D-32.
///
/// Mirrors `IR.FieldCollector` from `IR+FieldCollector.swift`.
pub struct FieldCollector {
    collected_fields: Mutex<
        IndexMap<
            GraphQLCompositeType,
            IndexMap<String, (GraphQLType, Option<String>)>,
        >,
    >,
}

/// Collected field tuple: (response_key, type, deprecation_reason).
pub type CollectedField = (String, GraphQLType, Option<String>);

impl FieldCollector {
    pub fn new() -> Self {
        FieldCollector {
            collected_fields: Mutex::new(IndexMap::new()),
        }
    }

    /// Collects fields from a selection set.
    ///
    /// Only collects for interface-implementing types (Object, Interface -- not Union).
    /// Mirrors Swift's `collectFields(from:)`.
    pub fn collect_fields(&self, from: &compilation_result::SelectionSet) {
        // Only collect for Object or Interface types (types that implement interfaces)
        let interfaces = match &from.parent_type {
            GraphQLCompositeType::Object(obj) => Some(&obj.interfaces),
            GraphQLCompositeType::Interface(iface) => Some(&iface.interfaces),
            GraphQLCompositeType::Union(_) => return, // Unions don't have fields
        };

        let _ = interfaces; // Used for type checking above

        let mut fields = self.collected_fields.lock().expect("lock poisoned");

        for selection in &from.selections {
            if let compilation_result::Selection::Field(field) = selection {
                Self::add_field_to_map(field, &from.parent_type, &mut fields);
            }
        }
    }

    fn add_field_to_map(
        field: &compilation_result::Field,
        type_: &GraphQLCompositeType,
        fields: &mut IndexMap<GraphQLCompositeType, IndexMap<String, (GraphQLType, Option<String>)>>,
    ) {
        let type_fields = fields.entry(type_.clone()).or_insert_with(IndexMap::new);
        let key = field.response_key().to_string();
        if !type_fields.contains_key(&key) {
            type_fields.insert(
                key,
                (field.type_.clone(), field.deprecation_reason.clone()),
            );
        }
    }

    /// Returns collected fields for a type, merging fields from all interfaces it implements.
    ///
    /// Returns fields sorted by field name.
    /// Mirrors Swift's `collectedFields(for:)`.
    pub fn collected_fields_for(
        &self,
        type_: &GraphQLCompositeType,
    ) -> Vec<CollectedField> {
        let fields = self.collected_fields.lock().expect("lock poisoned");

        let mut result: IndexMap<String, (GraphQLType, Option<String>)> =
            fields.get(type_).cloned().unwrap_or_default();

        // Merge fields from interfaces
        let interfaces = get_interfaces(type_);
        for interface in interfaces {
            let iface_type = GraphQLCompositeType::Interface(interface.clone());
            if let Some(interface_fields) = fields.get(&iface_type) {
                for (key, value) in interface_fields {
                    // Interfaces fields don't overwrite existing (merge semantics)
                    if !result.contains_key(key) {
                        result.insert(key.clone(), value.clone());
                    }
                }
            }
        }

        let mut sorted: Vec<CollectedField> = result
            .into_iter()
            .map(|(key, (type_, deprecation))| (key, type_, deprecation))
            .collect();
        sorted.sort_by(|a, b| a.0.cmp(&b.0));
        sorted
    }
}

impl Default for FieldCollector {
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Debug for FieldCollector {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("FieldCollector").finish()
    }
}

/// Returns interfaces for a composite type.
fn get_interfaces(type_: &GraphQLCompositeType) -> Vec<&std::sync::Arc<GraphQLInterfaceType>> {
    match type_ {
        GraphQLCompositeType::Object(obj) => obj.interfaces.iter().collect(),
        GraphQLCompositeType::Interface(iface) => iface.interfaces.iter().collect(),
        GraphQLCompositeType::Union(_) => vec![],
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    use graphql_compiler::{
        GraphQLName, GraphQLObjectType, GraphQLScalarType,
    };
    use std::sync::Arc;

    fn make_scalar_type() -> GraphQLType {
        GraphQLType::Scalar(Arc::new(GraphQLScalarType {
            name: GraphQLName::new("String".to_string()),
            documentation: None,
            specified_by_url: None,
        }))
    }

    fn make_int_type() -> GraphQLType {
        GraphQLType::Scalar(Arc::new(GraphQLScalarType {
            name: GraphQLName::new("Int".to_string()),
            documentation: None,
            specified_by_url: None,
        }))
    }

    fn make_object(name: &str) -> Arc<GraphQLObjectType> {
        Arc::new(GraphQLObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        })
    }

    fn make_field(name: &str, type_: GraphQLType) -> compilation_result::Field {
        compilation_result::Field {
            name: name.to_string(),
            alias: None,
            type_,
            arguments: None,
            inclusion_conditions: None,
            directives: None,
            selection_set: None,
            deprecation_reason: None,
            documentation: None,
        }
    }

    #[test]
    fn collect_fields_from_selection_set_with_two_fields() {
        let collector = FieldCollector::new();
        let obj = make_object("User");
        let parent_type = GraphQLCompositeType::Object(obj);

        let ss = compilation_result::SelectionSet {
            parent_type: parent_type.clone(),
            selections: vec![
                compilation_result::Selection::Field(make_field("name", make_scalar_type())),
                compilation_result::Selection::Field(make_field("age", make_int_type())),
            ],
        };

        collector.collect_fields(&ss);

        let fields = collector.collected_fields_for(&parent_type);
        assert_eq!(fields.len(), 2);
        // Sorted by name
        assert_eq!(fields[0].0, "age");
        assert_eq!(fields[1].0, "name");
    }

    #[test]
    fn collect_fields_does_not_duplicate_same_field() {
        let collector = FieldCollector::new();
        let obj = make_object("User");
        let parent_type = GraphQLCompositeType::Object(obj);

        let ss = compilation_result::SelectionSet {
            parent_type: parent_type.clone(),
            selections: vec![
                compilation_result::Selection::Field(make_field("name", make_scalar_type())),
            ],
        };

        collector.collect_fields(&ss);
        collector.collect_fields(&ss);

        let fields = collector.collected_fields_for(&parent_type);
        assert_eq!(fields.len(), 1);
    }

    #[test]
    fn collect_fields_ignores_union_types() {
        use graphql_compiler::GraphQLUnionType;

        let collector = FieldCollector::new();
        let union = Arc::new(GraphQLUnionType {
            name: GraphQLName::new("SearchResult".to_string()),
            documentation: None,
            types: vec![],
        });
        let parent_type = GraphQLCompositeType::Union(union);

        let ss = compilation_result::SelectionSet {
            parent_type: parent_type.clone(),
            selections: vec![
                compilation_result::Selection::Field(make_field("name", make_scalar_type())),
            ],
        };

        collector.collect_fields(&ss);

        let fields = collector.collected_fields_for(&parent_type);
        assert!(fields.is_empty());
    }
}
