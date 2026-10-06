use serde::{Deserialize, Serialize};

/// Composition is used as a substitute for a boolean where context is better placed in the value
/// instead of the parameter name, e.g.: `includeDeprecatedEnumCases = true` vs.
/// `deprecatedEnumCases = .include`.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.Composition` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Composition {
  Include,
  Exclude,
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_composition_include_roundtrip() {
    let json = serde_json::to_string(&Composition::Include).unwrap();
    assert_eq!(json, r#""include""#);
    let parsed: Composition = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed, Composition::Include);
  }

  #[test]
  fn test_composition_exclude_roundtrip() {
    let json = serde_json::to_string(&Composition::Exclude).unwrap();
    assert_eq!(json, r#""exclude""#);
    let parsed: Composition = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed, Composition::Exclude);
  }
}
