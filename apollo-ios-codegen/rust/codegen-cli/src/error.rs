//! CLI-specific error types.
//!
//! Mirrors Swift's `Sources/CodegenCLI/Error.swift` with additional
//! structured variants for common CLI failure modes.

use std::fmt;

/// CLI-specific errors that can occur during command execution.
#[derive(Debug)]
pub enum CliError {
    /// Generic error with a description.
    ///
    /// Mirrors Swift's `Error { errorDescription }`.
    Generic { description: String },
    /// Cannot read config file at path.
    CannotReadFile { path: String, source: std::io::Error },
    /// Config JSON is invalid.
    InvalidConfiguration { source: serde_json::Error },
    /// File already exists and --overwrite not passed.
    FileAlreadyExists { path: String },
    /// Validation error (e.g., missing required options).
    Validation { message: String },
    /// Codegen pipeline error.
    Codegen(apollo_codegen_lib::codegen::CodegenError),
}

impl fmt::Display for CliError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CliError::Generic { description } => write!(f, "{}", description),
            CliError::CannotReadFile { path, source } => {
                write!(f, "Cannot read file at '{}': {}", path, source)
            }
            CliError::InvalidConfiguration { source } => {
                write!(f, "Invalid configuration: {}", source)
            }
            CliError::FileAlreadyExists { path } => {
                write!(
                    f,
                    "File already exists at {}. Hint: use --overwrite to overwrite any existing file at the path.",
                    path
                )
            }
            CliError::Validation { message } => write!(f, "{}", message),
            CliError::Codegen(e) => write!(f, "{}", e),
        }
    }
}

impl std::error::Error for CliError {}

impl From<apollo_codegen_lib::codegen::CodegenError> for CliError {
    fn from(e: apollo_codegen_lib::codegen::CodegenError) -> Self {
        CliError::Codegen(e)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cli_error_display_generic() {
        let err = CliError::Generic {
            description: "something went wrong".to_string(),
        };
        assert_eq!(format!("{}", err), "something went wrong");
    }

    #[test]
    fn test_cli_error_display_cannot_read_file() {
        let err = CliError::CannotReadFile {
            path: "/bad/path.json".to_string(),
            source: std::io::Error::new(std::io::ErrorKind::NotFound, "not found"),
        };
        let msg = format!("{}", err);
        assert!(msg.contains("Cannot read file at '/bad/path.json'"));
        assert!(msg.contains("not found"));
    }

    #[test]
    fn test_cli_error_display_file_already_exists() {
        let err = CliError::FileAlreadyExists {
            path: "./config.json".to_string(),
        };
        let msg = format!("{}", err);
        assert!(msg.contains("File already exists at ./config.json"));
        assert!(msg.contains("--overwrite"));
    }

    #[test]
    fn test_cli_error_display_validation() {
        let err = CliError::Validation {
            message: "missing required field".to_string(),
        };
        assert_eq!(format!("{}", err), "missing required field");
    }

    #[test]
    fn test_cli_error_from_codegen_error() {
        let codegen_err = apollo_codegen_lib::codegen::CodegenError::CannotLoadSchema;
        let cli_err: CliError = codegen_err.into();
        assert!(matches!(cli_err, CliError::Codegen(_)));
        let msg = format!("{}", cli_err);
        assert!(msg.contains("A GraphQL schema could not be found"));
    }
}
