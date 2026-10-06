use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use indexmap::IndexMap;
use serde::Serialize;

use crate::graphql_name::{GraphQLName, GraphQLNamedItem};
use crate::graphql_type::GraphQLType;
use crate::graphql_value::GraphQLValue;

// MARK: - GraphQLSchema

/// A GraphQL schema.
/// Mirrors `GraphQLSchema` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLSchema {
    pub query_type: Arc<GraphQLObjectType>,
    pub mutation_type: Option<Arc<GraphQLObjectType>>,
    pub subscription_type: Option<Arc<GraphQLObjectType>>,
    pub referenced_types: Vec<GraphQLNamedType>,
}

// MARK: - GraphQLNamedType

/// An enum representing any named GraphQL type.
/// Mirrors the `GraphQLNamedType` class hierarchy from `GraphQLSchema.swift`.
///
/// Uses `Arc` for shared ownership, matching Swift's reference type semantics
/// where a single type instance is referenced from multiple places (schema,
/// fields, union members, etc.).
#[derive(Clone, Debug, Serialize)]
#[serde(tag = "kind")]
pub enum GraphQLNamedType {
    Scalar(Arc<GraphQLScalarType>),
    Object(Arc<GraphQLObjectType>),
    Interface(Arc<GraphQLInterfaceType>),
    Union(Arc<GraphQLUnionType>),
    Enum(Arc<GraphQLEnumType>),
    InputObject(Arc<GraphQLInputObjectType>),
}

impl GraphQLNamedType {
    pub fn name(&self) -> &GraphQLName {
        match self {
            GraphQLNamedType::Scalar(t) => &t.name,
            GraphQLNamedType::Object(t) => &t.name,
            GraphQLNamedType::Interface(t) => &t.name,
            GraphQLNamedType::Union(t) => &t.name,
            GraphQLNamedType::Enum(t) => &t.name,
            GraphQLNamedType::InputObject(t) => &t.name,
        }
    }

    pub fn documentation(&self) -> Option<&str> {
        match self {
            GraphQLNamedType::Scalar(t) => t.documentation.as_deref(),
            GraphQLNamedType::Object(t) => t.documentation.as_deref(),
            GraphQLNamedType::Interface(t) => t.documentation.as_deref(),
            GraphQLNamedType::Union(t) => t.documentation.as_deref(),
            GraphQLNamedType::Enum(t) => t.documentation.as_deref(),
            GraphQLNamedType::InputObject(t) => t.documentation.as_deref(),
        }
    }
}

impl Hash for GraphQLNamedType {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name().hash(state);
    }
}

impl PartialEq for GraphQLNamedType {
    fn eq(&self, other: &Self) -> bool {
        self.name() == other.name()
    }
}

impl Eq for GraphQLNamedType {}

impl fmt::Display for GraphQLNamedType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.name().schema_name)
    }
}

// MARK: - GraphQLScalarType

/// A GraphQL scalar type.
/// Mirrors `GraphQLScalarType` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLScalarType {
    pub name: GraphQLName,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub specified_by_url: Option<String>,
}

impl GraphQLScalarType {
    /// Returns `true` if this is a custom scalar (not one of the built-in
    /// scalars: String, Int, Float, Boolean).
    /// A scalar with a `specified_by_url` is always considered custom.
    pub fn is_custom_scalar(&self) -> bool {
        if self.specified_by_url.is_some() {
            return true;
        }
        !matches!(
            self.name.schema_name.as_str(),
            "String" | "Int" | "Float" | "Boolean"
        )
    }
}

impl GraphQLNamedItem for GraphQLScalarType {
    fn name(&self) -> &GraphQLName {
        &self.name
    }
}

impl Hash for GraphQLScalarType {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
    }
}

impl PartialEq for GraphQLScalarType {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl Eq for GraphQLScalarType {}

// MARK: - GraphQLEnumType

/// A GraphQL enum type.
/// Mirrors `GraphQLEnumType` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLEnumType {
    pub name: GraphQLName,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation: Option<String>,
    pub values: Vec<GraphQLEnumValue>,
}

impl GraphQLNamedItem for GraphQLEnumType {
    fn name(&self) -> &GraphQLName {
        &self.name
    }
}

impl Hash for GraphQLEnumType {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
    }
}

impl PartialEq for GraphQLEnumType {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl Eq for GraphQLEnumType {}

// MARK: - GraphQLEnumValue

/// A value within a GraphQL enum type.
/// Mirrors `GraphQLEnumValue` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLEnumValue {
    pub name: GraphQLName,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deprecation_reason: Option<String>,
}

impl GraphQLEnumValue {
    /// Returns `true` if this enum value is deprecated.
    pub fn is_deprecated(&self) -> bool {
        self.deprecation_reason.is_some()
    }
}

impl GraphQLNamedItem for GraphQLEnumValue {
    fn name(&self) -> &GraphQLName {
        &self.name
    }
}

// MARK: - GraphQLInputObjectType

/// A GraphQL input object type.
/// Mirrors `GraphQLInputObjectType` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLInputObjectType {
    pub name: GraphQLName,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation: Option<String>,
    pub is_one_of: bool,
    pub fields: IndexMap<String, GraphQLInputField>,
}

impl GraphQLNamedItem for GraphQLInputObjectType {
    fn name(&self) -> &GraphQLName {
        &self.name
    }
}

impl Hash for GraphQLInputObjectType {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
    }
}

impl PartialEq for GraphQLInputObjectType {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl Eq for GraphQLInputObjectType {}

// MARK: - GraphQLInputField

/// A field on a GraphQL input object type.
/// Mirrors `GraphQLInputField` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLInputField {
    pub name: GraphQLName,
    #[serde(rename = "type")]
    pub type_: GraphQLType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deprecation_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub default_value: Option<GraphQLValue>,
}

impl GraphQLNamedItem for GraphQLInputField {
    fn name(&self) -> &GraphQLName {
        &self.name
    }
}

// MARK: - GraphQLCompositeType

/// A composite GraphQL type (object, interface, or union).
/// Mirrors `GraphQLCompositeType` from `GraphQLSchema.swift`.
///
/// In Swift, this is a class hierarchy. In Rust, we use an enum
/// with Arc-wrapped variants for shared ownership.
#[derive(Clone, Debug, Serialize)]
#[serde(tag = "kind")]
pub enum GraphQLCompositeType {
    Object(Arc<GraphQLObjectType>),
    Interface(Arc<GraphQLInterfaceType>),
    Union(Arc<GraphQLUnionType>),
}

impl GraphQLCompositeType {
    pub fn name(&self) -> &GraphQLName {
        match self {
            GraphQLCompositeType::Object(t) => &t.name,
            GraphQLCompositeType::Interface(t) => &t.name,
            GraphQLCompositeType::Union(t) => &t.name,
        }
    }
}

impl Hash for GraphQLCompositeType {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name().hash(state);
    }
}

impl PartialEq for GraphQLCompositeType {
    fn eq(&self, other: &Self) -> bool {
        self.name() == other.name()
    }
}

impl Eq for GraphQLCompositeType {}

impl fmt::Display for GraphQLCompositeType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            GraphQLCompositeType::Object(_) => write!(f, "Object - {}", self.name()),
            GraphQLCompositeType::Interface(_) => write!(f, "Interface - {}", self.name()),
            GraphQLCompositeType::Union(_) => write!(f, "Union - {}", self.name()),
        }
    }
}

// MARK: - GraphQLAbstractType

/// An abstract GraphQL type (interface or union).
/// Mirrors `GraphQLAbstractType` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
#[serde(tag = "kind")]
pub enum GraphQLAbstractType {
    Interface(Arc<GraphQLInterfaceType>),
    Union(Arc<GraphQLUnionType>),
}

impl GraphQLAbstractType {
    pub fn name(&self) -> &GraphQLName {
        match self {
            GraphQLAbstractType::Interface(t) => &t.name,
            GraphQLAbstractType::Union(t) => &t.name,
        }
    }
}

impl Hash for GraphQLAbstractType {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name().hash(state);
    }
}

impl PartialEq for GraphQLAbstractType {
    fn eq(&self, other: &Self) -> bool {
        self.name() == other.name()
    }
}

impl Eq for GraphQLAbstractType {}

// MARK: - GraphQLObjectType

/// A GraphQL object type.
/// Mirrors `GraphQLObjectType` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLObjectType {
    pub name: GraphQLName,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation: Option<String>,
    pub fields: IndexMap<String, GraphQLField>,
    pub interfaces: Vec<Arc<GraphQLInterfaceType>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_fields: Option<Vec<String>>,
}

impl GraphQLObjectType {
    /// Returns `true` if this object type implements the given interface.
    pub fn implements_interface(&self, interface: &GraphQLInterfaceType) -> bool {
        self.interfaces.iter().any(|i| i.name == interface.name)
    }
}

impl GraphQLNamedItem for GraphQLObjectType {
    fn name(&self) -> &GraphQLName {
        &self.name
    }
}

impl Hash for GraphQLObjectType {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
    }
}

impl PartialEq for GraphQLObjectType {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl Eq for GraphQLObjectType {}

impl fmt::Display for GraphQLObjectType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Object - {}", self.name)
    }
}

// MARK: - GraphQLInterfaceType

/// A GraphQL interface type.
/// Mirrors `GraphQLInterfaceType` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLInterfaceType {
    pub name: GraphQLName,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation: Option<String>,
    pub fields: IndexMap<String, GraphQLField>,
    pub interfaces: Vec<Arc<GraphQLInterfaceType>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_fields: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub implementing_objects: Vec<Arc<GraphQLObjectType>>,
}

impl GraphQLInterfaceType {
    /// Returns `true` if this interface type implements the given interface.
    pub fn implements_interface(&self, interface: &GraphQLInterfaceType) -> bool {
        self.interfaces.iter().any(|i| i.name == interface.name)
    }
}

impl GraphQLNamedItem for GraphQLInterfaceType {
    fn name(&self) -> &GraphQLName {
        &self.name
    }
}

impl Hash for GraphQLInterfaceType {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
    }
}

impl PartialEq for GraphQLInterfaceType {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl Eq for GraphQLInterfaceType {}

impl fmt::Display for GraphQLInterfaceType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Interface - {}", self.name)
    }
}

// MARK: - GraphQLUnionType

/// A GraphQL union type.
/// Mirrors `GraphQLUnionType` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLUnionType {
    pub name: GraphQLName,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation: Option<String>,
    pub types: Vec<Arc<GraphQLObjectType>>,
}

impl GraphQLNamedItem for GraphQLUnionType {
    fn name(&self) -> &GraphQLName {
        &self.name
    }
}

impl Hash for GraphQLUnionType {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
    }
}

impl PartialEq for GraphQLUnionType {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl Eq for GraphQLUnionType {}

impl fmt::Display for GraphQLUnionType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Union - {}", self.name)
    }
}

// MARK: - GraphQLField

/// A field on a GraphQL object or interface type.
/// Mirrors `GraphQLField` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLField {
    pub name: String,
    #[serde(rename = "type")]
    pub type_: GraphQLType,
    pub arguments: Vec<GraphQLFieldArgument>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deprecation_reason: Option<String>,
}

impl Hash for GraphQLField {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
        self.type_.hash(state);
        self.arguments.hash(state);
    }
}

impl PartialEq for GraphQLField {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
            && self.type_ == other.type_
            && self.arguments == other.arguments
    }
}

impl Eq for GraphQLField {}

impl fmt::Display for GraphQLField {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.name, self.type_.type_reference())
    }
}

// MARK: - GraphQLFieldArgument

/// An argument on a GraphQL field.
/// Mirrors `GraphQLFieldArgument` from `GraphQLSchema.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct GraphQLFieldArgument {
    pub name: String,
    #[serde(rename = "type")]
    pub type_: GraphQLType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deprecation_reason: Option<String>,
}

impl Hash for GraphQLFieldArgument {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
        self.type_.hash(state);
    }
}

impl PartialEq for GraphQLFieldArgument {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name && self.type_ == other.type_
    }
}

impl Eq for GraphQLFieldArgument {}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_scalar(name: &str) -> Arc<GraphQLScalarType> {
        Arc::new(GraphQLScalarType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            specified_by_url: None,
        })
    }

    fn make_string_type() -> GraphQLType {
        GraphQLType::Scalar(make_scalar("String"))
    }

    #[test]
    fn test_scalar_is_custom_scalar_false_for_builtins() {
        for name in &["String", "Int", "Float", "Boolean"] {
            let scalar = GraphQLScalarType {
                name: GraphQLName::new(name.to_string()),
                documentation: None,
                specified_by_url: None,
            };
            assert!(
                !scalar.is_custom_scalar(),
                "{} should not be a custom scalar",
                name
            );
        }
    }

    #[test]
    fn test_scalar_is_custom_scalar_true_for_others() {
        let scalar = GraphQLScalarType {
            name: GraphQLName::new("DateTime".to_string()),
            documentation: None,
            specified_by_url: None,
        };
        assert!(scalar.is_custom_scalar());
    }

    #[test]
    fn test_scalar_is_custom_scalar_true_when_specified_by_url_set() {
        let scalar = GraphQLScalarType {
            name: GraphQLName::new("String".to_string()),
            documentation: None,
            specified_by_url: Some("https://example.com".to_string()),
        };
        assert!(scalar.is_custom_scalar());
    }

    #[test]
    fn test_enum_value_is_deprecated() {
        let value = GraphQLEnumValue {
            name: GraphQLName::new("OLD_VALUE".to_string()),
            documentation: None,
            deprecation_reason: Some("Use NEW_VALUE instead".to_string()),
        };
        assert!(value.is_deprecated());

        let active = GraphQLEnumValue {
            name: GraphQLName::new("ACTIVE".to_string()),
            documentation: None,
            deprecation_reason: None,
        };
        assert!(!active.is_deprecated());
    }

    #[test]
    fn test_object_type_stores_fields_and_interfaces() {
        let mut fields = IndexMap::new();
        fields.insert(
            "id".to_string(),
            GraphQLField {
                name: "id".to_string(),
                type_: make_string_type(),
                arguments: vec![],
                documentation: None,
                deprecation_reason: None,
            },
        );

        let obj = GraphQLObjectType {
            name: GraphQLName::new("User".to_string()),
            documentation: None,
            fields,
            interfaces: vec![],
            key_fields: None,
        };
        assert_eq!(obj.fields.len(), 1);
        assert!(obj.fields.contains_key("id"));
        assert!(obj.interfaces.is_empty());
    }

    #[test]
    fn test_interface_type_stores_fields_and_interfaces() {
        let mut fields = IndexMap::new();
        fields.insert(
            "id".to_string(),
            GraphQLField {
                name: "id".to_string(),
                type_: make_string_type(),
                arguments: vec![],
                documentation: None,
                deprecation_reason: None,
            },
        );

        let iface = GraphQLInterfaceType {
            name: GraphQLName::new("Node".to_string()),
            documentation: None,
            fields,
            interfaces: vec![],
            key_fields: None,
            implementing_objects: vec![],
        };
        assert_eq!(iface.fields.len(), 1);
        assert!(iface.fields.contains_key("id"));
        assert!(iface.interfaces.is_empty());
    }

    #[test]
    fn test_union_type_stores_member_types() {
        let cat = Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Cat".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        });
        let dog = Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Dog".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        });

        let union = GraphQLUnionType {
            name: GraphQLName::new("Animal".to_string()),
            documentation: None,
            types: vec![Arc::clone(&cat), Arc::clone(&dog)],
        };
        assert_eq!(union.types.len(), 2);
        assert_eq!(union.types[0].name.schema_name, "Cat");
        assert_eq!(union.types[1].name.schema_name, "Dog");
    }

    #[test]
    fn test_named_type_enum_has_6_variants() {
        let scalar = GraphQLNamedType::Scalar(make_scalar("String"));
        let object = GraphQLNamedType::Object(Arc::new(GraphQLObjectType {
            name: GraphQLName::new("User".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        }));
        let interface = GraphQLNamedType::Interface(Arc::new(GraphQLInterfaceType {
            name: GraphQLName::new("Node".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
            implementing_objects: vec![],
        }));
        let union = GraphQLNamedType::Union(Arc::new(GraphQLUnionType {
            name: GraphQLName::new("Animal".to_string()),
            documentation: None,
            types: vec![],
        }));
        let enum_type = GraphQLNamedType::Enum(Arc::new(GraphQLEnumType {
            name: GraphQLName::new("Status".to_string()),
            documentation: None,
            values: vec![],
        }));
        let input = GraphQLNamedType::InputObject(Arc::new(GraphQLInputObjectType {
            name: GraphQLName::new("Input".to_string()),
            documentation: None,
            is_one_of: false,
            fields: IndexMap::new(),
        }));

        // All 6 variants created successfully
        assert_eq!(scalar.name().schema_name, "String");
        assert_eq!(object.name().schema_name, "User");
        assert_eq!(interface.name().schema_name, "Node");
        assert_eq!(union.name().schema_name, "Animal");
        assert_eq!(enum_type.name().schema_name, "Status");
        assert_eq!(input.name().schema_name, "Input");
    }

    #[test]
    fn test_input_field_stores_all_fields() {
        let field = GraphQLInputField {
            name: GraphQLName::new("email".to_string()),
            type_: make_string_type(),
            documentation: Some("The user's email".to_string()),
            deprecation_reason: Some("Use emailAddress instead".to_string()),
            default_value: Some(GraphQLValue::String("default@example.com".to_string())),
        };
        assert_eq!(field.name.schema_name, "email");
        assert!(field.documentation.is_some());
        assert!(field.deprecation_reason.is_some());
        assert!(field.default_value.is_some());
    }

    #[test]
    fn test_named_type_equality_by_name() {
        let s1 = GraphQLNamedType::Scalar(make_scalar("String"));
        let s2 = GraphQLNamedType::Scalar(make_scalar("String"));
        assert_eq!(s1, s2);

        let s3 = GraphQLNamedType::Scalar(make_scalar("Int"));
        assert_ne!(s1, s3);
    }

    #[test]
    fn test_composite_type_equality_by_name() {
        let obj1 = Graph::new_object("User");
        let obj2 = Arc::new(GraphQLObjectType {
            name: GraphQLName::new("User".to_string()),
            documentation: Some("Different docs".to_string()),
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        });

        let c1 = GraphQLCompositeType::Object(obj1);
        let c2 = GraphQLCompositeType::Object(obj2);
        assert_eq!(c1, c2);
    }

    // Helper module for creating test types
    struct Graph;
    impl Graph {
        fn new_object(name: &str) -> Arc<GraphQLObjectType> {
            Arc::new(GraphQLObjectType {
                name: GraphQLName::new(name.to_string()),
                documentation: None,
                fields: IndexMap::new(),
                interfaces: vec![],
                key_fields: None,
            })
        }
    }
}
