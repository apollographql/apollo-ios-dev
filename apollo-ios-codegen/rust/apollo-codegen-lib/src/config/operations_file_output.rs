use serde::de::{self, MapAccess, Visitor};
use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

use super::access_modifier::AccessModifier;

/// The local path structure for the generated operation object files.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.OperationsFileOutput` enum.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OperationsFileOutput {
  /// All operation object files will be located in the module with the schema types.
  InSchemaModule,
  /// Operation object files will be co-located relative to the defining operation `.graphql`
  /// file. `access_modifier` defaults to `Public`.
  Relative {
    subpath: Option<String>,
    access_modifier: AccessModifier,
  },
  /// All operation object files will be located in the specified `path`.
  /// `access_modifier` defaults to `Public`.
  Absolute {
    path: String,
    access_modifier: AccessModifier,
  },
}

impl OperationsFileOutput {
  /// Returns `true` if operations are output to the schema types module.
  /// Mirrors Swift's `OperationsFileOutput.isInModule` computed property.
  ///
  /// In Swift: `inSchemaModule -> true`, `relative/absolute -> false`.
  pub fn is_in_module(&self) -> bool {
    matches!(self, OperationsFileOutput::InSchemaModule)
  }
}

impl<'de> Deserialize<'de> for OperationsFileOutput {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    struct OperationsFileOutputVisitor;

    impl<'de> Visitor<'de> for OperationsFileOutputVisitor {
      type Value = OperationsFileOutput;

      fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("an OperationsFileOutput object with one key: inSchemaModule, relative, or absolute")
      }

      fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let key: String = map
          .next_key()?
          .ok_or_else(|| de::Error::custom("Invalid number of keys found, expected one."))?;

        match key.as_str() {
          "inSchemaModule" => {
            let _: serde_json::Value = map.next_value()?;
            Ok(OperationsFileOutput::InSchemaModule)
          }
          "relative" => {
            #[derive(Deserialize)]
            struct Inner {
              subpath: Option<String>,
              #[serde(rename = "accessModifier", default = "crate::config::access_modifier::default_public")]
              access_modifier: AccessModifier,
            }
            let inner: Inner = map.next_value()?;
            Ok(OperationsFileOutput::Relative {
              subpath: inner.subpath,
              access_modifier: inner.access_modifier,
            })
          }
          "absolute" => {
            #[derive(Deserialize)]
            struct Inner {
              path: String,
              #[serde(rename = "accessModifier", default = "crate::config::access_modifier::default_public")]
              access_modifier: AccessModifier,
            }
            let inner: Inner = map.next_value()?;
            Ok(OperationsFileOutput::Absolute {
              path: inner.path,
              access_modifier: inner.access_modifier,
            })
          }
          other => Err(de::Error::unknown_variant(
            other,
            &["inSchemaModule", "relative", "absolute"],
          )),
        }
      }
    }

    deserializer.deserialize_map(OperationsFileOutputVisitor)
  }
}

impl Serialize for OperationsFileOutput {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    match self {
      OperationsFileOutput::InSchemaModule => {
        let mut map = serializer.serialize_map(Some(1))?;
        map.serialize_entry("inSchemaModule", &serde_json::Map::new())?;
        map.end()
      }
      OperationsFileOutput::Relative {
        subpath,
        access_modifier,
      } => {
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Inner<'a> {
          #[serde(skip_serializing_if = "Option::is_none")]
          subpath: &'a Option<String>,
          access_modifier: &'a AccessModifier,
        }
        let mut map = serializer.serialize_map(Some(1))?;
        map.serialize_entry(
          "relative",
          &Inner {
            subpath,
            access_modifier,
          },
        )?;
        map.end()
      }
      OperationsFileOutput::Absolute {
        path,
        access_modifier,
      } => {
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Inner<'a> {
          path: &'a str,
          access_modifier: &'a AccessModifier,
        }
        let mut map = serializer.serialize_map(Some(1))?;
        map.serialize_entry(
          "absolute",
          &Inner {
            path,
            access_modifier,
          },
        )?;
        map.end()
      }
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_operations_in_schema_module_roundtrip() {
    let json = r#"{"inSchemaModule":{}}"#;
    let parsed: OperationsFileOutput = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, OperationsFileOutput::InSchemaModule);
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_operations_relative_with_subpath() {
    let json = r#"{"relative":{"subpath":"Generated","accessModifier":"public"}}"#;
    let parsed: OperationsFileOutput = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      OperationsFileOutput::Relative {
        subpath: Some("Generated".to_string()),
        access_modifier: AccessModifier::Public,
      }
    );
  }

  #[test]
  fn test_operations_relative_default_access_modifier() {
    let json = r#"{"relative":{}}"#;
    let parsed: OperationsFileOutput = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      OperationsFileOutput::Relative {
        subpath: None,
        access_modifier: AccessModifier::Public,
      }
    );
  }

  #[test]
  fn test_operations_absolute_roundtrip() {
    let json = r#"{"absolute":{"path":"/absolute/path","accessModifier":"internal"}}"#;
    let parsed: OperationsFileOutput = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      OperationsFileOutput::Absolute {
        path: "/absolute/path".to_string(),
        access_modifier: AccessModifier::Internal,
      }
    );
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }
}
