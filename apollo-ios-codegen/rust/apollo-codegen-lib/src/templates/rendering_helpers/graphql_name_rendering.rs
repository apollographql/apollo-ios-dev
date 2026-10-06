//! GraphQL name rendering helpers for code generation.
//!
//! Mirrors Swift's `GraphQLName+RenderingHelper.swift` from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/GraphQLName+RenderingHelper.swift`.

use graphql_compiler::schema::{
  GraphQLEnumValue, GraphQLInputField, GraphQLNamedType, GraphQLScalarType,
};

use crate::config::conversion_strategies::{EnumCases, InputObjects};
use crate::config::swift_keywords::{is_in, SwiftKeywords};
use crate::templates::ConfigurationContext;
use super::string_casing::first_uppercased;
use super::string_swift_name_escaping::{as_enum_case_name, convert_to_camel_case, escape_if};

/// The context in which a GraphQL named type is being rendered.
///
/// Mirrors Swift's `GraphQLNamedType.RenderContext` enum.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RenderContext {
  /// Rendering for a filename.
  Filename,
  /// Rendering for a type name, with optional input value context.
  Typename { is_input_value: bool },
}

/// Renders a `GraphQLNamedType` as a string for the given context.
///
/// Mirrors Swift's `GraphQLNamedType.render(as:)` method.
pub fn render_named_type(named_type: &GraphQLNamedType, context: &RenderContext) -> String {
  // If the name has been customized, return it unchanged
  if let Some(custom_name) = &named_type.name().custom_name {
    return custom_name.clone();
  }

  match context {
    RenderContext::Filename => named_type.name().schema_name.clone(),
    RenderContext::Typename { is_input_value } => {
      render_type_name(named_type, *is_input_value)
    }
  }
}

/// Renders the type name for a named type.
///
/// Mirrors Swift's `GraphQLNamedType.renderTypeName(isInputValue:)`.
fn render_type_name(named_type: &GraphQLNamedType, is_input_value: bool) -> String {
  let swift_name = swift_name_for_type(named_type, is_input_value);

  match named_type {
    GraphQLNamedType::Scalar(scalar) => {
      if !scalar.is_custom_scalar() || scalar.name.schema_name == "ID" {
        return swift_name;
      }
      // Custom scalar falls through to standard processing
      let uppercased_name = first_uppercased(&swift_name);
      if is_in(SwiftKeywords::TYPE_NAMES_TO_SUFFIX, &uppercased_name) {
        format!("{}{}", uppercased_name, typename_suffix(named_type))
      } else {
        uppercased_name
      }
    }
    GraphQLNamedType::Object(_)
    | GraphQLNamedType::Interface(_)
    | GraphQLNamedType::Union(_)
    | GraphQLNamedType::Enum(_)
    | GraphQLNamedType::InputObject(_) => {
      let uppercased_name = first_uppercased(&swift_name);
      if is_in(SwiftKeywords::TYPE_NAMES_TO_SUFFIX, &uppercased_name) {
        format!("{}{}", uppercased_name, typename_suffix(named_type))
      } else {
        uppercased_name
      }
    }
  }
}

/// Returns the Swift name for a named type, applying standard renaming rules.
///
/// Mirrors Swift's `GraphQLNamedType.swiftName(isInputValue:)` method.
pub fn swift_name_for_type(named_type: &GraphQLNamedType, is_input_value: bool) -> String {
  match named_type.name().schema_name.as_str() {
    "Boolean" => "Bool".to_string(),
    "Float" => "Double".to_string(),
    "Int" => if is_input_value { "Int32".to_string() } else { "Int".to_string() },
    _ => named_type.name().schema_name.clone(),
  }
}

/// Returns the typename suffix for a named type to avoid conflicts.
///
/// Mirrors Swift's `GraphQLNamedType.typenameSuffix` property.
fn typename_suffix(named_type: &GraphQLNamedType) -> &'static str {
  match named_type {
    GraphQLNamedType::Enum(_) => "_Enum",
    GraphQLNamedType::InputObject(_) => "_InputObject",
    GraphQLNamedType::Interface(_) => "_Interface",
    GraphQLNamedType::Object(_) => "_Object",
    GraphQLNamedType::Scalar(_) => "_Scalar",
    GraphQLNamedType::Union(_) => "_Union",
  }
}

/// Returns `true` if a scalar type is a built-in Swift type (String, Int, Float, Boolean).
///
/// Mirrors Swift's `GraphQLScalarType.isSwiftType` property.
pub fn is_swift_type(scalar: &GraphQLScalarType) -> bool {
  matches!(
    scalar.name.schema_name.as_str(),
    "String" | "Int" | "Float" | "Boolean"
  )
}

// MARK: - GraphQLEnumValue rendering

/// The context in which a GraphQL enum value is being rendered.
///
/// Mirrors Swift's `GraphQLEnumValue.RenderContext` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnumRenderContext {
  /// Rendering as a Swift enum case name.
  EnumCase,
  /// Rendering as the raw value for a Swift enum case.
  EnumRawValue,
}

/// Renders a `GraphQLEnumValue` as a string for the given context.
///
/// Mirrors Swift's `GraphQLEnumValue.render(as:config:)` method.
pub fn render_enum_value(
  value: &GraphQLEnumValue,
  context: EnumRenderContext,
  config: &ConfigurationContext,
) -> String {
  // If the name has been customized and it's not for .enumRawValue, return it unchanged
  if let Some(custom_name) = &value.name.custom_name {
    if context != EnumRenderContext::EnumRawValue {
      return custom_name.clone();
    }
  }

  match context {
    EnumRenderContext::EnumCase => render_enum_case(value, config),
    EnumRenderContext::EnumRawValue => value.name.schema_name.clone(),
  }
}

/// Renders an enum value as a Swift enum case name.
/// Mirrors the Swift `ConfigurationContext` overload of `renderEnumCase`: the enum case
/// conversion strategy is applied first, then the configured capitalization rules, then
/// keyword escaping.
fn render_enum_case(value: &GraphQLEnumValue, config: &ConfigurationContext) -> String {
  let case_name = match config.config.options.conversion_strategies.enum_cases {
    EnumCases::None => value.name.schema_name.clone(),
    EnumCases::CamelCase => convert_to_camel_case(&value.name.schema_name),
  };
  as_enum_case_name(&config.capitalizer.apply(&case_name))
}

// MARK: - GraphQLInputField rendering

/// Renders a `GraphQLInputField` name as a Swift property name.
///
/// Mirrors Swift's `GraphQLInputField.render(config:)` method.
pub fn render_input_field(
  field: &GraphQLInputField,
  config: &ConfigurationContext,
) -> String {
  // If the name has been customized, return it unchanged
  if let Some(custom_name) = &field.name.custom_name {
    return custom_name.clone();
  }

  render_input_field_name(field, config)
}

/// Renders the input field name with conversion strategy applied.
/// Mirrors the Swift `ConfigurationContext` overload of `renderInputField`: the input object
/// conversion strategy is applied first, then the configured capitalization rules, then
/// keyword escaping.
fn render_input_field_name(
  field: &GraphQLInputField,
  config: &ConfigurationContext,
) -> String {
  let mut typename = field.name.schema_name.clone();

  match config.config.options.conversion_strategies.input_objects {
    InputObjects::None => {}
    InputObjects::CamelCase => {
      typename = convert_to_camel_case(&typename);
    }
  }

  typename = config.capitalizer.apply(&typename);

  escape_if(&typename, SwiftKeywords::FIELD_ACCESSOR_NAMES_TO_ESCAPE)
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::config::ApolloCodegenConfiguration;

  /// Swift type GraphQL `Int` maps to as an input value in this Apollo iOS version (`Int32`
  /// from 2.0.0).
  const INT_INPUT_VALUE_SWIFT_TYPE: &str = "Int32";
  use graphql_compiler::graphql_name::GraphQLName;
  use graphql_compiler::schema::{
    GraphQLEnumType, GraphQLObjectType,
  };
  use indexmap::IndexMap;
  use std::sync::Arc;

  fn make_scalar_type(name: &str) -> GraphQLNamedType {
    GraphQLNamedType::Scalar(Arc::new(GraphQLScalarType {
      name: GraphQLName::new(name.to_string()),
      documentation: None,
      specified_by_url: None,
    }))
  }

  fn make_object_type(name: &str) -> GraphQLNamedType {
    GraphQLNamedType::Object(Arc::new(GraphQLObjectType {
      name: GraphQLName::new(name.to_string()),
      documentation: None,
      fields: IndexMap::new(),
      interfaces: vec![],
      key_fields: None,
    }))
  }

  fn make_enum_type(name: &str) -> GraphQLNamedType {
    GraphQLNamedType::Enum(Arc::new(GraphQLEnumType {
      name: GraphQLName::new(name.to_string()),
      documentation: None,
      values: vec![],
    }))
  }

  fn default_config() -> ConfigurationContext {
    let config: ApolloCodegenConfiguration = serde_json::from_str(r#"{
      "schemaNamespace": "TestSchema",
      "input": {},
      "output": {
        "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"none": {}}
      }
    }"#).unwrap();
    ConfigurationContext::new(config, None)
  }

  #[test]
  fn test_render_named_type_filename() {
    let named = make_object_type("User");
    assert_eq!(render_named_type(&named, &RenderContext::Filename), "User");
  }

  #[test]
  fn test_render_named_type_typename() {
    let named = make_object_type("User");
    assert_eq!(
      render_named_type(&named, &RenderContext::Typename { is_input_value: false }),
      "User"
    );
  }

  #[test]
  fn test_render_named_type_with_custom_name() {
    let mut name = GraphQLName::new("ACTIVE".to_string());
    name.custom_name = Some("active".to_string());
    let named = GraphQLNamedType::Enum(Arc::new(GraphQLEnumType {
      name,
      documentation: None,
      values: vec![],
    }));
    assert_eq!(
      render_named_type(&named, &RenderContext::Typename { is_input_value: false }),
      "active"
    );
  }

  #[test]
  fn test_render_scalar_boolean_becomes_bool() {
    let named = make_scalar_type("Boolean");
    assert_eq!(
      render_named_type(&named, &RenderContext::Typename { is_input_value: false }),
      "Bool"
    );
  }

  #[test]
  fn test_render_scalar_float_becomes_double() {
    let named = make_scalar_type("Float");
    assert_eq!(
      render_named_type(&named, &RenderContext::Typename { is_input_value: false }),
      "Double"
    );
  }

  #[test]
  fn test_render_scalar_int_as_input_value() {
    let named = make_scalar_type("Int");
    assert_eq!(
      render_named_type(&named, &RenderContext::Typename { is_input_value: true }),
      INT_INPUT_VALUE_SWIFT_TYPE
    );
  }

  #[test]
  fn test_render_scalar_int_not_input_value() {
    let named = make_scalar_type("Int");
    assert_eq!(
      render_named_type(&named, &RenderContext::Typename { is_input_value: false }),
      "Int"
    );
  }

  #[test]
  fn test_type_name_suffix_for_reserved_names() {
    // "Self" is in TYPE_NAMES_TO_SUFFIX
    let named = make_object_type("Self");
    assert_eq!(
      render_named_type(&named, &RenderContext::Typename { is_input_value: false }),
      "Self_Object"
    );
  }

  #[test]
  fn test_type_name_suffix_for_protocol() {
    let named = make_enum_type("Protocol");
    assert_eq!(
      render_named_type(&named, &RenderContext::Typename { is_input_value: false }),
      "Protocol_Enum"
    );
  }

  #[test]
  fn test_is_swift_type_builtins() {
    for name in &["String", "Int", "Float", "Boolean"] {
      let scalar = GraphQLScalarType {
        name: GraphQLName::new(name.to_string()),
        documentation: None,
        specified_by_url: None,
      };
      assert!(is_swift_type(&scalar), "{} should be a Swift type", name);
    }
  }

  #[test]
  fn test_is_swift_type_custom() {
    let scalar = GraphQLScalarType {
      name: GraphQLName::new("DateTime".to_string()),
      documentation: None,
      specified_by_url: None,
    };
    assert!(!is_swift_type(&scalar));
  }

  #[test]
  fn test_render_enum_value_case_camel_case() {
    let config = default_config();
    let value = GraphQLEnumValue {
      name: GraphQLName::new("ACTIVE_STATUS".to_string()),
      documentation: None,
      deprecation_reason: None,
    };
    let result = render_enum_value(&value, EnumRenderContext::EnumCase, &config);
    assert_eq!(result, "activeStatus");
  }

  #[test]
  fn test_render_enum_value_raw_value() {
    let config = default_config();
    let value = GraphQLEnumValue {
      name: GraphQLName::new("ACTIVE_STATUS".to_string()),
      documentation: None,
      deprecation_reason: None,
    };
    let result = render_enum_value(&value, EnumRenderContext::EnumRawValue, &config);
    assert_eq!(result, "ACTIVE_STATUS");
  }

  #[test]
  fn test_render_enum_value_keyword_escaped() {
    let config = default_config();
    let value = GraphQLEnumValue {
      name: GraphQLName::new("class".to_string()),
      documentation: None,
      deprecation_reason: None,
    };
    let result = render_enum_value(&value, EnumRenderContext::EnumCase, &config);
    assert_eq!(result, "`class`");
  }

  #[test]
  fn test_type_name_documentation() {
    let mut name = GraphQLName::new("ACTIVE".to_string());
    name.custom_name = Some("active".to_string());
    assert_eq!(
      name.type_name_documentation(),
      Some("// Renamed from GraphQL schema value: 'ACTIVE'".to_string())
    );
  }

  #[test]
  fn test_type_name_documentation_none() {
    let name = GraphQLName::new("User".to_string());
    assert!(name.type_name_documentation().is_none());
  }
}
