//! Field argument rendering helpers for code generation.
//!
//! Mirrors Swift's `FieldArgumentRendering.swift` from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/FieldArgumentRendering.swift`.

use graphql_compiler::graphql_value::GraphQLValue;

use super::input_variable_renderable::{indent_continuation_lines, swift_double_description};

/// Renders a `GraphQLValue` as a Swift literal for use in field argument default values.
///
/// The `indent_level` parameter controls multiline rendering for nested objects:
/// objects with 2+ entries render multiline with entries at `indent_level + 2` spaces
/// and closing bracket at `indent_level` spaces.
///
/// Mirrors Swift's `GraphQLValue.renderInputValueLiteral()` method.
pub fn render_input_value_literal(value: &GraphQLValue, indent_level: usize) -> String {
  match value {
    // A string containing line breaks is interpolated as-is by Swift; `TemplateString`
    // indents the continuation lines to the entry's indentation.
    GraphQLValue::String(s) => {
      indent_continuation_lines(&format!("\"{}\"", s), &" ".repeat(indent_level))
    }
    GraphQLValue::Boolean(b) => if *b { "true".to_string() } else { "false".to_string() },
    GraphQLValue::Int(i) => i.to_string(),
    // Swift renders `Double.description` (`2.0`, `1e-05`), not the shortest integer form.
    GraphQLValue::Float(f) => swift_double_description(*f),
    GraphQLValue::Enum(e) => format!("\"{}\"", e),
    GraphQLValue::Null => ".null".to_string(),
    GraphQLValue::List(list) => {
      let items: Vec<String> = list
        .iter()
        .map(|v| render_input_value_literal(v, indent_level))
        .collect();
      format!("[{}]", items.join(", "))
    }
    GraphQLValue::Object(object) => {
      if object.len() <= 1 {
        let entries: Vec<String> = object
          .iter()
          .map(|(k, v)| format!("\"{}\": {}", k, render_input_value_literal(v, indent_level)))
          .collect();
        format!("[{}]", entries.join(", "))
      } else {
        let entry_indent = indent_level + 2;
        let entry_prefix = " ".repeat(entry_indent);
        let close_prefix = " ".repeat(indent_level);
        let entries: Vec<String> = object
          .iter()
          .map(|(k, v)| format!("{}\"{}\": {}", entry_prefix, k, render_input_value_literal(v, entry_indent)))
          .collect();
        format!("[\n{}\n{}]", entries.join(",\n"), close_prefix)
      }
    }
    GraphQLValue::Variable(var_name) => {
      format!(".variable(\"{}\")", var_name)
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use indexmap::IndexMap;

  #[test]
  fn test_render_string() {
    let result = render_input_value_literal(&GraphQLValue::String("hello".to_string()), 0);
    assert_eq!(result, "\"hello\"");
  }

  #[test]
  fn test_render_boolean_true() {
    let result = render_input_value_literal(&GraphQLValue::Boolean(true), 0);
    assert_eq!(result, "true");
  }

  #[test]
  fn test_render_boolean_false() {
    let result = render_input_value_literal(&GraphQLValue::Boolean(false), 0);
    assert_eq!(result, "false");
  }

  #[test]
  fn test_render_int() {
    let result = render_input_value_literal(&GraphQLValue::Int(42), 0);
    assert_eq!(result, "42");
  }

  #[test]
  fn test_render_float() {
    let result = render_input_value_literal(&GraphQLValue::Float(3.14), 0);
    assert_eq!(result, "3.14");
  }

  #[test]
  fn test_render_enum() {
    let result = render_input_value_literal(&GraphQLValue::Enum("ACTIVE".to_string()), 0);
    assert_eq!(result, "\"ACTIVE\"");
  }

  #[test]
  fn test_render_null() {
    let result = render_input_value_literal(&GraphQLValue::Null, 0);
    assert_eq!(result, ".null");
  }

  #[test]
  fn test_render_list() {
    let result = render_input_value_literal(&GraphQLValue::List(vec![
      GraphQLValue::Int(1),
      GraphQLValue::Int(2),
      GraphQLValue::Int(3),
    ]), 0);
    assert_eq!(result, "[1, 2, 3]");
  }

  #[test]
  fn test_render_object_single_entry() {
    let mut obj = IndexMap::new();
    obj.insert("key".to_string(), GraphQLValue::String("value".to_string()));
    let result = render_input_value_literal(&GraphQLValue::Object(obj), 0);
    assert_eq!(result, "[\"key\": \"value\"]");
  }

  #[test]
  fn test_render_object_multiline() {
    let mut obj = IndexMap::new();
    obj.insert("latitude".to_string(), GraphQLValue::Variable("latitude".to_string()));
    obj.insert("longitude".to_string(), GraphQLValue::Variable("longitude".to_string()));
    let result = render_input_value_literal(&GraphQLValue::Object(obj), 2);
    assert_eq!(result, "[\n    \"latitude\": .variable(\"latitude\"),\n    \"longitude\": .variable(\"longitude\")\n  ]");
  }

  #[test]
  fn test_render_variable() {
    let result = render_input_value_literal(&GraphQLValue::Variable("myVar".to_string()), 0);
    assert_eq!(result, ".variable(\"myVar\")");
  }

  #[test]
  fn test_render_nested_list() {
    let result = render_input_value_literal(&GraphQLValue::List(vec![
      GraphQLValue::List(vec![GraphQLValue::Int(1), GraphQLValue::Int(2)]),
      GraphQLValue::List(vec![GraphQLValue::Int(3)]),
    ]), 0);
    assert_eq!(result, "[[1, 2], [3]]");
  }
}
