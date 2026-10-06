//! Input variable rendering helpers for code generation.
//!
//! Mirrors Swift's `InputVariableRenderable.swift` from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/InputVariableRenderable.swift`.

use std::sync::Arc;

use graphql_compiler::graphql_name::GraphQLName;
use graphql_compiler::graphql_type::GraphQLType;
use graphql_compiler::graphql_value::GraphQLValue;
use graphql_compiler::schema::{GraphQLEnumValue, GraphQLInputObjectType};

use crate::templates::ConfigurationContext;
use super::graphql_name_rendering::{render_enum_value, render_input_field, render_named_type, EnumRenderContext, RenderContext};
use super::string_casing::first_uppercased;

/// Trait for types that can be rendered as input variables.
///
/// Mirrors Swift's `InputVariableRenderable` protocol.
pub trait InputVariableRenderable {
  fn type_(&self) -> &GraphQLType;
  fn default_value(&self) -> Option<&GraphQLValue>;
}

/// A concrete input variable for rendering.
///
/// Mirrors Swift's `InputVariable` struct.
pub struct InputVariable<'a> {
  pub type_: &'a GraphQLType,
  pub default_value: Option<&'a GraphQLValue>,
}

impl<'a> InputVariableRenderable for InputVariable<'a> {
  fn type_(&self) -> &GraphQLType {
    self.type_
  }
  fn default_value(&self) -> Option<&GraphQLValue> {
    self.default_value
  }
}

/// Renders the default value for an input variable.
///
/// Mirrors Swift's `InputVariableRenderable.renderVariableDefaultValue(config:)`.
/// Resolves an input object type by schema name.
///
/// The compiler builds input object types with immutable shared ownership, so the
/// `GraphQLInputObjectType` reachable through another input object's field may be an
/// unresolved stub without fields (recursive or forward references). Swift's JavaScript
/// bridge has reference semantics and always sees the complete type; the resolver gives the
/// renderer the same view by looking the type up in the schema's referenced types.
pub type InputObjectResolver<'a> = dyn Fn(&str) -> Option<Arc<GraphQLInputObjectType>> + 'a;

pub fn render_variable_default_value(
  renderable: &dyn InputVariableRenderable,
  config: &ConfigurationContext,
) -> String {
  render_variable_default_value_resolving(renderable, config, &|_| None)
}

pub fn render_variable_default_value_resolving(
  renderable: &dyn InputVariableRenderable,
  config: &ConfigurationContext,
  resolver: &InputObjectResolver,
) -> String {
  render_variable_default_value_inner(renderable, false, config, resolver)
}

fn render_variable_default_value_inner(
  renderable: &dyn InputVariableRenderable,
  in_list: bool,
  config: &ConfigurationContext,
  resolver: &InputObjectResolver,
) -> String {
  match renderable.default_value() {
    None => String::new(),
    Some(GraphQLValue::Null) => {
      if in_list { "nil".to_string() } else { ".null".to_string() }
    }
    Some(GraphQLValue::String(s)) => format!("\"{}\"", s),
    Some(GraphQLValue::Boolean(b)) => if *b { "true".to_string() } else { "false".to_string() },
    Some(GraphQLValue::Int(i)) => i.to_string(),
    Some(GraphQLValue::Float(f)) => swift_double_description(*f),
    Some(GraphQLValue::Enum(enum_value)) => {
      let enum_case = GraphQLEnumValue {
        name: GraphQLName::new(enum_value.clone()),
        documentation: None,
        deprecation_reason: None,
      };
      format!(
        ".init(.{})",
        render_enum_value(&enum_case, EnumRenderContext::EnumCase, config)
      )
    }
    Some(GraphQLValue::List(list)) => {
      let list_inner_type = match renderable.type_() {
        GraphQLType::NonNull(inner) => match inner.as_ref() {
          GraphQLType::List(inner_type) => inner_type,
          _ => panic!("Variable type must be List with value of .list type."),
        },
        GraphQLType::List(inner_type) => inner_type,
        _ => panic!("Variable type must be List with value of .list type."),
      };

      let items: Vec<String> = list
        .iter()
        .filter_map(|v| {
          let variable = InputVariable {
            type_: list_inner_type,
            default_value: Some(v),
          };
          let rendered = render_variable_default_value_inner(&variable, true, config, resolver);
          if rendered.is_empty() { None } else { Some(rendered) }
        })
        .collect();
      // Swift 2.0.0 renders list defaults with `\(list:)`: more than one item wraps
      // onto separate lines with continuation indentation.
      if items.len() > 1 {
        format!("[\n  {}\n]", indent_continuation_lines(&items.join(",\n"), "  "))
      } else {
        format!("[{}]", items.join(",\n"))
      }
    }
    Some(GraphQLValue::Object(object)) => {
      match renderable.type_() {
        GraphQLType::NonNull(inner) => {
          if let GraphQLType::InputObject(input_obj_type) = inner.as_ref() {
            render_initializer(input_obj_type, object, config, resolver)
          } else {
            panic!("Variable type must be InputObject with value of .object type.")
          }
        }
        GraphQLType::InputObject(input_obj_type) => {
          // Swift 2.0.0: inside a list the initializer is rendered directly;
          // otherwise `.init(\n  <initializer>\n)` with continuation indentation.
          if in_list {
            render_initializer(input_obj_type, object, config, resolver)
          } else {
            format!(
              ".init(\n  {}\n)",
              indent_continuation_lines(&render_initializer(input_obj_type, object, config, resolver), "  ")
            )
          }
        }
        _ => panic!("Variable type must be InputObject with value of .object type."),
      }
    }
    Some(GraphQLValue::Variable(_)) => {
      panic!("Variable cannot be used as Default Value for an Operation Variable!")
    }
  }
}

/// Renders an initializer call for an input object type with the given values.
///
/// Mirrors Swift's `GraphQLInputObjectType.renderInitializer(values:config:)`.
fn render_initializer(
  input_type: &GraphQLInputObjectType,
  values: &indexmap::IndexMap<String, GraphQLValue>,
  config: &ConfigurationContext,
  resolver: &InputObjectResolver,
) -> String {
  let resolved = resolver(&input_type.name.schema_name);
  let input_type: &GraphQLInputObjectType = match resolved.as_deref() {
    Some(complete) => complete,
    None => input_type,
  };
  let entries: Vec<String> = values
    .iter()
    .filter_map(|(key, value)| {
      let field = input_type.fields.get(key)?;
      let variable = InputVariable {
        type_: &field.type_,
        default_value: Some(value),
      };
      let rendered_name = render_input_field(field, config);
      let rendered_value = render_variable_default_value_resolving(&variable, config, resolver);
      Some(format!("{}: {}", rendered_name, rendered_value))
    })
    .collect();

  let type_name = render_named_type(
    &graphql_compiler::schema::GraphQLNamedType::InputObject(
      std::sync::Arc::new(input_type.clone()),
    ),
    &RenderContext::Typename { is_input_value: false },
  );

  let prefix = if !config.config.output.operations.is_in_module() {
    format!("{}.", first_uppercased(&config.config.schema_namespace))
  } else {
    String::new()
  };

  // Mirrors TemplateString's `\(list: entries)`: more than one entry wraps the
  // list in newlines with a 2-space indent applied to every subsequent line.
  let list = if entries.len() > 1 {
    format!("\n  {}\n", indent_continuation_lines(&entries.join(",\n"), "  "))
  } else {
    entries.join(",\n")
  };
  format!("{}{}({})", prefix, type_name, list)
}

/// Indents every line after the first by `indent`, mirroring how Swift's
/// `TemplateString` interpolation applies the current line's indentation to a
/// multi-line interpolated value.
pub fn indent_continuation_lines(s: &str, indent: &str) -> String {
  let mut lines = s.split('\n');
  let mut out = String::new();
  if let Some(first) = lines.next() {
    out.push_str(first);
  }
  for line in lines {
    out.push('\n');
    if !line.is_empty() {
      out.push_str(indent);
    }
    out.push_str(line);
  }
  out
}

/// Mirrors Swift's `Double.description` formatting for finite values:
/// integral values render with a trailing `.0` (e.g. `5.0`), exponents use the
/// `e+NN` / `e-NN` form.
pub fn swift_double_description(f: f64) -> String {
  if !f.is_finite() {
    return if f.is_nan() { "nan".to_string() } else if f > 0.0 { "inf".to_string() } else { "-inf".to_string() };
  }
  if f == 0.0 {
    return if f.is_sign_negative() { "-0.0".to_string() } else { "0.0".to_string() };
  }
  let exp = f.abs().log10().floor() as i32;
  if exp < -4 || exp >= 16 {
    // Shortest round-trip mantissa with Swift-style exponent.
    let s = format!("{:e}", f);
    let (mant, e) = s.split_once('e').unwrap();
    let e: i32 = e.parse().unwrap();
    let sign = if e < 0 { "-" } else { "+" };
    return format!("{}e{}{:02}", mant, sign, e.abs());
  }
  if f.fract() == 0.0 {
    format!("{:.1}", f)
  } else {
    f.to_string()
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::config::ApolloCodegenConfiguration;
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
  fn test_render_none_default() {
    let config = default_config();
    let var = InputVariable {
      type_: &make_string_type(),
      default_value: None,
    };
    assert_eq!(render_variable_default_value(&var, &config), "");
  }

  #[test]
  fn test_render_null_default() {
    let config = default_config();
    let t = make_string_type();
    let var = InputVariable {
      type_: &t,
      default_value: Some(&GraphQLValue::Null),
    };
    assert_eq!(render_variable_default_value(&var, &config), ".null");
  }

  #[test]
  fn test_render_string_default() {
    let config = default_config();
    let t = make_string_type();
    let var = InputVariable {
      type_: &t,
      default_value: Some(&GraphQLValue::String("hello".to_string())),
    };
    assert_eq!(render_variable_default_value(&var, &config), "\"hello\"");
  }

  #[test]
  fn test_render_boolean_default() {
    let config = default_config();
    let t = make_string_type();
    let var = InputVariable {
      type_: &t,
      default_value: Some(&GraphQLValue::Boolean(true)),
    };
    assert_eq!(render_variable_default_value(&var, &config), "true");
  }

  #[test]
  fn test_render_int_default() {
    let config = default_config();
    let t = make_string_type();
    let var = InputVariable {
      type_: &t,
      default_value: Some(&GraphQLValue::Int(42)),
    };
    assert_eq!(render_variable_default_value(&var, &config), "42");
  }

  #[test]
  fn test_render_enum_default() {
    let config = default_config();
    let t = make_string_type();
    let var = InputVariable {
      type_: &t,
      default_value: Some(&GraphQLValue::Enum("ACTIVE".to_string())),
    };
    let result = render_variable_default_value(&var, &config);
    assert!(result.contains(".init("));
    assert!(result.contains("active"));
  }

  #[test]
  fn test_render_list_default() {
    let config = default_config();
    let inner_type = make_string_type();
    let list_type = GraphQLType::List(Box::new(inner_type));
    let var = InputVariable {
      type_: &list_type,
      default_value: Some(&GraphQLValue::List(vec![
        GraphQLValue::String("a".to_string()),
        GraphQLValue::String("b".to_string()),
      ])),
    };
    let result = render_variable_default_value(&var, &config);
    // 2.0.0+: `\(list:)` formatting puts more than one item on separate lines
    assert_eq!(result, "[\n  \"a\",\n  \"b\"\n]");
  }
}
