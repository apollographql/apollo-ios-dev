use indexmap::IndexMap;
use serde::de::{self, MapAccess, Visitor};
use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// Customization options applied to the schema during code generation.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.SchemaCustomization` struct.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SchemaCustomization {
  /// Dictionary with Keys representing the types being renamed/customized.
  pub custom_type_names: IndexMap<String, CustomSchemaTypeName>,
}

impl Default for SchemaCustomization {
  fn default() -> Self {
    Self {
      custom_type_names: IndexMap::new(),
    }
  }
}

// Valid keys for SchemaCustomization.
const VALID_SCHEMA_CUSTOMIZATION_KEYS: &[&str] = &["customTypeNames"];

impl<'de> Deserialize<'de> for SchemaCustomization {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    struct SchemaCustomizationVisitor;

    impl<'de> Visitor<'de> for SchemaCustomizationVisitor {
      type Value = SchemaCustomization;

      fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("a SchemaCustomization object")
      }

      fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let mut custom_type_names: Option<IndexMap<String, CustomSchemaTypeName>> = None;

        while let Some(key) = map.next_key::<String>()? {
          if !VALID_SCHEMA_CUSTOMIZATION_KEYS.contains(&key.as_str()) {
            return Err(de::Error::custom(format!(
              "Unrecognized key found: {key}"
            )));
          }

          match key.as_str() {
            "customTypeNames" => {
              custom_type_names = Some(map.next_value()?);
            }
            _ => unreachable!(),
          }
        }

        Ok(SchemaCustomization {
          custom_type_names: custom_type_names.unwrap_or_default(),
        })
      }
    }

    deserializer.deserialize_map(SchemaCustomizationVisitor)
  }
}

impl Serialize for SchemaCustomization {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    let mut map = serializer.serialize_map(Some(1))?;
    map.serialize_entry("customTypeNames", &self.custom_type_names)?;
    map.end()
  }
}

/// A custom schema type name configuration.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.SchemaCustomization.CustomSchemaTypeName` enum.
///
/// Supports three JSON formats:
/// - Plain string: `"CustomName"` -> `Type { name }`
/// - Tagged object for type: `{"type": {"name": "X"}}` -> `Type { name }`
/// - Tagged object for enum: `{"enum": {"name": "X", "cases": {"A": "B"}}}` -> `Enum { name, cases }`
/// - Tagged object for inputObject: `{"inputObject": {"name": "X", "fields": {"A": "B"}}}` -> `InputObject { name, fields }`
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CustomSchemaTypeName {
  /// A simple type rename.
  Type { name: String },
  /// An enum customization with optional name and optional case mapping.
  Enum {
    name: Option<String>,
    cases: Option<IndexMap<String, String>>,
  },
  /// An input object customization with optional name and optional field mapping.
  InputObject {
    name: Option<String>,
    fields: Option<IndexMap<String, String>>,
  },
}

impl<'de> Deserialize<'de> for CustomSchemaTypeName {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    // First try to deserialize as a JSON Value to determine the format
    let value: serde_json::Value = serde_json::Value::deserialize(deserializer)?;

    match &value {
      // Plain string -> Type
      serde_json::Value::String(s) => {
        if s.is_empty() {
          return Err(de::Error::custom(
            "No customization data was provided, customization will be ignored.",
          ));
        }
        Ok(CustomSchemaTypeName::Type { name: s.clone() })
      }
      // Tagged object
      serde_json::Value::Object(obj) => {
        if let Some(type_val) = obj.get("type") {
          let inner: TypeInner =
            serde_json::from_value(type_val.clone()).map_err(de::Error::custom)?;
          let name = decode_if_present_or_empty(inner.name);
          match name {
            Some(name) => Ok(CustomSchemaTypeName::Type { name }),
            None => Err(de::Error::custom(
              "No customization data was provided, customization will be ignored.",
            )),
          }
        } else if let Some(enum_val) = obj.get("enum") {
          let inner: EnumInner =
            serde_json::from_value(enum_val.clone()).map_err(de::Error::custom)?;
          let name = decode_if_present_or_empty(inner.name);
          let cases = decode_map_if_present_or_empty(inner.cases);

          if name.is_none() && cases.is_none() {
            return Err(de::Error::custom(
              "No customization data was provided, customization will be ignored.",
            ));
          }

          // Optimization: if name-only (no cases), store as Type
          if let Some(ref name_val) = name {
            if cases.is_none() {
              return Ok(CustomSchemaTypeName::Type {
                name: name_val.clone(),
              });
            }
          }

          Ok(CustomSchemaTypeName::Enum { name, cases })
        } else if let Some(input_val) = obj.get("inputObject") {
          let inner: InputObjectInner =
            serde_json::from_value(input_val.clone()).map_err(de::Error::custom)?;
          let name = decode_if_present_or_empty(inner.name);
          let fields = decode_map_if_present_or_empty(inner.fields);

          if name.is_none() && fields.is_none() {
            return Err(de::Error::custom(
              "No customization data was provided, customization will be ignored.",
            ));
          }

          // Optimization: if name-only (no fields), store as Type
          if let Some(ref name_val) = name {
            if fields.is_none() {
              return Ok(CustomSchemaTypeName::Type {
                name: name_val.clone(),
              });
            }
          }

          Ok(CustomSchemaTypeName::InputObject { name, fields })
        } else {
          Err(de::Error::custom(
            "Unable to decode custom schema type name: expected 'type', 'enum', or 'inputObject' key.",
          ))
        }
      }
      _ => Err(de::Error::custom(
        "Unable to decode custom schema type name: expected string or object.",
      )),
    }
  }
}

#[derive(Deserialize)]
struct TypeInner {
  name: Option<String>,
}

#[derive(Deserialize)]
struct EnumInner {
  name: Option<String>,
  cases: Option<IndexMap<String, String>>,
}

#[derive(Deserialize)]
struct InputObjectInner {
  name: Option<String>,
  fields: Option<IndexMap<String, String>>,
}

fn decode_if_present_or_empty(value: Option<String>) -> Option<String> {
  value.and_then(|s| if s.is_empty() { None } else { Some(s) })
}

fn decode_map_if_present_or_empty(
  value: Option<IndexMap<String, String>>,
) -> Option<IndexMap<String, String>> {
  value.and_then(|m| if m.is_empty() { None } else { Some(m) })
}

impl Serialize for CustomSchemaTypeName {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    match self {
      CustomSchemaTypeName::Type { name } => {
        // Serialize as a plain string
        serializer.serialize_str(name)
      }
      CustomSchemaTypeName::Enum { name, cases } => {
        // If cases is None, serialize as plain string (name only)
        if cases.is_none() {
          if let Some(name) = name {
            return serializer.serialize_str(name);
          }
        }
        let mut outer = serializer.serialize_map(Some(1))?;
        #[derive(Serialize)]
        struct Inner<'a> {
          #[serde(skip_serializing_if = "Option::is_none")]
          name: &'a Option<String>,
          #[serde(skip_serializing_if = "Option::is_none")]
          cases: &'a Option<IndexMap<String, String>>,
        }
        outer.serialize_entry("enum", &Inner { name, cases })?;
        outer.end()
      }
      CustomSchemaTypeName::InputObject { name, fields } => {
        // If fields is None, serialize as plain string (name only)
        if name.is_some() && fields.is_none() {
          if let Some(name) = name {
            return serializer.serialize_str(name);
          }
        }
        let mut outer = serializer.serialize_map(Some(1))?;
        #[derive(Serialize)]
        struct Inner<'a> {
          #[serde(skip_serializing_if = "Option::is_none")]
          name: &'a Option<String>,
          #[serde(skip_serializing_if = "Option::is_none")]
          fields: &'a Option<IndexMap<String, String>>,
        }
        outer.serialize_entry("inputObject", &Inner { name, fields })?;
        outer.end()
      }
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_custom_schema_type_name_plain_string() {
    let json = r#""CustomName""#;
    let parsed: CustomSchemaTypeName = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      CustomSchemaTypeName::Type {
        name: "CustomName".to_string()
      }
    );
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_custom_schema_type_name_tagged_type() {
    let json = r#"{"type":{"name":"RenamedType"}}"#;
    let parsed: CustomSchemaTypeName = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      CustomSchemaTypeName::Type {
        name: "RenamedType".to_string()
      }
    );
  }

  #[test]
  fn test_custom_schema_type_name_enum_with_cases() {
    let json = r#"{"enum":{"name":"MyEnum","cases":{"A":"B"}}}"#;
    let parsed: CustomSchemaTypeName = serde_json::from_str(json).unwrap();
    let mut cases = IndexMap::new();
    cases.insert("A".to_string(), "B".to_string());
    assert_eq!(
      parsed,
      CustomSchemaTypeName::Enum {
        name: Some("MyEnum".to_string()),
        cases: Some(cases),
      }
    );
  }

  #[test]
  fn test_custom_schema_type_name_enum_name_only_optimized_to_type() {
    // Enum with only name (no cases) should be stored as Type
    let json = r#"{"enum":{"name":"MyEnum"}}"#;
    let parsed: CustomSchemaTypeName = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      CustomSchemaTypeName::Type {
        name: "MyEnum".to_string()
      }
    );
  }

  #[test]
  fn test_custom_schema_type_name_input_object_with_fields() {
    let json = r#"{"inputObject":{"name":"MyInput","fields":{"fieldA":"renamedA"}}}"#;
    let parsed: CustomSchemaTypeName = serde_json::from_str(json).unwrap();
    let mut fields = IndexMap::new();
    fields.insert("fieldA".to_string(), "renamedA".to_string());
    assert_eq!(
      parsed,
      CustomSchemaTypeName::InputObject {
        name: Some("MyInput".to_string()),
        fields: Some(fields),
      }
    );
  }

  #[test]
  fn test_custom_schema_type_name_input_object_name_only_optimized_to_type() {
    let json = r#"{"inputObject":{"name":"MyInput"}}"#;
    let parsed: CustomSchemaTypeName = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      CustomSchemaTypeName::Type {
        name: "MyInput".to_string()
      }
    );
  }

  #[test]
  fn test_custom_schema_type_name_empty_string_error() {
    let json = r#""""#;
    let result = serde_json::from_str::<CustomSchemaTypeName>(json);
    assert!(result.is_err());
  }

  #[test]
  fn test_schema_customization_default() {
    let sc = SchemaCustomization::default();
    assert!(sc.custom_type_names.is_empty());
  }

  #[test]
  fn test_schema_customization_roundtrip() {
    let json = r#"{"customTypeNames":{"MyType":"RenamedType"}}"#;
    let parsed: SchemaCustomization = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed.custom_type_names.get("MyType"),
      Some(&CustomSchemaTypeName::Type {
        name: "RenamedType".to_string()
      })
    );
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }
}
