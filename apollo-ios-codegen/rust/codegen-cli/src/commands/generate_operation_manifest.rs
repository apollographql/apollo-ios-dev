//! Generate operation manifest command implementation.
//!
//! Mirrors Swift's `Sources/CodegenCLI/Commands/GenerateOperationManifest.swift`.
//! Validates that `operationManifest` configuration exists, then calls
//! `ApolloCodegen::build()` with `OPERATION_MANIFEST` only.

use clap::Args;

use apollo_codegen_lib::codegen::{ApolloCodegen, CodegenProvider, ItemsToGenerate};
use apollo_codegen_lib::codegen_logger::CodegenLogger;

use crate::error::CliError;
use crate::input_options::{self, InputOptions};

/// Generate Persisted Queries operation manifest based on a code generation configuration.
#[derive(Args, Debug)]
#[command(name = "generate-operation-manifest")]
pub struct GenerateOperationManifest {
    #[command(flatten)]
    pub inputs: InputOptions,
}

impl GenerateOperationManifest {
    pub fn run(&self) -> Result<(), CliError> {
        CodegenLogger::set_level(self.inputs.verbose);

        let configuration = self.inputs.get_codegen_configuration()?;

        // Validate operationManifest section exists
        if configuration.operation_manifest.is_none() {
            return Err(CliError::Validation {
                message: "`operationManifest` section must be set in the codegen configuration \
                          JSON in order to generate an operation manifest."
                    .to_string(),
            });
        }

        let root_url = input_options::root_output_url(&self.inputs);

        ApolloCodegen::build(
            &configuration,
            root_url.as_deref(),
            ItemsToGenerate::OPERATION_MANIFEST,
        )?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_missing_operation_manifest_config_returns_error() {
        // Create a minimal valid config as JSON string (no operationManifest)
        let config_json = r#"{
            "schemaNamespace": "TestSchema",
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

        let cmd = GenerateOperationManifest {
            inputs: InputOptions {
                path: "./config.json".to_string(),
                string: Some(config_json.to_string()),
                verbose: false,
            },
        };
        let result = cmd.run();
        assert!(result.is_err());
        let msg = format!("{}", result.unwrap_err());
        assert!(msg.contains("operationManifest"));
        assert!(msg.contains("must be set"));
    }
}
