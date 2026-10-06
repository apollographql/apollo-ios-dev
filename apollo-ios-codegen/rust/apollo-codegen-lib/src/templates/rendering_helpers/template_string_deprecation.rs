//! Deprecation message rendering helper for template strings.
//!
//! Mirrors Swift's `TemplateString+DeprecationMessage.swift` from
//! `Sources/ApolloCodegenLib/TemplateString+DeprecationMessage.swift`.

use crate::config::composition::Composition;
use crate::templates::ConfigurationContext;
use super::string_swift_name_escaping::escaped_swift_string_special_characters;

/// Renders a deprecation annotation if warnings on deprecated usage is enabled.
///
/// Returns `None` when `config.options.warnings_on_deprecated_usage != Include` or when
/// the reason is `None`.
///
/// Returns `@available(*, deprecated, message: "...")` with escaped special characters.
pub fn render_deprecation_reason(
  reason: Option<&str>,
  config: &ConfigurationContext,
) -> Option<String> {
  if config.options().warnings_on_deprecated_usage != Composition::Include {
    return None;
  }

  let reason = reason?;
  let escaped = escaped_swift_string_special_characters(reason);
  Some(format!("@available(*, deprecated, message: \"{}\")", escaped))
}

/// Renders a field argument deprecation warning as a `#warning` directive.
pub fn render_field_argument_warning(
  field: &str,
  argument: &str,
  warning_reason: &str,
) -> String {
  let escaped = escaped_swift_string_special_characters(warning_reason);
  format!(
    "#warning(\"Argument '{}' of field '{}' is deprecated. Reason: '{}'\")",
    argument, field, escaped
  )
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::config::ApolloCodegenConfiguration;

  fn make_config(include_warnings: bool) -> ConfigurationContext {
    let json = if include_warnings {
      r#"{
        "schemaNamespace": "TestSchema",
        "input": {},
        "output": {
          "schemaTypes": { "path": "./gen", "moduleType": {"other": {}} },
          "operations": {"inSchemaModule": {}},
          "testMocks": {"none": {}}
        },
        "options": { "warningsOnDeprecatedUsage": "include" }
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
        "options": { "warningsOnDeprecatedUsage": "exclude" }
      }"#
    };
    let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
    ConfigurationContext::new(config, None)
  }

  #[test]
  fn test_render_deprecation_reason_includes() {
    let config = make_config(true);
    let result = render_deprecation_reason(Some("Use newField instead"), &config);
    assert_eq!(
      result,
      Some("@available(*, deprecated, message: \"Use newField instead\")".to_string())
    );
  }

  #[test]
  fn test_render_deprecation_reason_excludes() {
    let config = make_config(false);
    let result = render_deprecation_reason(Some("Use newField instead"), &config);
    assert_eq!(result, None);
  }

  #[test]
  fn test_render_deprecation_reason_none() {
    let config = make_config(true);
    let result = render_deprecation_reason(None, &config);
    assert_eq!(result, None);
  }

  #[test]
  fn test_render_deprecation_reason_with_special_chars() {
    let config = make_config(true);
    let result = render_deprecation_reason(Some("Use \"newField\" instead"), &config);
    assert_eq!(
      result,
      Some("@available(*, deprecated, message: \"Use \\\"newField\\\" instead\")".to_string())
    );
  }
}
