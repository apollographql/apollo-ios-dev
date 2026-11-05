//! Initialize command implementation.
//!
//! Mirrors Swift's `Sources/CodegenCLI/Commands/Initialize.swift`. The configuration is
//! produced by the same hand-written `ApolloCodegenConfiguration.minimalJSON` template that
//! the Swift CLI uses (`" : "` separators, empty objects spanning two lines, no trailing
//! newline in the written file) so that `init` output is byte-identical to Swift.

use std::path::Path;

use clap::{Args, ValueEnum};

use apollo_codegen_lib::config::validation::validate_config_values;
use apollo_codegen_lib::config::ApolloCodegenConfiguration;

use crate::constants;
use crate::error::CliError;

/// CLI-friendly module type enum without associated values.
///
/// Mirrors Swift's `ModuleTypeExpressibleByArgument` enum; the raw values are the strings
/// accepted on the command line and written into the generated JSON.
#[derive(Debug, Clone, ValueEnum)]
pub enum CliModuleType {
    #[value(name = "embeddedInTarget")]
    EmbeddedInTarget,
    #[value(name = "swiftPackage")]
    SwiftPackage,
    #[value(name = "other")]
    Other,
}

impl CliModuleType {
    /// The raw value of the Swift `ModuleTypeExpressibleByArgument` case.
    pub fn raw_value(&self) -> &'static str {
        match self {
            CliModuleType::EmbeddedInTarget => "embeddedInTarget",
            CliModuleType::SwiftPackage => "swiftPackage",
            CliModuleType::Other => "other",
        }
    }
}

impl std::fmt::Display for CliModuleType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.raw_value())
    }
}

/// Mirrors Swift's `ApolloCodegenConfiguration.minimalJSON(schemaNamespace:moduleType:targetName:)`
/// (the non-CocoaPods variant). The whitespace is significant: it is the exact text the Swift
/// CLI prints and writes.
pub fn minimal_json(
    schema_namespace: &str,
    module_type: &CliModuleType,
    target_name: Option<&str>,
) -> String {
    let module_target = match target_name {
        None => "}".to_string(),
        Some(name) => format!("  \"name\" : \"{}\"\n        }}", name),
    };

    MINIMAL_JSON_TEMPLATE
        .replace("__SCHEMA_NAMESPACE__", schema_namespace)
        .replace("__MODULE_TYPE__", module_type.raw_value())
        .replace("__MODULE_TARGET__", &module_target)
}

const MINIMAL_JSON_TEMPLATE: &str = r#"{
  "schemaNamespace" : "__SCHEMA_NAMESPACE__",
  "input" : {
    "operationSearchPaths" : [
      "**/*.graphql"
    ],
    "schemaSearchPaths" : [
      "**/*.graphqls"
    ]
  },
  "output" : {
    "testMocks" : {
      "none" : {
      }
    },
    "schemaTypes" : {
      "path" : "./__SCHEMA_NAMESPACE__",
      "moduleType" : {
        "__MODULE_TYPE__" : {
        __MODULE_TARGET__
      }
    },
    "operations" : {
      "inSchemaModule" : {
      }
    }
  }
}"#;

/// Initialize a new configuration with defaults.
#[derive(Args, Debug)]
#[command(name = "init")]
pub struct Initialize {
    /// DEPRECATED - Use --schema-namespace instead.
    #[arg(long)]
    pub schema_name: Option<String>,

    /// Name used to scope the generated schema type files.
    #[arg(long, short = 'n', default_value = "")]
    pub schema_namespace: String,

    /// How to package the schema types for dependency management. Possible types:
    /// embeddedInTarget, swiftPackage, other.
    #[arg(long, short = 'm', value_enum)]
    pub module_type: CliModuleType,

    /// Name of the target in which the schema types files will be manually embedded. This is
    /// required for the "embeddedInTarget" module type and will be ignored for all other
    /// module types.
    #[arg(long, short = 't')]
    pub target_name: Option<String>,

    /// Write the configuration to a file at the path.
    #[arg(short, long, default_value = constants::DEFAULT_FILE_PATH)]
    pub path: String,

    /// Overwrite any file at --path. If init is called without --overwrite and a config file
    /// already exists at --path, the command will fail.
    #[arg(long, short = 'w')]
    pub overwrite: bool,

    /// Print the configuration to stdout.
    #[arg(long, short = 's')]
    pub print: bool,
}

impl Initialize {
    pub fn run(&mut self) -> Result<(), CliError> {
        self.validate()?;

        let json = minimal_json(
            &self.schema_namespace,
            &self.module_type,
            self.target_name.as_deref(),
        );

        // Swift decodes the template and runs `ApolloCodegen._validate` on it before any output.
        let config: ApolloCodegenConfiguration = serde_json::from_str(&json)
            .map_err(|e| CliError::InvalidConfiguration { source: e })?;
        validate_config_values(&config).map_err(|e| CliError::Validation {
            message: format!("{}", e),
        })?;

        if self.print {
            // `Swift.print` appends the line break; the JSON itself has no trailing newline.
            println!("{}", json);
            return Ok(());
        }

        if !self.overwrite && Path::new(&self.path).exists() {
            return Err(CliError::FileAlreadyExists {
                path: self.path.clone(),
            });
        }

        // `ApolloFileManager.createFile` creates intermediate directories.
        if let Some(parent) = Path::new(&self.path).parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).map_err(|e| CliError::Generic {
                    description: format!("Failed to create directory for '{}': {}", self.path, e),
                })?;
            }
        }
        std::fs::write(&self.path, json.as_bytes()).map_err(|e| CliError::Generic {
            description: format!("Failed to write configuration to '{}': {}", self.path, e),
        })?;

        println!("New configuration output to {}.", self.path);
        Ok(())
    }

    fn validate(&mut self) -> Result<(), CliError> {
        // embeddedInTarget requires --target-name (checked first, as in Swift's `validate()`)
        if matches!(self.module_type, CliModuleType::EmbeddedInTarget)
            && self.target_name.as_deref().is_none_or(|n| n.is_empty())
        {
            return Err(CliError::Validation {
                message: "Target name is required when using \"embeddedInTarget\" module type. \
                          Use --target-name to specify."
                    .to_string(),
            });
        }

        // Handle deprecated --schema-name (the warning goes to stdout, like `Swift.print`)
        if let Some(ref schema_name) = self.schema_name {
            println!(
                "Warning: --schema-name is deprecated, please use --schema-namespace instead."
            );

            if !self.schema_namespace.is_empty() {
                return Err(CliError::Validation {
                    message: "Cannot specify both --schema-name and --schema-namespace. \
                              Please only use --schema-namespace."
                        .to_string(),
                });
            }

            self.schema_namespace = schema_name.clone();
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cli_module_type_raw_values_match_swift() {
        assert_eq!(
            CliModuleType::EmbeddedInTarget.raw_value(),
            "embeddedInTarget"
        );
        assert_eq!(CliModuleType::SwiftPackage.raw_value(), "swiftPackage");
        assert_eq!(CliModuleType::Other.raw_value(), "other");
    }

    #[test]
    fn test_minimal_json_matches_swift_template_with_target_name() {
        let json = minimal_json("X", &CliModuleType::EmbeddedInTarget, Some("T"));
        let expected = "{\n  \"schemaNamespace\" : \"X\",\n  \"input\" : {\n    \"operationSearchPaths\" : [\n      \"**/*.graphql\"\n    ],\n    \"schemaSearchPaths\" : [\n      \"**/*.graphqls\"\n    ]\n  },\n  \"output\" : {\n    \"testMocks\" : {\n      \"none\" : {\n      }\n    },\n    \"schemaTypes\" : {\n      \"path\" : \"./X\",\n      \"moduleType\" : {\n        \"embeddedInTarget\" : {\n          \"name\" : \"T\"\n        }\n      }\n    },\n    \"operations\" : {\n      \"inSchemaModule\" : {\n      }\n    }\n  }\n}";
        assert_eq!(json, expected);
        assert!(serde_json::from_str::<ApolloCodegenConfiguration>(&json).is_ok());
    }

    #[test]
    fn test_minimal_json_matches_swift_template_without_target_name() {
        let json = minimal_json("X", &CliModuleType::Other, None);
        assert!(
            json.contains("      \"moduleType\" : {\n        \"other\" : {\n        }\n      }\n"),
            "{}",
            json
        );
        assert!(!json.ends_with('\n'));
        // Swift writes the target name for every module type when one is given.
        let json = minimal_json("X", &CliModuleType::SwiftPackage, Some("T"));
        assert!(
            json.contains("        \"swiftPackage\" : {\n          \"name\" : \"T\"\n        }\n"),
            "{}",
            json
        );
    }

    #[test]
    fn test_validate_embedded_requires_target_name() {
        let mut cmd = Initialize {
            schema_name: None,
            schema_namespace: "MySchema".to_string(),
            module_type: CliModuleType::EmbeddedInTarget,
            target_name: None,
            path: constants::DEFAULT_FILE_PATH.to_string(),
            overwrite: false,
            print: false,
        };
        let result = cmd.validate();
        assert!(result.is_err());
        let msg = format!("{}", result.unwrap_err());
        assert!(msg.contains("Target name is required"));
    }

    #[test]
    fn test_validate_embedded_empty_target_name_rejected() {
        let mut cmd = Initialize {
            schema_name: None,
            schema_namespace: "MySchema".to_string(),
            module_type: CliModuleType::EmbeddedInTarget,
            target_name: Some("".to_string()),
            path: constants::DEFAULT_FILE_PATH.to_string(),
            overwrite: false,
            print: false,
        };
        let result = cmd.validate();
        assert!(result.is_err());
    }

    #[test]
    fn test_validate_schema_name_and_namespace_conflict() {
        let mut cmd = Initialize {
            schema_name: Some("OldName".to_string()),
            schema_namespace: "NewName".to_string(),
            module_type: CliModuleType::SwiftPackage,
            target_name: None,
            path: constants::DEFAULT_FILE_PATH.to_string(),
            overwrite: false,
            print: false,
        };
        let result = cmd.validate();
        assert!(result.is_err());
        let msg = format!("{}", result.unwrap_err());
        assert!(msg.contains("Cannot specify both --schema-name and --schema-namespace"));
    }

    #[test]
    fn test_validate_deprecated_schema_name_sets_namespace() {
        let mut cmd = Initialize {
            schema_name: Some("LegacyName".to_string()),
            schema_namespace: "".to_string(),
            module_type: CliModuleType::SwiftPackage,
            target_name: None,
            path: constants::DEFAULT_FILE_PATH.to_string(),
            overwrite: false,
            print: false,
        };
        let result = cmd.validate();
        assert!(result.is_ok());
        assert_eq!(cmd.schema_namespace, "LegacyName");
    }

    #[test]
    fn test_validate_swift_package_no_target_needed() {
        let mut cmd = Initialize {
            schema_name: None,
            schema_namespace: "MySchema".to_string(),
            module_type: CliModuleType::SwiftPackage,
            target_name: None,
            path: constants::DEFAULT_FILE_PATH.to_string(),
            overwrite: false,
            print: false,
        };
        let result = cmd.validate();
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_other_no_target_needed() {
        let mut cmd = Initialize {
            schema_name: None,
            schema_namespace: "MySchema".to_string(),
            module_type: CliModuleType::Other,
            target_name: None,
            path: constants::DEFAULT_FILE_PATH.to_string(),
            overwrite: false,
            print: false,
        };
        let result = cmd.validate();
        assert!(result.is_ok());
    }
}
