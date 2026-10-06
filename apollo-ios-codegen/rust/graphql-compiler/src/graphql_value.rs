use indexmap::IndexMap;
use serde::Serialize;

/// A value in a GraphQL document.
/// Mirrors `GraphQLValue` from `GraphQLValue.swift`.
///
/// Has exactly 9 variants matching the Swift enum.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub enum GraphQLValue {
    Variable(String),
    Int(i64),
    Float(f64),
    String(String),
    Boolean(bool),
    Null,
    Enum(String),
    List(Vec<GraphQLValue>),
    Object(IndexMap<String, GraphQLValue>),
}

// Manual Hash implementation because f64 doesn't implement Hash.
// We use to_bits() for f64 hashing, matching the semantics needed
// for deterministic behavior.
impl std::hash::Hash for GraphQLValue {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        std::mem::discriminant(self).hash(state);
        match self {
            GraphQLValue::Variable(v) => v.hash(state),
            GraphQLValue::Int(v) => v.hash(state),
            GraphQLValue::Float(v) => v.to_bits().hash(state),
            GraphQLValue::String(v) => v.hash(state),
            GraphQLValue::Boolean(v) => v.hash(state),
            GraphQLValue::Null => {}
            GraphQLValue::Enum(v) => v.hash(state),
            GraphQLValue::List(v) => v.hash(state),
            GraphQLValue::Object(v) => {
                for (k, val) in v {
                    k.hash(state);
                    val.hash(state);
                }
            }
        }
    }
}

impl Eq for GraphQLValue {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_variable_variant() {
        let val = GraphQLValue::Variable("myVar".to_string());
        if let GraphQLValue::Variable(name) = &val {
            assert_eq!(name, "myVar");
        } else {
            panic!("Expected Variable variant");
        }
    }

    #[test]
    fn test_int_variant() {
        let val = GraphQLValue::Int(42);
        assert_eq!(val, GraphQLValue::Int(42));
    }

    #[test]
    fn test_float_variant() {
        let val = GraphQLValue::Float(3.14);
        assert_eq!(val, GraphQLValue::Float(3.14));
    }

    #[test]
    fn test_string_variant() {
        let val = GraphQLValue::String("hello".to_string());
        assert_eq!(val, GraphQLValue::String("hello".to_string()));
    }

    #[test]
    fn test_boolean_variant() {
        let val = GraphQLValue::Boolean(true);
        assert_eq!(val, GraphQLValue::Boolean(true));
    }

    #[test]
    fn test_null_variant() {
        let val = GraphQLValue::Null;
        assert_eq!(val, GraphQLValue::Null);
    }

    #[test]
    fn test_enum_variant() {
        let val = GraphQLValue::Enum("ACTIVE".to_string());
        assert_eq!(val, GraphQLValue::Enum("ACTIVE".to_string()));
    }

    #[test]
    fn test_list_variant() {
        let val = GraphQLValue::List(vec![
            GraphQLValue::Int(1),
            GraphQLValue::Int(2),
        ]);
        if let GraphQLValue::List(items) = &val {
            assert_eq!(items.len(), 2);
        } else {
            panic!("Expected List variant");
        }
    }

    #[test]
    fn test_object_variant_uses_indexmap() {
        let mut map = IndexMap::new();
        map.insert("key1".to_string(), GraphQLValue::String("val1".to_string()));
        map.insert("key2".to_string(), GraphQLValue::Int(42));
        let val = GraphQLValue::Object(map);

        if let GraphQLValue::Object(obj) = &val {
            assert_eq!(obj.len(), 2);
            // Verify insertion order is preserved (IndexMap guarantee)
            let keys: Vec<&String> = obj.keys().collect();
            assert_eq!(keys, vec!["key1", "key2"]);
        } else {
            panic!("Expected Object variant");
        }
    }

    #[test]
    fn test_all_9_variants_constructible() {
        let variants: Vec<GraphQLValue> = vec![
            GraphQLValue::Variable("v".to_string()),
            GraphQLValue::Int(1),
            GraphQLValue::Float(1.0),
            GraphQLValue::String("s".to_string()),
            GraphQLValue::Boolean(true),
            GraphQLValue::Null,
            GraphQLValue::Enum("E".to_string()),
            GraphQLValue::List(vec![]),
            GraphQLValue::Object(IndexMap::new()),
        ];
        assert_eq!(variants.len(), 9);
    }
}
