//! File generator for schema metadata files.
//!
//! Mirrors Swift's `SchemaMetadataFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/SchemaMetadataFileGenerator.swift`.

use std::sync::Arc;

use ir;

use crate::templates::schema::schema_metadata_template::SchemaMetadataTemplate;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file containing schema metadata used by the GraphQL executor at runtime.
pub struct SchemaMetadataFileGenerator {
    /// Source IR schema.
    pub schema: Arc<ir::Schema>,
    /// Shared codegen configuration.
    pub config: ConfigurationContext,
}

impl FileGenerator for SchemaMetadataFileGenerator {
    fn file_name(&self) -> String {
        "SchemaMetadata".to_string()
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        Box::new(SchemaMetadataTemplate::new(
            self.schema.clone(),
            self.config.clone(),
        ))
    }

    fn target(&self) -> FileTarget {
        FileTarget::Schema
    }
}
