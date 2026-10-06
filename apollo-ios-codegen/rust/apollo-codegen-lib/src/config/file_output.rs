use serde::de::{self, MapAccess, Visitor};
use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

use super::module_type::ModuleType;
use super::operations_file_output::OperationsFileOutput;
use super::test_mock_file_output::TestMockFileOutput;

/// The paths and files output by code generation.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.FileOutput` struct.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileOutput {
  /// The local path structure for the generated schema types files.
  pub schema_types: SchemaTypesFileOutput,
  /// The local path structure for the generated operation object files.
  pub operations: OperationsFileOutput,
  /// The local path structure for the test mock operation object files.
  pub test_mocks: TestMockFileOutput,
  /// Legacy field for backwards compatibility with operationIdentifiersPath.
  /// Used only during deserialization to migrate to OperationManifestConfiguration.
  pub(crate) operation_ids_path: Option<String>,
}

/// The local path structure for the generated schema types files.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.SchemaTypesFileOutput` struct.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SchemaTypesFileOutput {
  /// Local path where the generated schema types files should be stored.
  pub path: String,
  /// How to package the schema types for dependency management.
  pub module_type: ModuleType,
}

impl SchemaTypesFileOutput {
  /// Returns `true` if the schema types are in a module (SPM or Other).
  /// Mirrors Swift's `SchemaTypesFileOutput.isInModule` computed property.
  pub fn is_in_module(&self) -> bool {
    matches!(self.module_type, ModuleType::SwiftPackage { .. } | ModuleType::Other)
  }
}

// Custom Deserialize for FileOutput to handle legacy `operationIdentifiersPath` key
// while rejecting other unknown keys.
impl<'de> Deserialize<'de> for FileOutput {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    struct FileOutputVisitor;

    impl<'de> Visitor<'de> for FileOutputVisitor {
      type Value = FileOutput;

      fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("a FileOutput object")
      }

      fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let mut schema_types: Option<SchemaTypesFileOutput> = None;
        let mut operations: Option<OperationsFileOutput> = None;
        let mut test_mocks: Option<TestMockFileOutput> = None;
        let mut operation_ids_path: Option<String> = None;

        while let Some(key) = map.next_key::<String>()? {
          match key.as_str() {
            "schemaTypes" => {
              if schema_types.is_some() {
                return Err(de::Error::duplicate_field("schemaTypes"));
              }
              schema_types = Some(map.next_value()?);
            }
            "operations" => {
              if operations.is_some() {
                return Err(de::Error::duplicate_field("operations"));
              }
              operations = Some(map.next_value()?);
            }
            "testMocks" => {
              if test_mocks.is_some() {
                return Err(de::Error::duplicate_field("testMocks"));
              }
              test_mocks = Some(map.next_value()?);
            }
            "operationIdentifiersPath" => {
              if operation_ids_path.is_some() {
                return Err(de::Error::duplicate_field("operationIdentifiersPath"));
              }
              operation_ids_path = Some(map.next_value()?);
            }
            other => {
              return Err(de::Error::custom(format!(
                "Unrecognized key found: {other}"
              )));
            }
          }
        }

        let schema_types =
          schema_types.ok_or_else(|| de::Error::missing_field("schemaTypes"))?;
        let operations = operations.unwrap_or(OperationsFileOutput::InSchemaModule);
        let test_mocks = test_mocks.unwrap_or(TestMockFileOutput::None);

        Ok(FileOutput {
          schema_types,
          operations,
          test_mocks,
          operation_ids_path,
        })
      }
    }

    deserializer.deserialize_map(FileOutputVisitor)
  }
}

impl Serialize for FileOutput {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    let mut map = serializer.serialize_map(Some(3))?;
    map.serialize_entry("schemaTypes", &self.schema_types)?;
    map.serialize_entry("operations", &self.operations)?;
    map.serialize_entry("testMocks", &self.test_mocks)?;
    // Never serialize the legacy operationIdentifiersPath
    map.end()
  }
}
