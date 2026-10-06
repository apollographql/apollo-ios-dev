use std::collections::BTreeSet;

use serde::de::{self, MapAccess, Visitor};
use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// Configuration for which generated selection sets should include generated initializers.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.SelectionSetInitializers` struct.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectionSetInitializers {
  /// Option to generate initializers for all operations.
  pub operations: bool,
  /// Option to generate initializers for all named fragments.
  pub named_fragments: bool,
  /// Named definitions to generate initializers for.
  pub definitions: BTreeSet<String>,
}

impl SelectionSetInitializers {
  /// Creates an empty SelectionSetInitializers (the default).
  pub fn empty() -> Self {
    Self {
      operations: false,
      named_fragments: false,
      definitions: BTreeSet::new(),
    }
  }
}

// Valid keys for SelectionSetInitializers (current + legacy).
const VALID_KEYS: &[&str] = &[
  "operations",
  "namedFragments",
  "definitionsNamed",
  "localCacheMutations", // deprecated, accepted but ignored
];

impl<'de> Deserialize<'de> for SelectionSetInitializers {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    struct SelectionSetInitializersVisitor;

    impl<'de> Visitor<'de> for SelectionSetInitializersVisitor {
      type Value = SelectionSetInitializers;

      fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("a SelectionSetInitializers object")
      }

      fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let mut operations = false;
        let mut named_fragments = false;
        let mut definitions = BTreeSet::new();

        while let Some(key) = map.next_key::<String>()? {
          if !VALID_KEYS.contains(&key.as_str()) {
            return Err(de::Error::custom(format!(
              "Unrecognized key found: {key}"
            )));
          }

          match key.as_str() {
            "operations" => {
              let val: bool = map.next_value()?;
              if val {
                operations = true;
              }
            }
            "namedFragments" => {
              let val: bool = map.next_value()?;
              if val {
                named_fragments = true;
              }
            }
            "definitionsNamed" => {
              definitions = map.next_value()?;
            }
            "localCacheMutations" => {
              // Legacy key: accepted but ignored.
              let _: serde_json::Value = map.next_value()?;
            }
            _ => unreachable!(),
          }
        }

        Ok(SelectionSetInitializers {
          operations,
          named_fragments,
          definitions,
        })
      }
    }

    deserializer.deserialize_map(SelectionSetInitializersVisitor)
  }
}

impl Serialize for SelectionSetInitializers {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    // Only emit keys that have non-default values
    let count = usize::from(self.operations)
      + usize::from(self.named_fragments)
      + usize::from(!self.definitions.is_empty());
    let mut map = serializer.serialize_map(Some(count))?;

    if self.operations {
      map.serialize_entry("operations", &true)?;
    }
    if self.named_fragments {
      map.serialize_entry("namedFragments", &true)?;
    }
    if !self.definitions.is_empty() {
      // Serialize as a sorted array
      let sorted: Vec<&String> = self.definitions.iter().collect();
      map.serialize_entry("definitionsNamed", &sorted)?;
    }

    map.end()
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_empty_object() {
    let json = r#"{}"#;
    let parsed: SelectionSetInitializers = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, SelectionSetInitializers::empty());
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_operations_only() {
    let json = r#"{"operations":true}"#;
    let parsed: SelectionSetInitializers = serde_json::from_str(json).unwrap();
    assert!(parsed.operations);
    assert!(!parsed.named_fragments);
    assert!(parsed.definitions.is_empty());
  }

  #[test]
  fn test_with_definitions_named() {
    let json = r#"{"namedFragments":true,"definitionsNamed":["Operation1","Operation2"]}"#;
    let parsed: SelectionSetInitializers = serde_json::from_str(json).unwrap();
    assert!(parsed.named_fragments);
    assert!(parsed.definitions.contains("Operation1"));
    assert!(parsed.definitions.contains("Operation2"));
  }

  #[test]
  fn test_legacy_local_cache_mutations_accepted() {
    let json = r#"{"localCacheMutations":true}"#;
    let parsed: SelectionSetInitializers = serde_json::from_str(json).unwrap();
    // Legacy key is accepted but ignored
    assert!(!parsed.operations);
    assert!(!parsed.named_fragments);
  }

  #[test]
  fn test_unknown_key_rejected() {
    let json = r#"{"unknownKey":true}"#;
    let result = serde_json::from_str::<SelectionSetInitializers>(json);
    assert!(result.is_err());
  }

  #[test]
  fn test_roundtrip_all() {
    let ssi = SelectionSetInitializers {
      operations: true,
      named_fragments: true,
      definitions: BTreeSet::new(),
    };
    let json = serde_json::to_string(&ssi).unwrap();
    let parsed: SelectionSetInitializers = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed, ssi);
  }
}
