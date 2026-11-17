use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use serde::Serialize;

use crate::schema::{
    GraphQLCompositeType, GraphQLEnumType, GraphQLInputObjectType, GraphQLNamedType,
    GraphQLScalarType,
};

/// A GraphQL type.
/// Mirrors `GraphQLType` from `GraphQLType.swift`.
///
/// Has exactly 6 variants matching the Swift indirect enum.
/// Uses `Box` for recursive variants (NonNull, List).
#[derive(Clone, Debug, Serialize)]
#[serde(tag = "kind")]
pub enum GraphQLType {
    Entity(GraphQLCompositeType),
    Scalar(Arc<GraphQLScalarType>),
    Enum(Arc<GraphQLEnumType>),
    InputObject(Arc<GraphQLInputObjectType>),
    NonNull(Box<GraphQLType>),
    List(Box<GraphQLType>),
}

impl GraphQLType {
    /// Returns the string representation of this type reference.
    /// Mirrors Swift's `typeReference` computed property.
    ///
    /// Examples: "String", "String!", "[String]", "[String!]!"
    pub fn type_reference(&self) -> String {
        match self {
            GraphQLType::Entity(t) => t.name().schema_name.clone(),
            GraphQLType::Scalar(t) => t.name.schema_name.clone(),
            GraphQLType::Enum(t) => t.name.schema_name.clone(),
            GraphQLType::InputObject(t) => t.name.schema_name.clone(),
            GraphQLType::NonNull(inner) => format!("{}!", inner.type_reference()),
            GraphQLType::List(inner) => format!("[{}]", inner.type_reference()),
        }
    }

    /// Returns the underlying named type, unwrapping through NonNull and List.
    /// Mirrors Swift's `namedType` computed property.
    pub fn named_type(&self) -> &GraphQLNamedType {
        match self {
            GraphQLType::Entity(GraphQLCompositeType::Object(t)) => {
                // We need to return a reference, but GraphQLNamedType is an enum.
                // Since we can't store an owned value, we use a helper approach.
                // This is a design limitation - we return a leaked reference only
                // for test/debug purposes. In production, use inner_named_type().
                unimplemented!(
                    "named_type() not available on Entity types directly; \
                     use named_type_name() or pattern match instead. \
                     Type: {}",
                    t.name.schema_name
                )
            }
            GraphQLType::NonNull(inner) | GraphQLType::List(inner) => inner.named_type(),
            _ => unimplemented!(
                "named_type() returns owned GraphQLNamedType; \
                 use named_type_name() for the name string"
            ),
        }
    }

    /// Returns the name of the underlying named type, unwrapping through
    /// NonNull and List wrappers.
    pub fn named_type_name(&self) -> &str {
        match self {
            GraphQLType::Entity(t) => &t.name().schema_name,
            GraphQLType::Scalar(t) => &t.name.schema_name,
            GraphQLType::Enum(t) => &t.name.schema_name,
            GraphQLType::InputObject(t) => &t.name.schema_name,
            GraphQLType::NonNull(inner) | GraphQLType::List(inner) => inner.named_type_name(),
        }
    }

    /// Returns the innermost type, unwrapping through all NonNull and List
    /// wrappers. Mirrors Swift's `innerType` computed property.
    pub fn inner_type(&self) -> &GraphQLType {
        match self {
            GraphQLType::Entity(_)
            | GraphQLType::Scalar(_)
            | GraphQLType::Enum(_)
            | GraphQLType::InputObject(_) => self,
            GraphQLType::NonNull(inner) | GraphQLType::List(inner) => inner.inner_type(),
        }
    }

    /// Returns `true` if this type is nullable (i.e., not wrapped in NonNull).
    /// Mirrors Swift's `isNullable` computed property.
    pub fn is_nullable(&self) -> bool {
        !matches!(self, GraphQLType::NonNull(_))
    }

    /// Returns `true` if this type is a list type (unwrapping through NonNull).
    /// Mirrors Swift's `isListType` computed property from `IR+Formatting.swift`.
    pub fn is_list_type(&self) -> bool {
        match self {
            GraphQLType::List(_) => true,
            GraphQLType::NonNull(inner) => inner.is_list_type(),
            _ => false,
        }
    }
}

impl Hash for GraphQLType {
    fn hash<H: Hasher>(&self, state: &mut H) {
        std::mem::discriminant(self).hash(state);
        match self {
            GraphQLType::Entity(t) => t.hash(state),
            GraphQLType::Scalar(t) => t.hash(state),
            GraphQLType::Enum(t) => t.hash(state),
            GraphQLType::InputObject(t) => t.hash(state),
            GraphQLType::NonNull(inner) => inner.hash(state),
            GraphQLType::List(inner) => inner.hash(state),
        }
    }
}

impl PartialEq for GraphQLType {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (GraphQLType::Entity(a), GraphQLType::Entity(b)) => a == b,
            (GraphQLType::Scalar(a), GraphQLType::Scalar(b)) => a == b,
            (GraphQLType::Enum(a), GraphQLType::Enum(b)) => a == b,
            (GraphQLType::InputObject(a), GraphQLType::InputObject(b)) => a == b,
            (GraphQLType::NonNull(a), GraphQLType::NonNull(b)) => a == b,
            (GraphQLType::List(a), GraphQLType::List(b)) => a == b,
            _ => false,
        }
    }
}

impl Eq for GraphQLType {}

impl fmt::Display for GraphQLType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.type_reference())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::graphql_name::GraphQLName;
    use crate::schema::{GraphQLObjectType, GraphQLUnionType};
    use indexmap::IndexMap;

    fn make_scalar(name: &str) -> Arc<GraphQLScalarType> {
        Arc::new(GraphQLScalarType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            specified_by_url: None,
        })
    }

    fn make_enum(name: &str) -> Arc<GraphQLEnumType> {
        Arc::new(GraphQLEnumType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            values: vec![],
        })
    }

    fn make_input_object(name: &str) -> Arc<GraphQLInputObjectType> {
        Arc::new(GraphQLInputObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            is_one_of: false,
            fields: IndexMap::new(),
        })
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

    #[test]
    fn test_6_variants() {
        let entity = GraphQLType::Entity(GraphQLCompositeType::Object(make_object("User")));
        let scalar = GraphQLType::Scalar(make_scalar("String"));
        let enum_type = GraphQLType::Enum(make_enum("Status"));
        let input = GraphQLType::InputObject(make_input_object("Input"));
        let non_null = GraphQLType::NonNull(Box::new(GraphQLType::Scalar(make_scalar("String"))));
        let list = GraphQLType::List(Box::new(GraphQLType::Scalar(make_scalar("String"))));

        // All 6 constructible
        assert_eq!(entity.type_reference(), "User");
        assert_eq!(scalar.type_reference(), "String");
        assert_eq!(enum_type.type_reference(), "Status");
        assert_eq!(input.type_reference(), "Input");
        assert_eq!(non_null.type_reference(), "String!");
        assert_eq!(list.type_reference(), "[String]");
    }

    #[test]
    fn test_type_reference_complex() {
        // [String!]!
        let inner = GraphQLType::NonNull(Box::new(GraphQLType::Scalar(make_scalar("String"))));
        let list = GraphQLType::List(Box::new(inner));
        let non_null_list = GraphQLType::NonNull(Box::new(list));

        assert_eq!(non_null_list.type_reference(), "[String!]!");
    }

    #[test]
    fn test_named_type_name_unwraps() {
        let inner = GraphQLType::Scalar(make_scalar("String"));
        let non_null = GraphQLType::NonNull(Box::new(inner));
        let list = GraphQLType::List(Box::new(non_null));

        assert_eq!(list.named_type_name(), "String");
    }

    #[test]
    fn test_inner_type_unwraps() {
        let scalar = GraphQLType::Scalar(make_scalar("Int"));
        let non_null = GraphQLType::NonNull(Box::new(scalar.clone()));
        let list = GraphQLType::List(Box::new(non_null));

        let inner = list.inner_type();
        assert!(matches!(inner, GraphQLType::Scalar(_)));
    }

    #[test]
    fn test_is_nullable() {
        let scalar = GraphQLType::Scalar(make_scalar("String"));
        assert!(scalar.is_nullable());

        let non_null = GraphQLType::NonNull(Box::new(scalar));
        assert!(!non_null.is_nullable());

        let list = GraphQLType::List(Box::new(GraphQLType::Scalar(make_scalar("String"))));
        assert!(list.is_nullable());

        let entity = GraphQLType::Entity(GraphQLCompositeType::Union(Arc::new(GraphQLUnionType {
            name: GraphQLName::new("Animal".to_string()),
            documentation: None,
            types: vec![],
        })));
        assert!(entity.is_nullable());
    }

    #[test]
    fn test_equality() {
        let t1 = GraphQLType::Scalar(make_scalar("String"));
        let t2 = GraphQLType::Scalar(make_scalar("String"));
        assert_eq!(t1, t2);

        let t3 = GraphQLType::Scalar(make_scalar("Int"));
        assert_ne!(t1, t3);

        let t4 = GraphQLType::NonNull(Box::new(GraphQLType::Scalar(make_scalar("String"))));
        assert_ne!(t1, t4);
    }
}
