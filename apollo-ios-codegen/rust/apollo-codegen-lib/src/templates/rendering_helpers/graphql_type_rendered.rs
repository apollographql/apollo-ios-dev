//! GraphQL type rendering helpers for code generation.
//!
//! Mirrors Swift's `GraphQLType+Rendered.swift` from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/GraphQLType+Rendered.swift`.

use graphql_compiler::graphql_type::GraphQLType;
use graphql_compiler::schema::{
  GraphQLCompositeType, GraphQLNamedType,
};

use crate::config::ApolloCodegenConfiguration;
use super::graphql_name_rendering::{is_swift_type, render_named_type, RenderContext};
use super::string_casing::first_uppercased;
use crate::config::swift_keywords::{is_in, SwiftKeywords};

/// The context in which a GraphQL type is being rendered.
///
/// Mirrors Swift's `GraphQLType.RenderContext` enum.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TypeRenderContext {
  /// Renders the type for use in an operation selection set.
  SelectionSetField { force_non_null: bool },
  /// Renders the type for use in a test mock object.
  TestMockField { force_non_null: bool },
  /// Renders the type for use as an input value.
  /// If the outermost type is nullable, it will be wrapped in `GraphQLNullable`
  /// instead of an `Optional`.
  InputValue,
}

/// Renders a `GraphQLType` as a Swift type string for the given context.
///
/// Mirrors Swift's `GraphQLType.rendered(as:replacingNamedTypeWith:config:)` method.
pub fn rendered(
  graphql_type: &GraphQLType,
  context: &TypeRenderContext,
  replacing_name: Option<&str>,
  config: &ApolloCodegenConfiguration,
) -> String {
  match context {
    TypeRenderContext::SelectionSetField { force_non_null } => {
      rendered_as_selection_set_field(graphql_type, *force_non_null, replacing_name, config)
    }
    TypeRenderContext::TestMockField { force_non_null } => {
      rendered_as_test_mock_field(graphql_type, *force_non_null, replacing_name, config)
    }
    TypeRenderContext::InputValue => {
      render_as_input_value(graphql_type, true, config)
    }
  }
}

// MARK: Selection Set Field

fn rendered_as_selection_set_field(
  graphql_type: &GraphQLType,
  contained_in_non_null: bool,
  replacing_name: Option<&str>,
  config: &ApolloCodegenConfiguration,
) -> String {
  render_type(
    graphql_type,
    &TypeRenderContext::SelectionSetField { force_non_null: false },
    contained_in_non_null,
    replacing_name,
    config,
  )
}

// MARK: Mock Object Field

fn rendered_as_test_mock_field(
  graphql_type: &GraphQLType,
  contained_in_non_null: bool,
  replacing_name: Option<&str>,
  config: &ApolloCodegenConfiguration,
) -> String {
  render_type(
    graphql_type,
    &TypeRenderContext::TestMockField { force_non_null: false },
    contained_in_non_null,
    replacing_name,
    config,
  )
}

// MARK: Input Value

/// Renders a type as an input value, wrapping nullable types in `GraphQLNullable`.
///
/// Mirrors Swift's `GraphQLType.renderAsInputValue(inNullable:config:)`.
pub fn render_as_input_value(
  graphql_type: &GraphQLType,
  in_nullable: bool,
  config: &ApolloCodegenConfiguration,
) -> String {
  match graphql_type {
    GraphQLType::NonNull(of_type) => {
      render_as_input_value(of_type, false, config)
    }
    GraphQLType::List(of_type) => {
      let type_name = format!(
        "[{}]",
        render_type(of_type, &TypeRenderContext::InputValue, false, None, config)
      );
      if in_nullable {
        format!("GraphQLNullable<{}>", type_name)
      } else {
        type_name
      }
    }
    _ => {
      let type_name = render_type(
        graphql_type,
        &TypeRenderContext::InputValue,
        true,
        None,
        config,
      );
      if in_nullable {
        format!("GraphQLNullable<{}>", type_name)
      } else {
        type_name
      }
    }
  }
}

// MARK: - Render Type

fn render_type(
  graphql_type: &GraphQLType,
  context: &TypeRenderContext,
  contained_in_non_null: bool,
  replacing_name: Option<&str>,
  config: &ApolloCodegenConfiguration,
) -> String {
  match graphql_type {
    GraphQLType::Entity(composite_type) => {
      let named_type = named_type_from_composite(composite_type);
      let type_name = qualified_root_type_name(
        &named_type, context, replacing_name, config,
      );
      let type_name = wrapped_in_graphql_enum(&type_name, graphql_type);
      if contained_in_non_null {
        type_name
      } else {
        format!("{}?", type_name)
      }
    }
    GraphQLType::Scalar(scalar) => {
      let named_type = GraphQLNamedType::Scalar(scalar.clone());
      let type_name = qualified_root_type_name(
        &named_type, context, replacing_name, config,
      );
      let type_name = wrapped_in_graphql_enum(&type_name, graphql_type);
      if contained_in_non_null {
        type_name
      } else {
        format!("{}?", type_name)
      }
    }
    GraphQLType::Enum(enum_type) => {
      let named_type = GraphQLNamedType::Enum(enum_type.clone());
      let type_name = qualified_root_type_name(
        &named_type, context, replacing_name, config,
      );
      let type_name = wrapped_in_graphql_enum(&type_name, graphql_type);
      if contained_in_non_null {
        type_name
      } else {
        format!("{}?", type_name)
      }
    }
    GraphQLType::InputObject(input_obj) => {
      let named_type = GraphQLNamedType::InputObject(input_obj.clone());
      let type_name = qualified_root_type_name(
        &named_type, context, replacing_name, config,
      );
      let type_name = wrapped_in_graphql_enum(&type_name, graphql_type);
      if contained_in_non_null {
        type_name
      } else {
        format!("{}?", type_name)
      }
    }
    GraphQLType::NonNull(of_type) => {
      render_type(of_type, context, true, replacing_name, config)
    }
    GraphQLType::List(of_type) => {
      let rendered = render_type(of_type, context, false, replacing_name, config);
      let inner = format!("[{}]", rendered);
      if contained_in_non_null {
        inner
      } else {
        format!("{}?", inner)
      }
    }
  }
}

/// Returns the test mock field type name for a named type.
///
/// Mirrors Swift's `GraphQLNamedType.testMockFieldTypeName(_:)`.
pub fn test_mock_field_type_name(
  named_type: &GraphQLNamedType,
  _config: &ApolloCodegenConfiguration,
) -> String {
  let typename = render_named_type(named_type, &RenderContext::Typename { is_input_value: false });

  if is_in(SwiftKeywords::TEST_MOCK_FIELD_ABSTRACT_TYPE_NAMES_TO_NAMESPACE, &typename) {
    match named_type {
      GraphQLNamedType::Interface(_) | GraphQLNamedType::Union(_) => {
        return format!("MockObject.{}", typename);
      }
      _ => {}
    }
  }

  typename
}

/// Computes the fully-qualified root type name for a named type.
///
/// Mirrors Swift's `GraphQLNamedType.qualifiedRootTypeName(in:replacingNamedTypeWith:config:)`.
fn qualified_root_type_name(
  named_type: &GraphQLNamedType,
  context: &TypeRenderContext,
  replacing_name: Option<&str>,
  config: &ApolloCodegenConfiguration,
) -> String {
  let type_name: String = if let TypeRenderContext::TestMockField { .. } = context {
    replacing_name
      .map(|s| s.to_string())
      .unwrap_or_else(|| test_mock_field_type_name(named_type, config))
  } else {
    let is_input = matches!(context, TypeRenderContext::InputValue);
    replacing_name
      .map(|s| s.to_string())
      .unwrap_or_else(|| {
        render_named_type(named_type, &RenderContext::Typename { is_input_value: is_input })
      })
  };

  let schema_module_name: String = match named_type {
    GraphQLNamedType::Object(_)
    | GraphQLNamedType::Interface(_)
    | GraphQLNamedType::Union(_) => {
      // Composite types have no schema module prefix
      String::new()
    }
    GraphQLNamedType::Scalar(scalar) if is_swift_type(scalar) => {
      // Built-in Swift types have no prefix
      String::new()
    }
    _ => {
      match context {
        TypeRenderContext::InputValue => {
          if !config.output.operations.is_in_module() {
            format!("{}.", first_uppercased(&config.schema_namespace))
          } else {
            String::new()
          }
        }
        TypeRenderContext::SelectionSetField { .. }
        | TypeRenderContext::TestMockField { .. } => {
          format!("{}.", first_uppercased(&config.schema_namespace))
        }
      }
    }
  };

  format!("{}{}", schema_module_name, type_name)
}

/// Wraps the type name in `GraphQLEnum<...>` if the type is an enum.
///
/// Mirrors Swift's `String.wrappedInGraphQLEnum(ifIsEnumType:)`.
fn wrapped_in_graphql_enum(type_name: &str, graphql_type: &GraphQLType) -> String {
  if matches!(graphql_type, GraphQLType::Enum(_)) {
    format!("GraphQLEnum<{}>", type_name)
  } else {
    type_name.to_string()
  }
}

/// Converts a `GraphQLCompositeType` to a `GraphQLNamedType`.
fn named_type_from_composite(composite: &GraphQLCompositeType) -> GraphQLNamedType {
  match composite {
    GraphQLCompositeType::Object(obj) => GraphQLNamedType::Object(obj.clone()),
    GraphQLCompositeType::Interface(iface) => GraphQLNamedType::Interface(iface.clone()),
    GraphQLCompositeType::Union(union) => GraphQLNamedType::Union(union.clone()),
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use graphql_compiler::graphql_name::GraphQLName;
  use graphql_compiler::schema::{GraphQLEnumType, GraphQLObjectType, GraphQLScalarType};
  use indexmap::IndexMap;
  use std::sync::Arc;

  fn default_config() -> ApolloCodegenConfiguration {
    serde_json::from_str(r#"{
      "schemaNamespace": "TestSchema",
      "input": {},
      "output": {
        "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"none": {}}
      }
    }"#).unwrap()
  }

  fn make_scalar(name: &str) -> GraphQLType {
    GraphQLType::Scalar(Arc::new(GraphQLScalarType {
      name: GraphQLName::new(name.to_string()),
      documentation: None,
      specified_by_url: None,
    }))
  }

  fn make_enum(name: &str) -> GraphQLType {
    GraphQLType::Enum(Arc::new(GraphQLEnumType {
      name: GraphQLName::new(name.to_string()),
      documentation: None,
      values: vec![],
    }))
  }

  fn make_entity_object(name: &str) -> GraphQLType {
    use graphql_compiler::schema::GraphQLObjectType;
    GraphQLType::Entity(GraphQLCompositeType::Object(Arc::new(GraphQLObjectType {
      name: GraphQLName::new(name.to_string()),
      documentation: None,
      fields: IndexMap::new(),
      interfaces: vec![],
      key_fields: None,
    })))
  }

  #[test]
  fn test_rendered_scalar_string_non_null() {
    let config = default_config();
    let t = GraphQLType::NonNull(Box::new(make_scalar("String")));
    let result = rendered(&t, &TypeRenderContext::SelectionSetField { force_non_null: false }, None, &config);
    assert_eq!(result, "String");
  }

  #[test]
  fn test_rendered_scalar_string_nullable() {
    let config = default_config();
    let t = make_scalar("String");
    let result = rendered(&t, &TypeRenderContext::SelectionSetField { force_non_null: false }, None, &config);
    assert_eq!(result, "String?");
  }

  #[test]
  fn test_rendered_list_of_strings() {
    let config = default_config();
    let t = GraphQLType::List(Box::new(make_scalar("String")));
    let result = rendered(&t, &TypeRenderContext::SelectionSetField { force_non_null: false }, None, &config);
    assert_eq!(result, "[String?]?");
  }

  #[test]
  fn test_rendered_non_null_list_of_non_null_strings() {
    let config = default_config();
    let inner = GraphQLType::NonNull(Box::new(make_scalar("String")));
    let list = GraphQLType::List(Box::new(inner));
    let t = GraphQLType::NonNull(Box::new(list));
    let result = rendered(&t, &TypeRenderContext::SelectionSetField { force_non_null: false }, None, &config);
    assert_eq!(result, "[String]");
  }

  #[test]
  fn test_rendered_enum_wrapped() {
    let config = default_config();
    let t = GraphQLType::NonNull(Box::new(make_enum("Status")));
    let result = rendered(&t, &TypeRenderContext::SelectionSetField { force_non_null: false }, None, &config);
    assert_eq!(result, "GraphQLEnum<TestSchema.Status>");
  }

  #[test]
  fn test_rendered_as_input_value_nullable() {
    let config = default_config();
    let t = make_scalar("String");
    let result = rendered(&t, &TypeRenderContext::InputValue, None, &config);
    assert_eq!(result, "GraphQLNullable<String>");
  }

  #[test]
  fn test_rendered_as_input_value_non_null() {
    let config = default_config();
    let t = GraphQLType::NonNull(Box::new(make_scalar("String")));
    let result = rendered(&t, &TypeRenderContext::InputValue, None, &config);
    assert_eq!(result, "String");
  }

  #[test]
  fn test_rendered_entity_has_no_schema_prefix() {
    let config = default_config();
    let t = GraphQLType::NonNull(Box::new(make_entity_object("User")));
    let result = rendered(&t, &TypeRenderContext::SelectionSetField { force_non_null: false }, None, &config);
    // Composite types should not have schema prefix
    assert_eq!(result, "User");
  }

  #[test]
  fn test_rendered_custom_scalar_has_schema_prefix() {
    let config = default_config();
    let t = GraphQLType::NonNull(Box::new(GraphQLType::Scalar(Arc::new(GraphQLScalarType {
      name: GraphQLName::new("DateTime".to_string()),
      documentation: None,
      specified_by_url: None,
    }))));
    let result = rendered(&t, &TypeRenderContext::SelectionSetField { force_non_null: false }, None, &config);
    assert_eq!(result, "TestSchema.DateTime");
  }
}
