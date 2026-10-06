//! Configuration types for the Apollo codegen configuration system.
//!
//! This module contains the complete `ApolloCodegenConfiguration` type hierarchy,
//! mirroring Swift's `ApolloCodegenConfiguration` and all nested types.
//! All types support serde JSON serialization/deserialization compatible with
//! `apollo-codegen-config.json` files produced by Swift codegen.

pub mod access_modifier;
pub mod composition;
pub mod conversion_strategies;
pub mod deprecated;
pub mod experimental_features;
pub mod field_merging;
pub mod file_input;
pub mod file_output;
pub mod module_type;
pub mod operation_document_format;
pub mod operation_manifest;
pub mod operations_file_output;
pub mod output_options;
pub mod schema_customization;
pub mod schema_download;
pub mod selection_set_initializers;
pub mod swift_keywords;
pub mod test_mock_file_output;
pub mod validation;

// Re-export all public types at the config module level.
pub use access_modifier::AccessModifier;
pub use composition::Composition;
pub use conversion_strategies::{ConversionStrategies, EnumCases, FieldAccessors, InputObjects};
pub use deprecated::{APQConfig, CaseConversionStrategy, QueryStringLiteralFormat};
pub use experimental_features::ExperimentalFeatures;
pub use field_merging::FieldMerging;
pub use file_input::FileInput;
pub use file_output::{FileOutput, SchemaTypesFileOutput};
pub use module_type::ModuleType;
pub use operation_document_format::OperationDocumentFormat;
pub use operation_manifest::{OperationManifestConfiguration, Version};
pub use operations_file_output::OperationsFileOutput;
pub use output_options::OutputOptions;
pub use schema_customization::{CustomSchemaTypeName, SchemaCustomization};
pub use schema_download::{
  ApolloSchemaDownloadConfiguration, DownloadMethod, HTTPHeader, HTTPMethod, OutputFormat,
};
pub use selection_set_initializers::SelectionSetInitializers;
pub use test_mock_file_output::TestMockFileOutput;

use serde::de::{self, MapAccess, Visitor};
use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// A configuration object that defines behavior for code generation.
///
/// Mirrors Swift's `ApolloCodegenConfiguration` struct.
#[derive(Debug, Clone, PartialEq)]
pub struct ApolloCodegenConfiguration {
  /// Name used to scope the generated schema type files.
  pub schema_namespace: String,
  /// The input files required for code generation.
  pub input: FileInput,
  /// The paths and files output by code generation.
  pub output: FileOutput,
  /// Rules and options to customize the generated code.
  pub options: OutputOptions,
  /// Allows users to enable experimental features.
  pub experimental_features: ExperimentalFeatures,
  /// Schema download configuration.
  pub schema_download: Option<ApolloSchemaDownloadConfiguration>,
  /// Configuration for generating an operation manifest for use with persisted queries.
  pub operation_manifest: Option<OperationManifestConfiguration>,
}

// Valid keys for the top-level config (current + legacy).
const VALID_TOP_LEVEL_KEYS: &[&str] = &[
  "schemaName",
  "schemaNamespace",
  "input",
  "output",
  "options",
  "experimentalFeatures",
  "schemaDownloadConfiguration",
  "schemaDownload",
  "operationManifest",
];

impl<'de> Deserialize<'de> for ApolloCodegenConfiguration {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    struct ApolloCodegenConfigurationVisitor;

    impl<'de> Visitor<'de> for ApolloCodegenConfigurationVisitor {
      type Value = ApolloCodegenConfiguration;

      fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("an ApolloCodegenConfiguration object")
      }

      fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let mut schema_name: Option<String> = None;
        let mut schema_namespace: Option<String> = None;
        let mut input: Option<FileInput> = None;
        let mut output: Option<FileOutput> = None;
        let mut options: Option<OutputOptions> = None;
        let mut experimental_features: Option<ExperimentalFeatures> = None;
        let mut schema_download_configuration: Option<ApolloSchemaDownloadConfiguration> = None;
        let mut schema_download: Option<ApolloSchemaDownloadConfiguration> = None;
        let mut operation_manifest: Option<OperationManifestConfiguration> = None;

        while let Some(key) = map.next_key::<String>()? {
          if !VALID_TOP_LEVEL_KEYS.contains(&key.as_str()) {
            return Err(de::Error::custom(format!(
              "Unrecognized key found: {key}"
            )));
          }

          match key.as_str() {
            "schemaName" => {
              schema_name = Some(map.next_value()?);
            }
            "schemaNamespace" => {
              schema_namespace = Some(map.next_value()?);
            }
            "input" => {
              input = Some(map.next_value()?);
            }
            "output" => {
              output = Some(map.next_value()?);
            }
            "options" => {
              options = Some(map.next_value()?);
            }
            "experimentalFeatures" => {
              experimental_features = Some(map.next_value()?);
            }
            "schemaDownloadConfiguration" => {
              schema_download_configuration = Some(map.next_value()?);
            }
            "schemaDownload" => {
              schema_download = Some(map.next_value()?);
            }
            "operationManifest" => {
              operation_manifest = Some(map.next_value()?);
            }
            _ => unreachable!(),
          }
        }

        // schemaNamespace: try current key first, fall back to legacy schemaName
        let schema_namespace_value = schema_namespace.or(schema_name).ok_or_else(|| {
          de::Error::custom("Cannot find value for 'schemaNamespace' key")
        })?;

        let input = input.ok_or_else(|| de::Error::missing_field("input"))?;
        let file_output = output.ok_or_else(|| de::Error::missing_field("output"))?;

        // operationManifest: if not present, check legacy operationIdentifiersPath from FileOutput
        let operation_manifest = operation_manifest.or_else(|| {
          file_output.operation_ids_path.as_ref().map(|path| {
            OperationManifestConfiguration {
              path: path.clone(),
              version: operation_manifest::Version::Legacy,
              generate_manifest_on_code_generation: false,
            }
          })
        });

        // schemaDownload: try current key first, fall back to legacy schemaDownloadConfiguration
        let schema_download_value = schema_download.or(schema_download_configuration);

        Ok(ApolloCodegenConfiguration {
          schema_namespace: schema_namespace_value,
          input,
          output: file_output,
          options: options.unwrap_or_default(),
          experimental_features: experimental_features.unwrap_or_default(),
          schema_download: schema_download_value,
          operation_manifest,
        })
      }
    }

    deserializer.deserialize_map(ApolloCodegenConfigurationVisitor)
  }
}

impl Serialize for ApolloCodegenConfiguration {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    // Count required fields + optional fields that are Some
    let count = 5
      + usize::from(self.schema_download.is_some())
      + usize::from(self.operation_manifest.is_some());
    let mut map = serializer.serialize_map(Some(count))?;

    // Always use current key names (never legacy)
    map.serialize_entry("schemaNamespace", &self.schema_namespace)?;
    map.serialize_entry("input", &self.input)?;
    map.serialize_entry("output", &self.output)?;
    map.serialize_entry("options", &self.options)?;
    map.serialize_entry("experimentalFeatures", &self.experimental_features)?;

    if let Some(ref sd) = self.schema_download {
      map.serialize_entry("schemaDownload", sd)?;
    }

    if let Some(ref om) = self.operation_manifest {
      map.serialize_entry("operationManifest", om)?;
    }

    map.end()
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_minimal_config_with_defaults() {
    let json = r#"{
      "schemaNamespace": "MySchema",
      "input": {
        "schemaSearchPaths": ["schema.graphqls"],
        "operationSearchPaths": ["**/*.graphql"]
      },
      "output": {
        "schemaTypes": {
          "path": "./generated",
          "moduleType": {"swiftPackageManager": {}}
        },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"none": {}}
      }
    }"#;
    let parsed: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
    assert_eq!(parsed.schema_namespace, "MySchema");
    assert_eq!(parsed.input.schema_search_paths, vec!["schema.graphqls"]);
    assert_eq!(parsed.options, OutputOptions::default());
    assert_eq!(parsed.experimental_features, ExperimentalFeatures::default());
    assert!(parsed.schema_download.is_none());
    assert!(parsed.operation_manifest.is_none());
  }

  #[test]
  fn test_legacy_schema_name_key() {
    let json = r#"{
      "schemaName": "LegacyName",
      "input": {},
      "output": {
        "schemaTypes": {
          "path": "./gen",
          "moduleType": {"other": {}}
        },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"none": {}}
      }
    }"#;
    let parsed: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
    assert_eq!(parsed.schema_namespace, "LegacyName");
  }

  #[test]
  fn test_legacy_schema_download_configuration_key() {
    let json = r#"{
      "schemaNamespace": "Test",
      "input": {},
      "output": {
        "schemaTypes": {
          "path": "./gen",
          "moduleType": {"other": {}}
        },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"none": {}}
      },
      "schemaDownloadConfiguration": {
        "downloadMethod": {"introspection": {"endpointURL": "http://x.com"}},
        "outputPath": "schema.graphqls"
      }
    }"#;
    let parsed: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
    assert!(parsed.schema_download.is_some());
  }

  #[test]
  fn test_legacy_operation_identifiers_path_migration() {
    let json = r#"{
      "schemaNamespace": "Test",
      "input": {},
      "output": {
        "schemaTypes": {
          "path": "./gen",
          "moduleType": {"other": {}}
        },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"none": {}},
        "operationIdentifiersPath": "/path/to/ids.json"
      }
    }"#;
    let parsed: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
    assert!(parsed.operation_manifest.is_some());
    let manifest = parsed.operation_manifest.unwrap();
    assert_eq!(manifest.path, "/path/to/ids.json");
    assert_eq!(manifest.version, Version::Legacy);
    assert!(!manifest.generate_manifest_on_code_generation);
  }

  #[test]
  fn test_unknown_top_level_key_rejected() {
    let json = r#"{
      "schemaNamespace": "Test",
      "input": {},
      "output": {
        "schemaTypes": {
          "path": "./gen",
          "moduleType": {"other": {}}
        },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"none": {}}
      },
      "unknownKey": true
    }"#;
    let result = serde_json::from_str::<ApolloCodegenConfiguration>(json);
    assert!(result.is_err());
  }

  #[test]
  fn test_serialization_uses_current_keys_only() {
    let config = ApolloCodegenConfiguration {
      schema_namespace: "Test".to_string(),
      input: FileInput::default(),
      output: FileOutput {
        schema_types: SchemaTypesFileOutput {
          path: "./gen".to_string(),
          module_type: ModuleType::Other,
        },
        operations: OperationsFileOutput::InSchemaModule,
        test_mocks: TestMockFileOutput::None,
        operation_ids_path: None,
      },
      options: OutputOptions::default(),
      experimental_features: ExperimentalFeatures::default(),
      schema_download: None,
      operation_manifest: None,
    };
    let json = serde_json::to_string(&config).unwrap();
    // Should contain current key names
    assert!(json.contains("schemaNamespace"));
    // Should NOT contain legacy key names (check with quotes to avoid substring matches)
    assert!(!json.contains("\"schemaName\""));
    assert!(!json.contains("schemaDownloadConfiguration"));
    assert!(!json.contains("operationIdentifiersPath"));
    assert!(!json.contains("apqs"));
  }

  #[test]
  fn test_output_options_with_legacy_apqs() {
    let json = r#"{"apqs": "automaticallyPersist"}"#;
    let parsed: OutputOptions = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed.operation_document_format,
      OperationDocumentFormat::DEFINITION | OperationDocumentFormat::OPERATION_ID
    );
  }

  #[test]
  fn test_output_options_legacy_query_string_literal_format_accepted() {
    let json = r#"{"queryStringLiteralFormat": "singleLine"}"#;
    let parsed: OutputOptions = serde_json::from_str(json).unwrap();
    // Value is accepted but ignored, all other fields use defaults
    assert_eq!(parsed, OutputOptions::default());
  }

  #[test]
  fn test_file_input_defaults() {
    let fi = FileInput::default();
    assert_eq!(fi.schema_search_paths, vec!["**/*.graphqls"]);
    assert_eq!(fi.operation_search_paths, vec!["**/*.graphql"]);
  }

  #[test]
  fn test_operation_manifest_roundtrip() {
    let json = r#"{"path":"/out/manifest.json","version":"persistedQueries","generateManifestOnCodeGeneration":false}"#;
    let parsed: OperationManifestConfiguration = serde_json::from_str(json).unwrap();
    assert_eq!(parsed.path, "/out/manifest.json");
    assert_eq!(parsed.version, Version::PersistedQueries);
    assert!(!parsed.generate_manifest_on_code_generation);
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }
}
