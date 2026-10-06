//! Emulates the joining semantics of Swift's `TemplateString` `forEachIn:` / sequence
//! interpolations (`TemplateString.swift`).
//!
//! Elements are appended with `separator` between them, but an empty element contributes
//! nothing until the first non-empty element has been appended; after that every element,
//! empty or not, is preceded by the separator. This is why Swift templates that map every
//! item to "something or empty" emit one blank line per trailing empty item.

/// Joins `elements` exactly like `TemplateString.StringInterpolation.appendInterpolation(forEachIn:)`.
pub fn for_each_in_joined<I, S>(elements: I, separator: &str) -> String
where
  I: IntoIterator<Item = S>,
  S: AsRef<str>,
{
  let mut result = String::new();
  for element in elements {
    let element = element.as_ref();
    if result.is_empty() {
      result.push_str(element);
    } else {
      result.push_str(separator);
      result.push_str(element);
    }
  }
  result
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn leading_empty_elements_are_dropped_but_trailing_ones_add_separators() {
    assert_eq!(for_each_in_joined(["", "", "a", "", ""], "\n"), "a\n\n");
    assert_eq!(for_each_in_joined(["a", "b"], ",\n"), "a,\nb");
    assert_eq!(for_each_in_joined(["", ""], "\n"), "");
  }
}
