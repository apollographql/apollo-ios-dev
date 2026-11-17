//! File generator for GraphQL Object types.
//!
//! Mirrors Swift's `ObjectFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/ObjectFileGenerator.swift`.

use std::sync::Arc;

use graphql_compiler::schema::GraphQLObjectType;

use crate::templates::schema::object_template::ObjectTemplate;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file containing the Swift representation of a GraphQL Object.
pub struct ObjectFileGenerator {
    pub graphql_object: Arc<GraphQLObjectType>,
    pub config: ConfigurationContext,
}

impl FileGenerator for ObjectFileGenerator {
    fn file_name(&self) -> String {
        // Mirrors Swift `render(as: .filename)`: a customized name is used unchanged.
        self.graphql_object
            .name
            .custom_name
            .clone()
            .unwrap_or_else(|| self.graphql_object.name.schema_name.clone())
    }

    fn file_suffix(&self) -> Option<&str> {
        Some(".object")
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        Box::new(ObjectTemplate {
            graphql_object: self.graphql_object.clone(),
            config: self.config.clone(),
        })
    }

    fn target(&self) -> FileTarget {
        FileTarget::Object
    }
}
