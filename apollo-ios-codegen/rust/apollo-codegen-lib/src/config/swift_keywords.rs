//! Swift reserved keyword sets for configuration validation and template rendering.
//!
//! Mirrors Swift's `SwiftKeywords` enum from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/String+SwiftNameEscaping.swift`.

/// Constants for Swift reserved keywords and disallowed names used in validation
/// and template rendering.
pub struct SwiftKeywords;

impl SwiftKeywords {
  /// Schema namespace names that conflict with generated code.
  /// Comparisons should be case-insensitive (lowercased before lookup).
  pub const DISALLOWED_SCHEMA_NAMESPACE_NAMES: &[&str] = &["schema", "apolloapi"];

  /// Embedded target names that conflict with reserved library names.
  /// Comparisons should be case-insensitive (lowercased before lookup).
  pub const DISALLOWED_EMBEDDED_TARGET_NAMES: &[&str] = &["apollo", "apolloapi"];

  /// Field names that conflict with generated `SelectionSet` properties.
  pub const DISALLOWED_FIELD_NAMES: &[&str] = &["__data", "fragments"];

  /// Input parameter names that are disallowed.
  pub const DISALLOWED_INPUT_PARAMETER_NAMES: &[&str] = &["self", "_"];

  /// Type names that must be suffixed to avoid conflicts with Swift/ApolloAPI types.
  pub const TYPE_NAMES_TO_SUFFIX: &[&str] = &[
    "Any",
    "DataDict",
    "DocumentType",
    "Fragments",
    "FragmentContainer",
    "ParentType",
    "Protocol",
    "Schema",
    "Selection",
    "Self",
    "String",
    "Bool",
    "Int",
    "Int32",
    "Float",
    "Double",
    "ID",
    "Type",
    "Error",
    "_",
  ];

  /// Abstract type names that need namespacing in test mocks to avoid
  /// Swift compiler confusion with `Swift.Actor`.
  pub const TEST_MOCK_FIELD_ABSTRACT_TYPE_NAMES_TO_NAMESPACE: &[&str] = &["Actor"];

  /// Field names that conflict with `Mock`'s `@dynamicMember` subscripting.
  pub const TEST_MOCK_CONFLICTING_FIELD_NAMES: &[&str] = &["hash"];

  /// Swift keywords and reserved names that must be backtick-escaped when used
  /// as field accessor property names.
  pub const FIELD_ACCESSOR_NAMES_TO_ESCAPE: &[&str] = &[
    "associatedtype",
    "class",
    "deinit",
    "enum",
    "extension",
    "fileprivate",
    "func",
    "import",
    "init",
    "inout",
    "internal",
    "let",
    "operator",
    "private",
    "precedencegroup",
    "protocol",
    "Protocol",
    "public",
    "rethrows",
    "static",
    "struct",
    "subscript",
    "typealias",
    "var",
    "break",
    "case",
    "catch",
    "continue",
    "default",
    "defer",
    "do",
    "else",
    "fallthrough",
    "for",
    "guard",
    "if",
    "in",
    "repeat",
    "return",
    "throw",
    "switch",
    "where",
    "while",
    "as",
    "false",
    "is",
    "nil",
    "self",
    "Self",
    "super",
    "throws",
    "true",
    "try",
    "_",
  ];

  /// Input parameter names to escape -- same as field accessor names.
  pub const INPUT_PARAMETER_NAMES_TO_ESCAPE: &[&str] = Self::FIELD_ACCESSOR_NAMES_TO_ESCAPE;

  /// Test mock field names to escape -- field accessor names plus "Type" and "Any".
  pub const TEST_MOCK_FIELD_NAMES_TO_ESCAPE: &[&str] = &[
    "associatedtype",
    "class",
    "deinit",
    "enum",
    "extension",
    "fileprivate",
    "func",
    "import",
    "init",
    "inout",
    "internal",
    "let",
    "operator",
    "private",
    "precedencegroup",
    "protocol",
    "Protocol",
    "public",
    "rethrows",
    "static",
    "struct",
    "subscript",
    "typealias",
    "var",
    "break",
    "case",
    "catch",
    "continue",
    "default",
    "defer",
    "do",
    "else",
    "fallthrough",
    "for",
    "guard",
    "if",
    "in",
    "repeat",
    "return",
    "throw",
    "switch",
    "where",
    "while",
    "as",
    "false",
    "is",
    "nil",
    "self",
    "Self",
    "super",
    "throws",
    "true",
    "try",
    "_",
    "Type",
    "Any",
  ];

  /// Test mock initializer parameters that need a `_value` suffix.
  pub const TEST_MOCK_INITIALIZER_PARAMETERS_TO_SUFFIX: &[&str] = &["self"];
}

/// Returns `true` if the given value is contained in the set.
pub fn is_in(set: &[&str], value: &str) -> bool {
  set.contains(&value)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_field_accessor_names_count() {
    // Swift has exactly 54 entries matching the FieldAccessorNamesToEscape set
    assert_eq!(SwiftKeywords::FIELD_ACCESSOR_NAMES_TO_ESCAPE.len(), 54);
  }

  #[test]
  fn test_type_names_to_suffix_count() {
    assert_eq!(SwiftKeywords::TYPE_NAMES_TO_SUFFIX.len(), 20);
  }

  #[test]
  fn test_test_mock_field_names_includes_extra() {
    assert!(is_in(SwiftKeywords::TEST_MOCK_FIELD_NAMES_TO_ESCAPE, "Type"));
    assert!(is_in(SwiftKeywords::TEST_MOCK_FIELD_NAMES_TO_ESCAPE, "Any"));
    assert!(is_in(SwiftKeywords::TEST_MOCK_FIELD_NAMES_TO_ESCAPE, "class"));
  }

  #[test]
  fn test_is_in_helper() {
    assert!(is_in(SwiftKeywords::FIELD_ACCESSOR_NAMES_TO_ESCAPE, "class"));
    assert!(is_in(SwiftKeywords::FIELD_ACCESSOR_NAMES_TO_ESCAPE, "self"));
    assert!(!is_in(SwiftKeywords::FIELD_ACCESSOR_NAMES_TO_ESCAPE, "notAKeyword"));
  }

  #[test]
  fn test_disallowed_field_names() {
    assert!(is_in(SwiftKeywords::DISALLOWED_FIELD_NAMES, "__data"));
    assert!(is_in(SwiftKeywords::DISALLOWED_FIELD_NAMES, "fragments"));
  }

  #[test]
  fn test_disallowed_input_parameter_names() {
    assert!(is_in(SwiftKeywords::DISALLOWED_INPUT_PARAMETER_NAMES, "self"));
    assert!(is_in(SwiftKeywords::DISALLOWED_INPUT_PARAMETER_NAMES, "_"));
  }
}
