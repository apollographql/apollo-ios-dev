//! Documentation rendering helper for template strings.
//!
//! Mirrors Swift's `TemplateString+Documentation.swift` from
//! `Sources/ApolloCodegenLib/TemplateString+Documentation.swift`.

use crate::config::composition::Composition;
use crate::templates::ConfigurationContext;

/// Renders documentation as `///` prefixed lines if schema documentation is enabled.
///
/// Returns `None` when `config.options.schema_documentation != Include` or when
/// the documentation string is `None`.
pub fn render_documentation(
  documentation: Option<&str>,
  config: &ConfigurationContext,
) -> Option<String> {
  if config.options().schema_documentation != Composition::Include {
    return None;
  }

  let doc = documentation?;
  if doc.is_empty() {
    return None;
  }

  let lines: Vec<String> = doc
    .lines()
    .map(|line| {
      if line.trim().is_empty() {
        "///".to_string()
      } else {
        format!("/// {}", line)
      }
    })
    .collect();

  Some(lines.join("\n"))
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::config::ApolloCodegenConfiguration;

  fn make_config(include_docs: bool) -> ConfigurationContext {
    let json = if include_docs {
      r#"{
        "schemaNamespace": "TestSchema",
        "input": {},
        "output": {
          "schemaTypes": { "path": "./gen", "moduleType": {"other": {}} },
          "operations": {"inSchemaModule": {}},
          "testMocks": {"none": {}}
        },
        "options": { "schemaDocumentation": "include" }
      }"#
    } else {
      r#"{
        "schemaNamespace": "TestSchema",
        "input": {},
        "output": {
          "schemaTypes": { "path": "./gen", "moduleType": {"other": {}} },
          "operations": {"inSchemaModule": {}},
          "testMocks": {"none": {}}
        },
        "options": { "schemaDocumentation": "exclude" }
      }"#
    };
    let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
    ConfigurationContext::new(config, None)
  }

  #[test]
  fn test_render_documentation_includes() {
    let config = make_config(true);
    let result = render_documentation(Some("A user type"), &config);
    assert_eq!(result, Some("/// A user type".to_string()));
  }

  #[test]
  fn test_render_documentation_excludes() {
    let config = make_config(false);
    let result = render_documentation(Some("A user type"), &config);
    assert_eq!(result, None);
  }

  #[test]
  fn test_render_documentation_none_input() {
    let config = make_config(true);
    let result = render_documentation(None, &config);
    assert_eq!(result, None);
  }

  #[test]
  fn test_render_documentation_multiline() {
    let config = make_config(true);
    let result = render_documentation(Some("Line 1\nLine 2"), &config);
    assert_eq!(result, Some("/// Line 1\n/// Line 2".to_string()));
  }
}
