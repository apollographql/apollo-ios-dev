//! Configuration validation for Apollo codegen.
//!
//! Mirrors Swift's `ConfigurationValidation.swift` -- static analysis of configuration
//! values that catches errors before code generation begins. Does not require a compiled
//! schema; schema-aware validation is defined as a trait for Phase 3 implementation.

use std::fmt;

use super::field_merging::FieldMerging;
use super::module_type::ModuleType;
use super::selection_set_initializers::SelectionSetInitializers;
use super::swift_keywords::SwiftKeywords;
use super::test_mock_file_output::TestMockFileOutput;
use super::ApolloCodegenConfiguration;
use crate::capitalization_rule::Term;

/// Errors that can occur during configuration validation.
///
/// Error messages match Swift's `ApolloCodegen.Error` `errorDescription` strings exactly.
#[derive(Debug, Clone, PartialEq)]
pub enum ConfigError {
    /// The schema namespace is empty or contains whitespace.
    InvalidSchemaName { name: String, message: String },
    /// The schema namespace conflicts with a reserved name in the generated code.
    SchemaNameConflict { name: String },
    /// Field merging is not set to ALL but selection set initializers are non-empty.
    FieldMergingIncompatibility,
    /// Test mocks are configured as SwiftPackage but module type is not SwiftPackageManager.
    TestMocksInvalidSwiftPackageConfiguration,
    /// A generic configuration conflict.
    InvalidConfiguration { message: String },
    /// The embedded target name conflicts with a reserved library name.
    TargetNameConflict { name: String },
    /// An input search path is missing a file extension.
    InputSearchPathInvalid { path: String },
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConfigError::InvalidSchemaName { name, message } => {
                write!(f, "The schema namespace `{}` is invalid: {}", name, message)
            }
            ConfigError::SchemaNameConflict { name } => {
                write!(
                    f,
                    "Schema namespace '{}' conflicts with name of a type in the generated code. \
           Please choose a different schema name. Suggestions: {}Schema, {}GraphQL, {}API.",
                    name, name, name, name
                )
            }
            ConfigError::FieldMergingIncompatibility => {
                write!(
          f,
          "Options for disabling 'fieldMerging' and enabling 'selectionSetInitializers' are\n\
           incompatible.\n\n\
           Please set either 'fieldMerging' to 'all' or 'selectionSetInitializers' to be empty."
        )
            }
            ConfigError::TestMocksInvalidSwiftPackageConfiguration => {
                write!(
          f,
          "Schema Types must be generated with module type 'swiftPackageManager' to generate \
           a swift package for test mocks."
        )
            }
            ConfigError::InvalidConfiguration { message } => {
                write!(
                    f,
                    "The codegen configuration has conflicting values: {}",
                    message
                )
            }
            ConfigError::TargetNameConflict { name } => {
                write!(
          f,
          "Target name '{}' conflicts with a reserved library name. Please choose a different \
           target name.",
          name
        )
            }
            ConfigError::InputSearchPathInvalid { path } => {
                write!(
                    f,
                    "Input search path '{}' is invalid. Input search paths must include a file \
           extension component. (eg. '.graphql')",
                    path
                )
            }
        }
    }
}

impl std::error::Error for ConfigError {}

/// Validates the configuration against deterministic errors that will cause code generation
/// to fail. This validation step does not take into account schema and operation specific
/// types -- it is only a static analysis of the configuration.
///
/// Mirrors Swift's `ConfigurationContext.validateConfigValues()`.
///
/// The order of checks follows Swift's implementation exactly:
/// 1. Schema namespace not empty and no whitespace
/// 2. Field merging / selection set initializers incompatibility
/// 3. Schema namespace not a disallowed name (case-insensitive)
/// 4. Test mocks swift package requires SPM module type
/// 5. CocoaPods import + SPM incompatibility
/// 6. Embedded target name not disallowed (case-insensitive)
/// 7. Input search paths must contain a file extension
/// 8. Every regex term in `additionalCapitalizationRules` must compile
pub fn validate_config_values(config: &ApolloCodegenConfiguration) -> Result<(), ConfigError> {
    // 1. Schema namespace not empty and no whitespace
    if config.schema_namespace.is_empty()
        || config.schema_namespace.chars().any(|c| c.is_whitespace())
    {
        return Err(ConfigError::InvalidSchemaName {
            name: config.schema_namespace.clone(),
            message: "Cannot be empty nor contain spaces. If your schema namespace has spaces \
                consider replacing them with the underscore character."
                .to_string(),
        });
    }

    // 2. Field merging / selection set initializers incompatibility
    let is_selection_set_empty =
        config.options.selection_set_initializers == SelectionSetInitializers::empty();
    if config.experimental_features.field_merging != FieldMerging::ALL && !is_selection_set_empty {
        return Err(ConfigError::FieldMergingIncompatibility);
    }

    // 3. Schema namespace not a disallowed name (case-insensitive)
    if SwiftKeywords::DISALLOWED_SCHEMA_NAMESPACE_NAMES
        .contains(&config.schema_namespace.to_lowercase().as_str())
    {
        return Err(ConfigError::SchemaNameConflict {
            name: config.schema_namespace.clone(),
        });
    }

    // 4. Test mocks swift package requires SPM module type
    if matches!(
        config.output.test_mocks,
        TestMockFileOutput::SwiftPackage { .. }
    ) && !matches!(
        config.output.schema_types.module_type,
        ModuleType::SwiftPackage { .. }
    ) {
        return Err(ConfigError::TestMocksInvalidSwiftPackageConfiguration);
    }

    // 5. CocoaPods import + SPM incompatibility
    if matches!(
        config.output.schema_types.module_type,
        ModuleType::SwiftPackage { .. }
    ) && config.options.cocoapods_compatible_import_statements
    {
        return Err(ConfigError::InvalidConfiguration {
            message: "cocoapodsCompatibleImportStatements cannot be set to 'true' when the output \
                schema types module type is Swift Package Manager. Change the \
                cocoapodsCompatibleImportStatements value to 'false', or choose a different \
                module type, to resolve the conflict."
                .to_string(),
        });
    }

    // 6. Embedded target name not disallowed (case-insensitive)
    if let ModuleType::EmbeddedInTarget { ref name, .. } = config.output.schema_types.module_type {
        if SwiftKeywords::DISALLOWED_EMBEDDED_TARGET_NAMES.contains(&name.to_lowercase().as_str()) {
            return Err(ConfigError::TargetNameConflict { name: name.clone() });
        }
    }

    // 7. Input search paths must contain a file extension
    for search_path in &config.input.schema_search_paths {
        validate_input_search_path(search_path)?;
    }
    for search_path in &config.input.operation_search_paths {
        validate_input_search_path(search_path)?;
    }

    // 8. Every regex term in additionalCapitalizationRules must compile
    for rule in &config.options.additional_capitalization_rules {
        let Term::Regex(pattern) = &rule.term else {
            continue;
        };
        if let Err(error) = regex::Regex::new(pattern) {
            return Err(ConfigError::InvalidConfiguration {
                message: format!(
                    "Invalid regular expression '{}' in additionalCapitalizationRules: {}",
                    pattern, error
                ),
            });
        }
    }

    Ok(())
}

/// Validates that an input search path contains a file extension.
/// The path must contain a `.` and must not end with `.`.
fn validate_input_search_path(path: &str) -> Result<(), ConfigError> {
    if !path.contains('.') || path.ends_with('.') {
        return Err(ConfigError::InputSearchPathInvalid {
            path: path.to_string(),
        });
    }
    Ok(())
}

/// Trait for schema-aware configuration validation.
///
/// This validates configuration against the compiled schema and operations,
/// checking for conflicts that can only be detected with knowledge of the
/// actual GraphQL types (e.g., schema namespace conflicting with a type name).
///
/// Defined in Phase 2; implemented in Phase 3 when the compilation result
/// types are available.
pub trait SchemaAwareValidator {
    /// Validates the configuration against a compiled schema.
    fn validate_against_schema(
        &self,
        config: &ApolloCodegenConfiguration,
    ) -> Result<(), ConfigError>;
}
