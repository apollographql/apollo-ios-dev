use serde::de::{self, Visitor};
use serde::{Deserialize, Deserializer, Serialize, Serializer};

bitflags::bitflags! {
  /// Configuration for which merged fields and named fragment accessors are generated.
  ///
  /// Mirrors Swift's `ApolloCodegenConfiguration.FieldMerging` OptionSet.
  #[derive(Debug, Clone, Copy, PartialEq, Eq)]
  pub struct FieldMerging: u8 {
    /// Merges fields and fragment accessors from the selection set's direct ancestors.
    const ANCESTORS = 1;
    /// Merges fields and fragment accessors from sibling inline fragments.
    const SIBLINGS = 1 << 1;
    /// Merges fields and fragment accessors from named fragments spread into the selection set.
    const NAMED_FRAGMENTS = 1 << 2;
    /// Merges all possible fields and fragment accessors from all sources.
    const ALL = Self::ANCESTORS.bits() | Self::SIBLINGS.bits() | Self::NAMED_FRAGMENTS.bits();
  }
}

impl<'de> Deserialize<'de> for FieldMerging {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    struct FieldMergingVisitor;

    impl<'de> Visitor<'de> for FieldMergingVisitor {
      type Value = FieldMerging;

      fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("an array of strings (e.g. [\"all\"] or [\"ancestors\", \"siblings\"])")
      }

      fn visit_seq<A: de::SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
        let mut result = FieldMerging::empty();

        while let Some(value) = seq.next_element::<String>()? {
          match value.as_str() {
            "all" => {
              return Ok(FieldMerging::ALL);
            }
            "ancestors" => result |= FieldMerging::ANCESTORS,
            "siblings" => result |= FieldMerging::SIBLINGS,
            "namedFragments" => result |= FieldMerging::NAMED_FRAGMENTS,
            other => {
              return Err(de::Error::custom(format!(
                "Unrecognized value: {other}"
              )));
            }
          }
        }

        Ok(result)
      }
    }

    deserializer.deserialize_seq(FieldMergingVisitor)
  }
}

impl Serialize for FieldMerging {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    use serde::ser::SerializeSeq;

    // If all flags are set, emit ["all"] (matching Swift's exact behavior)
    if *self == Self::ALL {
      let mut seq = serializer.serialize_seq(Some(1))?;
      seq.serialize_element("all")?;
      return seq.end();
    }

    let count = usize::from(self.contains(Self::ANCESTORS))
      + usize::from(self.contains(Self::SIBLINGS))
      + usize::from(self.contains(Self::NAMED_FRAGMENTS));
    let mut seq = serializer.serialize_seq(Some(count))?;

    if self.contains(Self::ANCESTORS) {
      seq.serialize_element("ancestors")?;
    }
    if self.contains(Self::SIBLINGS) {
      seq.serialize_element("siblings")?;
    }
    if self.contains(Self::NAMED_FRAGMENTS) {
      seq.serialize_element("namedFragments")?;
    }

    seq.end()
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_field_merging_all_serializes_as_all() {
    let fm = FieldMerging::ALL;
    let json = serde_json::to_string(&fm).unwrap();
    assert_eq!(json, r#"["all"]"#);
  }

  #[test]
  fn test_field_merging_all_deserialize() {
    let json = r#"["all"]"#;
    let parsed: FieldMerging = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, FieldMerging::ALL);
  }

  #[test]
  fn test_field_merging_individual_flags() {
    let json = r#"["ancestors","siblings"]"#;
    let parsed: FieldMerging = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, FieldMerging::ANCESTORS | FieldMerging::SIBLINGS);
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_field_merging_all_individual_flags_serializes_as_all() {
    // When all three individual flags are set, it should serialize as ["all"]
    let fm = FieldMerging::ANCESTORS | FieldMerging::SIBLINGS | FieldMerging::NAMED_FRAGMENTS;
    let json = serde_json::to_string(&fm).unwrap();
    assert_eq!(json, r#"["all"]"#);
  }

  #[test]
  fn test_field_merging_empty() {
    let json = r#"[]"#;
    let parsed: FieldMerging = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, FieldMerging::empty());
  }

  #[test]
  fn test_field_merging_unknown_value_error() {
    let json = r#"["unknown"]"#;
    let result = serde_json::from_str::<FieldMerging>(json);
    assert!(result.is_err());
  }
}
