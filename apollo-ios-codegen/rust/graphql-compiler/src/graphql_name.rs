use std::fmt;
use std::hash::{Hash, Hasher};

use serde::Serialize;

/// A GraphQL name with schema-to-Swift name mapping.
/// Mirrors `GraphQLName` from `GraphQLName.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLName {
    pub schema_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub custom_name: Option<String>,
}

impl GraphQLName {
    pub fn new(schema_name: String) -> Self {
        Self {
            schema_name,
            custom_name: None,
        }
    }

    /// Returns the Swift-equivalent name for this GraphQL name.
    /// Maps `Boolean` -> `Bool` and `Float` -> `Double`.
    pub fn swift_name(&self) -> &str {
        match self.schema_name.as_str() {
            "Boolean" => "Bool",
            "Float" => "Double",
            _ => &self.schema_name,
        }
    }

    /// Returns documentation comment when a custom name is set.
    pub fn type_name_documentation(&self) -> Option<String> {
        match &self.custom_name {
            Some(custom) if !custom.is_empty() => {
                Some(format!(
                    "// Renamed from GraphQL schema value: '{}'",
                    self.schema_name
                ))
            }
            _ => None,
        }
    }
}

impl Hash for GraphQLName {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.schema_name.hash(state);
    }
}

impl PartialEq for GraphQLName {
    fn eq(&self, other: &Self) -> bool {
        self.schema_name == other.schema_name
    }
}

impl Eq for GraphQLName {}

impl fmt::Display for GraphQLName {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.schema_name)
    }
}

/// Trait for types that have a GraphQL name.
/// Mirrors `GraphQLNamedItem` from `GraphQLName.swift`.
pub trait GraphQLNamedItem {
    fn name(&self) -> &GraphQLName;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_stores_schema_name() {
        let name = GraphQLName::new("User".to_string());
        assert_eq!(name.schema_name, "User");
        assert!(name.custom_name.is_none());
    }

    #[test]
    fn test_swift_name_boolean_to_bool() {
        let name = GraphQLName::new("Boolean".to_string());
        assert_eq!(name.swift_name(), "Bool");
    }

    #[test]
    fn test_swift_name_float_to_double() {
        let name = GraphQLName::new("Float".to_string());
        assert_eq!(name.swift_name(), "Double");
    }

    #[test]
    fn test_swift_name_identity_for_others() {
        let name = GraphQLName::new("String".to_string());
        assert_eq!(name.swift_name(), "String");

        let name = GraphQLName::new("Int".to_string());
        assert_eq!(name.swift_name(), "Int");

        let name = GraphQLName::new("MyCustomType".to_string());
        assert_eq!(name.swift_name(), "MyCustomType");
    }

    #[test]
    fn test_custom_name_sets_and_type_name_documentation() {
        let mut name = GraphQLName::new("ACTIVE".to_string());
        name.custom_name = Some("active".to_string());
        assert_eq!(
            name.type_name_documentation(),
            Some("// Renamed from GraphQL schema value: 'ACTIVE'".to_string())
        );
    }

    #[test]
    fn test_type_name_documentation_none_without_custom_name() {
        let name = GraphQLName::new("User".to_string());
        assert!(name.type_name_documentation().is_none());
    }

    #[test]
    fn test_type_name_documentation_none_with_empty_custom_name() {
        let mut name = GraphQLName::new("User".to_string());
        name.custom_name = Some(String::new());
        assert!(name.type_name_documentation().is_none());
    }

    #[test]
    fn test_equality_based_on_schema_name_only() {
        let mut name1 = GraphQLName::new("User".to_string());
        name1.custom_name = Some("CustomUser".to_string());

        let name2 = GraphQLName::new("User".to_string());

        assert_eq!(name1, name2);
    }

    #[test]
    fn test_hash_based_on_schema_name_only() {
        use std::collections::hash_map::DefaultHasher;

        let mut name1 = GraphQLName::new("User".to_string());
        name1.custom_name = Some("CustomUser".to_string());

        let name2 = GraphQLName::new("User".to_string());

        let hash1 = {
            let mut h = DefaultHasher::new();
            name1.hash(&mut h);
            h.finish()
        };
        let hash2 = {
            let mut h = DefaultHasher::new();
            name2.hash(&mut h);
            h.finish()
        };

        assert_eq!(hash1, hash2);
    }
}
