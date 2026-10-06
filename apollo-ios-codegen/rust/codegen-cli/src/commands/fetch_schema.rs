//! Fetch schema command implementation (stub per D-69).
//!
//! Mirrors Swift's `Sources/CodegenCLI/Commands/FetchSchema.swift`.
//! In the Rust CLI, schema downloading is not yet supported. This command
//! exists so that `--help` shows all 4 subcommands matching the Swift CLI,
//! but always exits with an error.

use clap::Args;

use crate::error::CliError;
use crate::input_options::InputOptions;

/// Download a GraphQL schema from the Apollo Registry or GraphQL introspection.
#[derive(Args, Debug)]
#[command(name = "fetch-schema")]
pub struct FetchSchema {
    #[command(flatten)]
    pub inputs: InputOptions,
}

impl FetchSchema {
    pub fn run(&self) -> Result<(), CliError> {
        Err(CliError::Generic {
            description: "Schema downloading is not yet supported in the Rust CLI. \
                          Use the Swift CLI for now."
                .to_string(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fetch_schema_returns_stub_error() {
        let cmd = FetchSchema {
            inputs: InputOptions {
                path: "./config.json".to_string(),
                string: None,
                verbose: false,
            },
        };
        let result = cmd.run();
        assert!(result.is_err());
        let msg = format!("{}", result.unwrap_err());
        assert!(msg.contains("Schema downloading is not yet supported in the Rust CLI"));
    }
}
