//! File generator for schema configuration files.
//!
//! Mirrors Swift's `SchemaConfigurationFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/SchemaConfigurationFileGenerator.swift`.

use crate::templates::schema::schema_configuration_template::SchemaConfigurationTemplate;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file containing schema configuration used by the GraphQL executor at runtime.
///
/// Note: `overwrite()` returns `false` -- this is an editable file that should not
/// be overwritten once created.
pub struct SchemaConfigurationFileGenerator {
    /// Shared codegen configuration.
    pub config: ConfigurationContext,
}

impl FileGenerator for SchemaConfigurationFileGenerator {
    fn file_name(&self) -> String {
        "SchemaConfiguration".to_string()
    }

    fn overwrite(&self) -> bool {
        false
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        Box::new(SchemaConfigurationTemplate {
            config: self.config.clone(),
        })
    }

    fn target(&self) -> FileTarget {
        FileTarget::Schema
    }
}
