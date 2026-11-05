use serde::{Deserialize, Serialize};

/// The input paths and files required for code generation.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.FileInput` struct.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileInput {
    /// An array of path matching pattern strings used to find GraphQL schema
    /// files to be included for code generation.
    #[serde(default = "default_schema_search_paths")]
    pub schema_search_paths: Vec<String>,

    /// An array of path matching pattern strings used to find GraphQL
    /// operation files to be included for code generation.
    #[serde(default = "default_operation_search_paths")]
    pub operation_search_paths: Vec<String>,
}

impl Default for FileInput {
    fn default() -> Self {
        Self {
            schema_search_paths: default_schema_search_paths(),
            operation_search_paths: default_operation_search_paths(),
        }
    }
}

fn default_schema_search_paths() -> Vec<String> {
    vec!["**/*.graphqls".to_string()]
}

fn default_operation_search_paths() -> Vec<String> {
    vec!["**/*.graphql".to_string()]
}
