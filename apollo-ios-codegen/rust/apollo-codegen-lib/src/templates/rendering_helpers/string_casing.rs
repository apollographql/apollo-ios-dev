//! String casing helpers for code generation.
//!
//! Mirrors Swift's `String+Casing.swift` extension from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/String+Casing.swift`.

/// Returns the string with the first cased character uppercased.
///
/// Finds the first character where `is_alphabetic()` is true and has case,
/// then uppercases through that index and appends the remainder.
/// If no cased character is found, returns the string unchanged.
///
/// Mirrors Swift's `String.firstUppercased` computed property.
pub fn first_uppercased(s: &str) -> String {
  if s.is_empty() {
    return String::new();
  }

  let mut chars = s.char_indices();
  while let Some((i, c)) = chars.next() {
    if c.is_alphabetic() && (c.is_lowercase() || c.is_uppercase()) {
      // Found the first cased character
      let prefix_end = i + c.len_utf8();
      let uppercased_prefix = s[..prefix_end].to_uppercase();
      return format!("{}{}", uppercased_prefix, &s[prefix_end..]);
    }
  }

  // No cased character found -- return unchanged
  s.to_string()
}

/// Returns the string with the first cased character lowercased.
///
/// Finds the first character where `is_alphabetic()` is true and has case,
/// then lowercases through that index and appends the remainder.
/// If no cased character is found, returns the string unchanged.
///
/// Mirrors Swift's `String.firstLowercased` computed property.
pub fn first_lowercased(s: &str) -> String {
  if s.is_empty() {
    return String::new();
  }

  let mut chars = s.char_indices();
  while let Some((i, c)) = chars.next() {
    if c.is_alphabetic() && (c.is_lowercase() || c.is_uppercase()) {
      // Found the first cased character
      let prefix_end = i + c.len_utf8();
      let lowercased_prefix = s[..prefix_end].to_lowercase();
      return format!("{}{}", lowercased_prefix, &s[prefix_end..]);
    }
  }

  // No cased character found -- return unchanged
  s.to_string()
}

/// Returns `true` if the string is equal to its uppercased form.
///
/// Mirrors Swift's `String.isAllUppercased` computed property.
pub fn is_all_uppercased(s: &str) -> bool {
  s == s.to_uppercase()
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_first_uppercased_basic() {
    assert_eq!(first_uppercased("hello"), "Hello");
  }

  #[test]
  fn test_first_uppercased_already_upper() {
    assert_eq!(first_uppercased("Hello"), "Hello");
  }

  #[test]
  fn test_first_uppercased_leading_underscore() {
    assert_eq!(first_uppercased("_test"), "_Test");
  }

  #[test]
  fn test_first_uppercased_leading_numbers() {
    assert_eq!(first_uppercased("123abc"), "123Abc");
  }

  #[test]
  fn test_first_uppercased_empty() {
    assert_eq!(first_uppercased(""), "");
  }

  #[test]
  fn test_first_uppercased_no_cased_chars() {
    assert_eq!(first_uppercased("123"), "123");
  }

  #[test]
  fn test_first_uppercased_single_char() {
    assert_eq!(first_uppercased("a"), "A");
  }

  #[test]
  fn test_first_lowercased_basic() {
    assert_eq!(first_lowercased("Hello"), "hello");
  }

  #[test]
  fn test_first_lowercased_already_lower() {
    assert_eq!(first_lowercased("hello"), "hello");
  }

  #[test]
  fn test_first_lowercased_leading_underscore() {
    assert_eq!(first_lowercased("_Test"), "_test");
  }

  #[test]
  fn test_first_lowercased_all_upper() {
    assert_eq!(first_lowercased("ABC"), "aBC");
  }

  #[test]
  fn test_first_lowercased_empty() {
    assert_eq!(first_lowercased(""), "");
  }

  #[test]
  fn test_is_all_uppercased_true() {
    assert!(is_all_uppercased("ABC"));
    assert!(is_all_uppercased("HELLO_WORLD"));
    assert!(is_all_uppercased("123")); // no lowercase chars
  }

  #[test]
  fn test_is_all_uppercased_false() {
    assert!(!is_all_uppercased("Abc"));
    assert!(!is_all_uppercased("abC"));
    assert!(!is_all_uppercased("hello"));
  }

  #[test]
  fn test_is_all_uppercased_empty() {
    assert!(is_all_uppercased(""));
  }
}
