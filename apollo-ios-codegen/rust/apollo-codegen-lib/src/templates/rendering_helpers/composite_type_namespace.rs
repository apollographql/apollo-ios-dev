//! Composite type namespace helpers for code generation.
//!
//! Mirrors Swift's `GraphQLCompositeType+SchemaTypeNamespace.swift` from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/GraphQLCompositeType+SchemaTypeNamespace.swift`.

use graphql_compiler::schema::GraphQLCompositeType;

/// Returns the schema types namespace string for a composite type.
///
/// Mirrors Swift's `GraphQLCompositeType.schemaTypesNamespace` property.
///
/// # Panics
///
/// This function should only be called with valid parent types for selection sets.
pub fn schema_types_namespace(composite_type: &GraphQLCompositeType) -> &'static str {
  match composite_type {
    GraphQLCompositeType::Object(_) => "Objects",
    GraphQLCompositeType::Interface(_) => "Interfaces",
    GraphQLCompositeType::Union(_) => "Unions",
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use graphql_compiler::graphql_name::GraphQLName;
  use graphql_compiler::schema::{
    GraphQLInterfaceType, GraphQLObjectType, GraphQLUnionType,
  };
  use indexmap::IndexMap;
  use std::sync::Arc;

  #[test]
  fn test_object_namespace() {
    let obj = GraphQLCompositeType::Object(Arc::new(GraphQLObjectType {
      name: GraphQLName::new("User".to_string()),
      documentation: None,
      fields: IndexMap::new(),
      interfaces: vec![],
      key_fields: None,
    }));
    assert_eq!(schema_types_namespace(&obj), "Objects");
  }

  #[test]
  fn test_interface_namespace() {
    let iface = GraphQLCompositeType::Interface(Arc::new(GraphQLInterfaceType {
      name: GraphQLName::new("Node".to_string()),
      documentation: None,
      fields: IndexMap::new(),
      interfaces: vec![],
      key_fields: None,
      implementing_objects: vec![],
    }));
    assert_eq!(schema_types_namespace(&iface), "Interfaces");
  }

  #[test]
  fn test_union_namespace() {
    let union = GraphQLCompositeType::Union(Arc::new(GraphQLUnionType {
      name: GraphQLName::new("Animal".to_string()),
      documentation: None,
      types: vec![],
    }));
    assert_eq!(schema_types_namespace(&union), "Unions");
  }
}
