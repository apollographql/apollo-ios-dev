//! GraphQL input field rendering helpers for code generation.
//!
//! Mirrors Swift's `GraphQLInputField+Rendered.swift` from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/GraphQLInputField+Rendered.swift`.

use graphql_compiler::graphql_type::GraphQLType;
use graphql_compiler::schema::GraphQLInputField;

use crate::config::ApolloCodegenConfiguration;
use super::graphql_type_rendered::{rendered, TypeRenderContext};

/// Renders the Swift type string for an input field's type.
///
/// Mirrors Swift's `GraphQLInputField.renderInputValueType(includeDefault:config:)`.
pub fn render_input_value_type(
  field: &GraphQLInputField,
  include_default: bool,
  config: &ApolloCodegenConfiguration,
) -> String {
  let type_string = rendered(
    &field.type_,
    &TypeRenderContext::InputValue,
    None,
    config,
  );

  let optional_suffix = if is_swift_optional(field) { "?" } else { "" };
  let default_suffix = if include_default && has_swift_nil_default(field) {
    " = nil"
  } else {
    ""
  };

  format!("{}{}{}", type_string, optional_suffix, default_suffix)
}

/// Returns `true` if this input field should be a Swift Optional (not nullable, but has a default).
///
/// Mirrors Swift's `GraphQLInputField.isSwiftOptional` property.
fn is_swift_optional(field: &GraphQLInputField) -> bool {
  !is_nullable(field) && has_default_value(field)
}

/// Returns `true` if the field should have a `nil` default in Swift.
///
/// Mirrors Swift's `GraphQLInputField.hasSwiftNilDefault` property.
fn has_swift_nil_default(field: &GraphQLInputField) -> bool {
  is_nullable(field) || has_default_value(field)
}

/// Returns `true` if the field type is nullable (not wrapped in NonNull).
///
/// Mirrors Swift's `GraphQLInputField.isNullable` property.
pub fn is_nullable(field: &GraphQLInputField) -> bool {
  !matches!(field.type_, GraphQLType::NonNull(_))
}

/// Returns `true` if the field has a default value.
///
/// Mirrors Swift's `GraphQLInputField.hasDefaultValue` property.
pub fn has_default_value(field: &GraphQLInputField) -> bool {
  field.default_value.is_some()
}

#[cfg(test)]
mod tests {
  use super::*;
  use graphql_compiler::graphql_name::GraphQLName;
  use graphql_compiler::graphql_value::GraphQLValue;
  use graphql_compiler::schema::GraphQLScalarType;
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

  fn make_string_type() -> GraphQLType {
    GraphQLType::Scalar(Arc::new(GraphQLScalarType {
      name: GraphQLName::new("String".to_string()),
      documentation: None,
      specified_by_url: None,
    }))
  }

  #[test]
  fn test_render_nullable_string_field() {
    let config = default_config();
    let field = GraphQLInputField {
      name: GraphQLName::new("name".to_string()),
      type_: make_string_type(),
      documentation: None,
      deprecation_reason: None,
      default_value: None,
    };
    let result = render_input_value_type(&field, false, &config);
    assert_eq!(result, "GraphQLNullable<String>");
  }

  #[test]
  fn test_render_non_null_string_field() {
    let config = default_config();
    let field = GraphQLInputField {
      name: GraphQLName::new("name".to_string()),
      type_: GraphQLType::NonNull(Box::new(make_string_type())),
      documentation: None,
      deprecation_reason: None,
      default_value: None,
    };
    let result = render_input_value_type(&field, false, &config);
    assert_eq!(result, "String");
  }

  #[test]
  fn test_render_non_null_with_default_adds_optional() {
    let config = default_config();
    let field = GraphQLInputField {
      name: GraphQLName::new("name".to_string()),
      type_: GraphQLType::NonNull(Box::new(make_string_type())),
      documentation: None,
      deprecation_reason: None,
      default_value: Some(GraphQLValue::String("default".to_string())),
    };
    let result = render_input_value_type(&field, false, &config);
    // NonNull + default => optional suffix
    assert_eq!(result, "String?");
  }

  #[test]
  fn test_render_with_include_default_nil() {
    let config = default_config();
    let field = GraphQLInputField {
      name: GraphQLName::new("name".to_string()),
      type_: make_string_type(), // nullable
      documentation: None,
      deprecation_reason: None,
      default_value: None,
    };
    let result = render_input_value_type(&field, true, &config);
    // Nullable => has nil default
    assert_eq!(result, "GraphQLNullable<String> = nil");
  }

  #[test]
  fn test_is_nullable() {
    let nullable_field = GraphQLInputField {
      name: GraphQLName::new("f".to_string()),
      type_: make_string_type(),
      documentation: None,
      deprecation_reason: None,
      default_value: None,
    };
    assert!(is_nullable(&nullable_field));

    let non_null_field = GraphQLInputField {
      name: GraphQLName::new("f".to_string()),
      type_: GraphQLType::NonNull(Box::new(make_string_type())),
      documentation: None,
      deprecation_reason: None,
      default_value: None,
    };
    assert!(!is_nullable(&non_null_field));
  }
}
