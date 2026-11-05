//! File generator for GraphQL Custom Scalar types.
//!
//! Mirrors Swift's `CustomScalarFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/CustomScalarFileGenerator.swift`.

use std::sync::Arc;

use graphql_compiler::schema::GraphQLScalarType;

use crate::templates::schema::custom_scalar_template::CustomScalarTemplate;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file containing the Swift representation of a GraphQL Custom Scalar.
///
/// Note: `overwrite()` returns `false` -- this is an editable file that should not
/// be overwritten once created.
pub struct CustomScalarFileGenerator {
    pub graphql_scalar: Arc<GraphQLScalarType>,
    pub config: ConfigurationContext,
}

impl FileGenerator for CustomScalarFileGenerator {
    fn file_name(&self) -> String {
        // Mirrors Swift `render(as: .filename)`: a customized name is used unchanged.
        self.graphql_scalar
            .name
            .custom_name
            .clone()
            .unwrap_or_else(|| self.graphql_scalar.name.schema_name.clone())
    }

    fn file_suffix(&self) -> Option<&str> {
        Some(".scalar")
    }

    fn overwrite(&self) -> bool {
        false
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        Box::new(CustomScalarTemplate {
            graphql_scalar: self.graphql_scalar.clone(),
            config: self.config.clone(),
        })
    }

    fn target(&self) -> FileTarget {
        FileTarget::CustomScalar
    }
}
