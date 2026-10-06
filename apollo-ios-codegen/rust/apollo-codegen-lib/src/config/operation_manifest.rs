use serde::{Deserialize, Serialize};

/// Configuration for generating an operation manifest for use with persisted queries.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.OperationManifestConfiguration` struct.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationManifestConfiguration {
  /// Local path where the generated operation manifest file should be written.
  pub path: String,

  /// The version format to use when generating the operation manifest.
  /// Defaults to `PersistedQueries`.
  #[serde(default = "default_version")]
  pub version: Version,

  /// If set to `true` will generate the operation manifest every time code generation is run.
  /// Defaults to `false`.
  #[serde(default)]
  pub generate_manifest_on_code_generation: bool,
}

fn default_version() -> Version {
  Version::PersistedQueries
}

/// The version format for the operation manifest.
///
/// Mirrors Swift's `OperationManifestConfiguration.Version` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Version {
  /// Generates an operation manifest for use with persisted queries.
  PersistedQueries,
  /// Generates an operation manifest in the legacy safelisting format.
  Legacy,
}
