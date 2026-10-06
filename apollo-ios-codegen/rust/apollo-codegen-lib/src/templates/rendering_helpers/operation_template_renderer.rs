//! Operation template renderer helpers for code generation.
//!
//! Mirrors Swift's `OperationTemplateRenderer.swift` from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/OperationTemplateRenderer.swift`.

use graphql_compiler::graphql_type::GraphQLType;
use graphql_compiler::graphql_value::GraphQLValue;

use crate::templates::ConfigurationContext;
use super::graphql_type_rendered::{rendered, TypeRenderContext};
use super::input_variable_renderable::{
  render_variable_default_value_resolving, InputObjectResolver, InputVariable,
};
use super::string_swift_name_escaping::render_as_field_property_name;

/// A variable definition for rendering in operation templates.
///
/// This is a simplified version that contains just the data needed for rendering,
/// mirroring what `CompilationResult.VariableDefinition` provides to the Swift renderer.
pub struct VariableDefinition {
  pub name: String,
  pub type_: GraphQLType,
  pub default_value: Option<GraphQLValue>,
}

/// Renders the initializer for an operation with the given variables.
///
/// Mirrors Swift's `OperationTemplateRenderer.Initializer(_:)` method.
pub fn render_initializer(
  variables: &[VariableDefinition],
  config: &ConfigurationContext,
) -> String {
  render_initializer_resolving(variables, config, &|_| None)
}

/// Like [`render_initializer`], resolving nested input object types through `resolver` when
/// rendering variable default values.
pub fn render_initializer_resolving(
  variables: &[VariableDefinition],
  config: &ConfigurationContext,
  resolver: &InputObjectResolver,
) -> String {
  let init_keyword = "public init";
  if variables.is_empty() {
    return format!("{}() {{}}", init_keyword);
  }

  let params: Vec<String> = variables
    .iter()
    .map(|v| render_variable_parameter_resolving(v, config, resolver))
    .collect();

  let assignments: Vec<String> = variables
    .iter()
    .map(|v| {
      let name = render_as_field_property_name(&v.name, config);
      format!("self.{} = {}", name, name)
    })
    .collect();

  // Swift TemplateString `list:` separator puts each parameter on its own line
  // with 2-space indentation from init(
  let params_str = if params.len() > 1 {
    format!(
      "\n  {}\n",
      super::input_variable_renderable::indent_continuation_lines(&params.join(",\n"), "  ")
    )
  } else {
    params.join(", ")
  };

  format!(
    "{}({}) {{\n  {}\n}}",
    init_keyword,
    params_str,
    assignments.join("\n  ")
  )
}

/// Renders variable properties for an operation.
///
/// Mirrors Swift's `OperationTemplateRenderer.VariableProperties(_:)` method.
pub fn render_variable_properties(
  variables: &[VariableDefinition],
  config: &ConfigurationContext,
) -> String {
  variables
    .iter()
    .map(|v| {
      let name = render_as_field_property_name(&v.name, config);
      let type_str = rendered(&v.type_, &TypeRenderContext::InputValue, None, &config.config);
      format!("public var {}: {}", name, type_str)
    })
    .collect::<Vec<_>>()
    .join("\n")
}

/// Renders a single variable parameter for an initializer.
///
/// Mirrors Swift's `OperationTemplateRenderer.VariableParameter(_:)` method.
pub fn render_variable_parameter(
  variable: &VariableDefinition,
  config: &ConfigurationContext,
) -> String {
  render_variable_parameter_resolving(variable, config, &|_| None)
}

pub fn render_variable_parameter_resolving(
  variable: &VariableDefinition,
  config: &ConfigurationContext,
  resolver: &InputObjectResolver,
) -> String {
  let name = render_as_field_property_name(&variable.name, config);
  let type_str = rendered(&variable.type_, &TypeRenderContext::InputValue, None, &config.config);

  if variable.default_value.is_some() {
    let input_var = InputVariable {
      type_: &variable.type_,
      default_value: variable.default_value.as_ref(),
    };
    let default_val = render_variable_default_value_resolving(&input_var, config, resolver);
    format!("{}: {} = {}", name, type_str, default_val)
  } else {
    format!("{}: {}", name, type_str)
  }
}

/// Renders variable accessors for an operation.
///
/// Mirrors Swift's `OperationTemplateRenderer.VariableAccessors(_:graphQLOperation:)` method.
pub fn render_variable_accessors(
  variables: &[VariableDefinition],
  config: &ConfigurationContext,
  graphql_operation: bool,
) -> String {
  if variables.is_empty() {
    return String::new();
  }

  let prefix = if !graphql_operation {
    "GraphQLOperation."
  } else {
    ""
  };

  let entries: Vec<String> = variables
    .iter()
    .map(|v| {
      let rendered_name = render_as_field_property_name(&v.name, config);
      format!("\"{}\": {}", v.name, rendered_name)
    })
    .collect();

  // Swift's `list:` syntax renders multiple entries on separate lines
  if entries.len() == 1 {
    format!(
      "@_spi(Unsafe) public var __variables: {}Variables? {{ [{}] }}",
      prefix,
      entries[0]
    )
  } else {
    format!(
      "@_spi(Unsafe) public var __variables: {}Variables? {{ [\n  {}\n] }}",
      prefix,
      entries.join(",\n  ")
    )
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::config::ApolloCodegenConfiguration;

  /// Attribute Apollo iOS renders before the `__variables` accessor (`@_spi(Unsafe) ` from
  /// 2.0.0, nothing before).
  const VARIABLES_ACCESSOR_PREFIX: &str = "@_spi(Unsafe) ";
  use graphql_compiler::graphql_name::GraphQLName;
  use graphql_compiler::schema::GraphQLScalarType;
  use std::sync::Arc;

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

  fn make_string_type() -> GraphQLType {
    GraphQLType::Scalar(Arc::new(GraphQLScalarType {
      name: GraphQLName::new("String".to_string()),
      documentation: None,
      specified_by_url: None,
    }))
  }

  #[test]
  fn test_render_initializer_no_variables() {
    let config = default_config();
    let result = render_initializer(&[], &config);
    assert_eq!(result, "public init() {}");
  }

  #[test]
  fn test_render_initializer_with_variables() {
    let config = default_config();
    let vars = vec![
      VariableDefinition {
        name: "name".to_string(),
        type_: GraphQLType::NonNull(Box::new(make_string_type())),
        default_value: None,
      },
    ];
    let result = render_initializer(&vars, &config);
    assert!(result.contains("public init(name: String)"));
    assert!(result.contains("self.name = name"));
  }

  #[test]
  fn test_render_variable_properties() {
    let config = default_config();
    let vars = vec![
      VariableDefinition {
        name: "userId".to_string(),
        type_: GraphQLType::NonNull(Box::new(make_string_type())),
        default_value: None,
      },
    ];
    let result = render_variable_properties(&vars, &config);
    assert_eq!(result, "public var userId: String");
  }

  #[test]
  fn test_render_variable_accessors() {
    let config = default_config();
    let vars = vec![
      VariableDefinition {
        name: "userId".to_string(),
        type_: GraphQLType::NonNull(Box::new(make_string_type())),
        default_value: None,
      },
    ];
    let result = render_variable_accessors(&vars, &config, true);
    assert!(
      result.starts_with(&format!("{}public var __variables: Variables?", VARIABLES_ACCESSOR_PREFIX)),
      "actual:\n{}",
      result
    );
    assert!(result.contains("\"userId\": userId"));
  }

  #[test]
  fn test_render_variable_accessors_empty() {
    let config = default_config();
    let result = render_variable_accessors(&[], &config, true);
    assert_eq!(result, "");
  }

  #[test]
  fn test_render_variable_parameter_with_default() {
    let config = default_config();
    let var = VariableDefinition {
      name: "limit".to_string(),
      type_: make_string_type(), // nullable
      default_value: Some(GraphQLValue::Null),
    };
    let result = render_variable_parameter(&var, &config);
    assert!(result.contains("limit:"));
    assert!(result.contains("= .null"));
  }
}
