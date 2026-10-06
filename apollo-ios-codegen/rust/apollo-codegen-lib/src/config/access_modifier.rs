use serde::{Deserialize, Serialize};

/// Swift access control configuration.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.AccessModifier` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AccessModifier {
  /// Enable entities to be used within any source file from their defining module, and also in
  /// a source file from another module that imports the defining module.
  Public,
  /// Enable entities to be used within any source file from their defining module, but not in
  /// any source file outside of that module.
  Internal,
}

pub fn default_internal() -> AccessModifier {
  AccessModifier::Internal
}

pub fn default_public() -> AccessModifier {
  AccessModifier::Public
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_access_modifier_public_roundtrip() {
    let json = serde_json::to_string(&AccessModifier::Public).unwrap();
    assert_eq!(json, r#""public""#);
    let parsed: AccessModifier = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed, AccessModifier::Public);
  }

  #[test]
  fn test_access_modifier_internal_roundtrip() {
    let json = serde_json::to_string(&AccessModifier::Internal).unwrap();
    assert_eq!(json, r#""internal""#);
    let parsed: AccessModifier = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed, AccessModifier::Internal);
  }
}
