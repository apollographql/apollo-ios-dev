//! Swift name escaping and conversion helpers.
//!
//! Mirrors Swift's `String+SwiftNameEscaping.swift` from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/String+SwiftNameEscaping.swift`.

use super::string_casing::{first_lowercased, first_uppercased, is_all_uppercased};
use crate::capitalizer::Capitalizer;
use crate::config::conversion_strategies::FieldAccessors;
use crate::config::swift_keywords::{is_in, SwiftKeywords};
use crate::templates::ConfigurationContext;

/// Returns the string as an enum case name, escaping if it conflicts with Swift keywords.
pub fn as_enum_case_name(s: &str) -> String {
    escape_if(s, SwiftKeywords::FIELD_ACCESSOR_NAMES_TO_ESCAPE)
}

/// Returns the string as a selection set name, suffixing if it conflicts with reserved type names.
pub fn as_selection_set_name(s: &str) -> String {
    if is_in(SwiftKeywords::TYPE_NAMES_TO_SUFFIX, s) {
        format!("{}_SelectionSet", s)
    } else {
        s.to_string()
    }
}

/// Renders the string as a generated fragment type name with any configured capitalization
/// rules applied. Names that collide with reserved type names are suffixed with `_Fragment`.
///
/// Mirrors Swift's `String.asFragmentName(capitalizer:)` (2.4.0).
pub fn as_fragment_name(s: &str, capitalizer: &Capitalizer) -> String {
    let name = as_normalized_fragment_name(s, capitalizer);
    if is_in(SwiftKeywords::TYPE_NAMES_TO_SUFFIX, &name) {
        format!("{}_Fragment", name)
    } else {
        name
    }
}

/// Normalizes the string as a generated fragment name, without reserved type name escaping.
/// Shared by the generated fragment type name and file name so the two cannot drift apart.
///
/// The name is `firstUppercased` both before the rules run (so rules match the type-name form
/// of each word segment) and after (so the name always begins with a capital letter).
///
/// Mirrors Swift's `String.asNormalizedFragmentName(capitalizer:)` (2.4.0).
pub fn as_normalized_fragment_name(s: &str, capitalizer: &Capitalizer) -> String {
    first_uppercased(&capitalizer.apply(&first_uppercased(s)))
}

/// Returns the string as a test mock field property name, escaping if it conflicts.
pub fn as_test_mock_field_property_name(s: &str) -> String {
    escape_if(s, SwiftKeywords::TEST_MOCK_FIELD_NAMES_TO_ESCAPE)
}

/// Returns the suffixed test mock initializer parameter name if the name conflicts,
/// or `None` if no suffix is needed.
pub fn as_test_mock_initializer_parameter_name(s: &str) -> Option<String> {
    if is_in(SwiftKeywords::TEST_MOCK_INITIALIZER_PARAMETERS_TO_SUFFIX, s) {
        Some(format!("{}_value", s))
    } else {
        None
    }
}

/// Returns `true` if the name conflicts with test mock field names.
pub fn is_conflicting_test_mock_field_name(s: &str) -> bool {
    is_in(SwiftKeywords::TEST_MOCK_CONFLICTING_FIELD_NAMES, s)
}

/// Backtick-wraps the string if it is contained in the given set.
pub fn escape_if(s: &str, set: &[&str]) -> String {
    if is_in(set, s) {
        format!("`{}`", s)
    } else {
        s.to_string()
    }
}

/// Prefixes with underscore if contained in the set.
fn alias_if(s: &str, set: &[&str]) -> String {
    if is_in(set, s) {
        format!("_{}", s)
    } else {
        s.to_string()
    }
}

/// Backtick-wraps and adds underscore alias if contained in the set.
fn escape_with_alias_if(s: &str, set: &[&str]) -> String {
    if is_in(set, s) {
        format!("`{}` _{}", s, s)
    } else {
        s.to_string()
    }
}

/// Common logic for rendering a property name with config-driven casing.
///
/// Mirrors the Swift `ConfigurationContext` overload of `renderedAsPropertyName(config:)`:
/// the field accessor conversion strategy is applied first, then the configured
/// capitalization rules, and finally the first-lowercasing.
fn rendered_as_property_name(s: &str, config: &ConfigurationContext) -> String {
    let mut property_name = s.to_string();

    match config.config.options.conversion_strategies.field_accessors {
        FieldAccessors::CamelCase => {
            property_name = convert_to_camel_case(&property_name);
        }
        FieldAccessors::Idiomatic => {}
    }

    property_name = config.capitalizer.apply(&property_name);

    if is_all_uppercased(&property_name) {
        property_name.to_lowercase()
    } else {
        first_lowercased(&property_name)
    }
}

/// Renders the string as the property name for a field accessor on a generated `SelectionSet`.
/// Escapes names that would conflict with Swift reserved keywords.
pub fn render_as_field_property_name(s: &str, config: &ConfigurationContext) -> String {
    let property_name = rendered_as_property_name(s, config);
    escape_if(
        &property_name,
        SwiftKeywords::FIELD_ACCESSOR_NAMES_TO_ESCAPE,
    )
}

/// Renders the string as the parameter name for an initializer on a generated `SelectionSet`.
/// Escapes and aliases names that would conflict with Swift reserved keywords.
pub fn render_as_initializer_parameter_name(s: &str, config: &ConfigurationContext) -> String {
    let property_name = rendered_as_property_name(s, config);
    escape_with_alias_if(
        &property_name,
        SwiftKeywords::FIELD_ACCESSOR_NAMES_TO_ESCAPE,
    )
}

/// Renders the string as the parameter accessor name for an initializer on a generated `SelectionSet`.
/// Aliases names that would conflict with Swift reserved keywords.
pub fn render_as_initializer_parameter_accessor_name(
    s: &str,
    config: &ConfigurationContext,
) -> String {
    let property_name = rendered_as_property_name(s, config);
    alias_if(
        &property_name,
        SwiftKeywords::FIELD_ACCESSOR_NAMES_TO_ESCAPE,
    )
}

/// Renders the string as a test mock field property name, applying any configured
/// capitalization rules so the mock property matches the corresponding generated model
/// property. With no rules configured this is identical to `as_test_mock_field_property_name`.
///
/// Mirrors Swift's `String.renderAsTestMockFieldPropertyName(config:)`.
pub fn render_as_test_mock_field_property_name(s: &str, config: &ConfigurationContext) -> String {
    escape_if(
        &config.capitalizer.apply(s),
        SwiftKeywords::TEST_MOCK_FIELD_NAMES_TO_ESCAPE,
    )
}

/// Converts a string to `camelCase` from `snake_case`, `UpperCamelCase`, or `UPPERCASE`.
///
/// All inner `_` characters are removed, each 'word' is capitalized, and the result
/// is `firstLowercased`, preserving original leading and trailing `_` characters.
///
/// Mirrors Swift's `String.convertToCamelCase()` method.
pub fn convert_to_camel_case(s: &str) -> String {
    // If no underscore found
    if !s.contains('_') {
        // If string has any lowercase char, just firstLowercase it
        if s.chars().any(|c| c.is_lowercase()) {
            return first_lowercased(s);
        } else {
            // All uppercase -- just lowercase all
            return s.to_lowercase();
        }
    }

    let result: String = s
        .split('_')
        .map(|segment| {
            if segment.is_empty() {
                "_".to_string()
            } else {
                // Swift's `capitalized` lowercases everything then uppercases the first char
                let mut chars = segment.chars();
                match chars.next() {
                    None => String::new(),
                    Some(first) => {
                        let mut capitalized = first.to_uppercase().to_string();
                        for c in chars {
                            capitalized.extend(c.to_lowercase());
                        }
                        capitalized
                    }
                }
            }
        })
        .collect();

    first_lowercased(&result)
}

/// Replaces Swift string special characters with their escaped forms.
///
/// Mirrors Swift's `String.escapedSwiftStringSpecialCharacters()` method.
pub fn escaped_swift_string_special_characters(s: &str) -> String {
    let mut result = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\0' => result.push_str("\\0"),
            '\\' => result.push_str("\\\\"),
            '\t' => result.push_str("\\t"),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '"' => result.push_str("\\\""),
            '\'' => result.push_str("\\'"),
            _ => result.push(c),
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_convert_to_camel_case_snake_case() {
        assert_eq!(convert_to_camel_case("snake_case"), "snakeCase");
    }

    #[test]
    fn test_convert_to_camel_case_all_uppercase() {
        assert_eq!(convert_to_camel_case("ACTIVE"), "active");
    }

    #[test]
    fn test_convert_to_camel_case_already_camel() {
        assert_eq!(convert_to_camel_case("alreadyCamel"), "alreadyCamel");
    }

    #[test]
    fn test_convert_to_camel_case_upper_camel() {
        assert_eq!(convert_to_camel_case("UpperCamel"), "upperCamel");
    }

    #[test]
    fn test_convert_to_camel_case_leading_underscore() {
        // "_leading" splits to ["", "leading"] -> ["_", "Leading"] -> "_Leading"
        // then firstLowercased("_Leading") -> "_leading"
        assert_eq!(convert_to_camel_case("_leading"), "_leading");
    }

    #[test]
    fn test_convert_to_camel_case_trailing_underscore() {
        assert_eq!(convert_to_camel_case("trailing_"), "trailing_");
    }

    #[test]
    fn test_convert_to_camel_case_multiple_underscores() {
        assert_eq!(convert_to_camel_case("one_two_three"), "oneTwoThree");
    }

    #[test]
    fn test_convert_to_camel_case_uppercase_segments() {
        assert_eq!(convert_to_camel_case("SOME_VALUE"), "someValue");
    }

    #[test]
    fn test_escape_if_keyword() {
        assert_eq!(
            escape_if("class", SwiftKeywords::FIELD_ACCESSOR_NAMES_TO_ESCAPE),
            "`class`"
        );
    }

    #[test]
    fn test_escape_if_not_keyword() {
        assert_eq!(
            escape_if("name", SwiftKeywords::FIELD_ACCESSOR_NAMES_TO_ESCAPE),
            "name"
        );
    }

    #[test]
    fn test_escaped_swift_string_special_characters_quotes() {
        assert_eq!(
            escaped_swift_string_special_characters("he\"llo"),
            "he\\\"llo"
        );
    }

    #[test]
    fn test_escaped_swift_string_special_characters_newline() {
        assert_eq!(
            escaped_swift_string_special_characters("he\nllo"),
            "he\\nllo"
        );
    }

    #[test]
    fn test_escaped_swift_string_special_characters_backslash() {
        assert_eq!(
            escaped_swift_string_special_characters("he\\llo"),
            "he\\\\llo"
        );
    }

    #[test]
    fn test_escaped_swift_string_special_characters_tab() {
        assert_eq!(
            escaped_swift_string_special_characters("he\tllo"),
            "he\\tllo"
        );
    }

    #[test]
    fn test_escaped_swift_string_special_characters_no_special() {
        assert_eq!(
            escaped_swift_string_special_characters("hello world"),
            "hello world"
        );
    }

    #[test]
    fn test_as_enum_case_name_keyword() {
        assert_eq!(as_enum_case_name("class"), "`class`");
    }

    #[test]
    fn test_as_enum_case_name_non_keyword() {
        assert_eq!(as_enum_case_name("active"), "active");
    }

    #[test]
    fn test_as_selection_set_name_conflict() {
        assert_eq!(as_selection_set_name("Self"), "Self_SelectionSet");
        assert_eq!(as_selection_set_name("Protocol"), "Protocol_SelectionSet");
    }

    #[test]
    fn test_as_selection_set_name_no_conflict() {
        assert_eq!(as_selection_set_name("User"), "User");
    }

    #[test]
    fn test_as_fragment_name_conflict() {
        assert_eq!(
            as_fragment_name("string", &Capitalizer::default()),
            "String_Fragment"
        );
        assert_eq!(
            as_fragment_name("protocol", &Capitalizer::default()),
            "Protocol_Fragment"
        );
    }

    #[test]
    fn test_as_fragment_name_no_conflict() {
        assert_eq!(as_fragment_name("user", &Capitalizer::default()), "User");
    }

    #[test]
    fn test_as_test_mock_field_property_name() {
        assert_eq!(as_test_mock_field_property_name("Type"), "`Type`");
        assert_eq!(as_test_mock_field_property_name("Any"), "`Any`");
        assert_eq!(as_test_mock_field_property_name("name"), "name");
    }

    #[test]
    fn test_as_test_mock_initializer_parameter_name() {
        assert_eq!(
            as_test_mock_initializer_parameter_name("self"),
            Some("self_value".to_string())
        );
        assert_eq!(as_test_mock_initializer_parameter_name("name"), None);
    }

    #[test]
    fn test_is_conflicting_test_mock_field_name() {
        assert!(is_conflicting_test_mock_field_name("hash"));
        assert!(!is_conflicting_test_mock_field_name("name"));
    }
}
