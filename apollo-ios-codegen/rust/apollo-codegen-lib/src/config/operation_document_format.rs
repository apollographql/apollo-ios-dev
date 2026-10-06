use serde::de::{self, Visitor};
use serde::{Deserialize, Deserializer, Serialize, Serializer};

bitflags::bitflags! {
  /// How to generate the operation documents for generated operations.
  ///
  /// Mirrors Swift's `ApolloCodegenConfiguration.OperationDocumentFormat` OptionSet.
  #[derive(Debug, Clone, Copy, PartialEq, Eq)]
  pub struct OperationDocumentFormat: u8 {
    /// Include the GraphQL source document for the operation in the generated operation models.
    const DEFINITION = 1;
    /// Include the computed operation identifier hash for use with persisted queries or APQs.
    const OPERATION_ID = 1 << 1;
  }
}

impl<'de> Deserialize<'de> for OperationDocumentFormat {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    struct OperationDocumentFormatVisitor;

    impl<'de> Visitor<'de> for OperationDocumentFormatVisitor {
      type Value = OperationDocumentFormat;

      fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("an array of strings (e.g. [\"definition\", \"operationId\"])")
      }

      fn visit_seq<A: de::SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
        let mut result = OperationDocumentFormat::empty();

        while let Some(value) = seq.next_element::<String>()? {
          match value.as_str() {
            "definition" => result |= OperationDocumentFormat::DEFINITION,
            "operationId" => result |= OperationDocumentFormat::OPERATION_ID,
            _ => {} // Swift silently ignores unknown values
          }
        }

        if result.is_empty() {
          return Err(de::Error::custom(
            "operationDocumentFormat configuration cannot be empty.",
          ));
        }

        Ok(result)
      }
    }

    deserializer.deserialize_seq(OperationDocumentFormatVisitor)
  }
}

impl Serialize for OperationDocumentFormat {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    use serde::ser::SerializeSeq;
    let count = usize::from(self.contains(Self::DEFINITION))
      + usize::from(self.contains(Self::OPERATION_ID));
    let mut seq = serializer.serialize_seq(Some(count))?;

    if self.contains(Self::DEFINITION) {
      seq.serialize_element("definition")?;
    }
    if self.contains(Self::OPERATION_ID) {
      seq.serialize_element("operationId")?;
    }

    seq.end()
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_definition_only() {
    let json = r#"["definition"]"#;
    let parsed: OperationDocumentFormat = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, OperationDocumentFormat::DEFINITION);
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_operation_id_only() {
    let json = r#"["operationId"]"#;
    let parsed: OperationDocumentFormat = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, OperationDocumentFormat::OPERATION_ID);
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_definition_and_operation_id() {
    let json = r#"["definition","operationId"]"#;
    let parsed: OperationDocumentFormat = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      OperationDocumentFormat::DEFINITION | OperationDocumentFormat::OPERATION_ID
    );
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_empty_array_error() {
    let json = r#"[]"#;
    let result = serde_json::from_str::<OperationDocumentFormat>(json);
    assert!(result.is_err());
    let err = result.unwrap_err().to_string();
    assert!(err.contains("cannot be empty"));
  }
}
