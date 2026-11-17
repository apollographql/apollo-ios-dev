//! File generator for GraphQL Union types.
//!
//! Mirrors Swift's `UnionFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/UnionFileGenerator.swift`.

use std::sync::Arc;

use graphql_compiler::schema::GraphQLUnionType;

use crate::templates::schema::union_template::UnionTemplate;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file containing the Swift representation of a GraphQL Union.
pub struct UnionFileGenerator {
    pub graphql_union: Arc<GraphQLUnionType>,
    pub config: ConfigurationContext,
}

impl FileGenerator for UnionFileGenerator {
    fn file_name(&self) -> String {
        // Mirrors Swift `render(as: .filename)`: a customized name is used unchanged.
        self.graphql_union
            .name
            .custom_name
            .clone()
            .unwrap_or_else(|| self.graphql_union.name.schema_name.clone())
    }

    fn file_suffix(&self) -> Option<&str> {
        Some(".union")
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        Box::new(UnionTemplate {
            graphql_union: self.graphql_union.clone(),
            config: self.config.clone(),
        })
    }

    fn target(&self) -> FileTarget {
        FileTarget::Union
    }
}
