use serde::{Deserialize, Serialize};

use super::field_merging::FieldMerging;

/// Allows users to enable experimental features.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.ExperimentalFeatures` struct.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExperimentalFeatures {
    /// Determines which merged fields and named fragment accessors are generated.
    /// Defaults to `ALL`.
    #[serde(default = "default_field_merging")]
    pub field_merging: FieldMerging,

    /// If enabled, the generated operations will be transformed using a method
    /// that attempts to maintain compatibility with the legacy behavior from
    /// apollo-tooling for registering persisted operations to a safelist.
    #[serde(default)]
    pub legacy_safelisting_compatible_operations: bool,
}

impl Default for ExperimentalFeatures {
    fn default() -> Self {
        Self {
            field_merging: FieldMerging::ALL,
            legacy_safelisting_compatible_operations: false,
        }
    }
}

fn default_field_merging() -> FieldMerging {
    FieldMerging::ALL
}
