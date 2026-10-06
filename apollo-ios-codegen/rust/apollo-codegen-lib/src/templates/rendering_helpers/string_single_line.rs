//! String single-line conversion helper.
//!
//! Mirrors Swift's `String+SingleLineConversion.swift` from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/String+SingleLineConversion.swift`.

/// Converts a multi-line string to a single line by splitting on newlines,
/// trimming whitespace from each component, and joining with spaces.
///
/// Mirrors Swift's `String.convertedToSingleLine()` method.
pub fn converted_to_single_line(s: &str) -> String {
  s.lines()
    .map(|line| line.trim())
    .collect::<Vec<_>>()
    .join(" ")
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_single_line() {
    assert_eq!(converted_to_single_line("hello"), "hello");
  }

  #[test]
  fn test_multi_line() {
    assert_eq!(
      converted_to_single_line("hello\n  world\n  foo"),
      "hello world foo"
    );
  }

  #[test]
  fn test_empty() {
    assert_eq!(converted_to_single_line(""), "");
  }

  #[test]
  fn test_with_leading_trailing_whitespace() {
    assert_eq!(
      converted_to_single_line("  hello  \n  world  "),
      "hello world"
    );
  }
}
