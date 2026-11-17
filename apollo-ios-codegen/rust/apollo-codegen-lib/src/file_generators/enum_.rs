//! File generator for GraphQL Enum types.
//!
//! Mirrors Swift's `EnumFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/EnumFileGenerator.swift`.

use std::sync::Arc;

use graphql_compiler::schema::GraphQLEnumType;

use crate::templates::schema::enum_template::EnumTemplate;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file containing the Swift representation of a GraphQL Enum.
pub struct EnumFileGenerator {
    pub graphql_enum: Arc<GraphQLEnumType>,
    pub config: ConfigurationContext,
}

impl FileGenerator for EnumFileGenerator {
    fn file_name(&self) -> String {
        // Mirrors Swift `render(as: .filename)`: a customized name is used unchanged.
        self.graphql_enum
            .name
            .custom_name
            .clone()
            .unwrap_or_else(|| self.graphql_enum.name.schema_name.clone())
    }

    fn file_suffix(&self) -> Option<&str> {
        Some(".enum")
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        Box::new(EnumTemplate {
            graphql_enum: self.graphql_enum.clone(),
            config: self.config.clone(),
        })
    }

    fn target(&self) -> FileTarget {
        FileTarget::Enum
    }
}
