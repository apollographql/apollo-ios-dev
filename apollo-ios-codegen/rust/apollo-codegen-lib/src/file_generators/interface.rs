//! File generator for GraphQL Interface types.
//!
//! Mirrors Swift's `InterfaceFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/InterfaceFileGenerator.swift`.

use std::sync::Arc;

use graphql_compiler::schema::GraphQLInterfaceType;

use crate::templates::schema::interface_template::InterfaceTemplate;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file containing the Swift representation of a GraphQL Interface.
pub struct InterfaceFileGenerator {
    pub graphql_interface: Arc<GraphQLInterfaceType>,
    pub config: ConfigurationContext,
}

impl FileGenerator for InterfaceFileGenerator {
    fn file_name(&self) -> String {
        // Mirrors Swift `render(as: .filename)`: a customized name is used unchanged.
        self.graphql_interface
            .name
            .custom_name
            .clone()
            .unwrap_or_else(|| self.graphql_interface.name.schema_name.clone())
    }

    fn file_suffix(&self) -> Option<&str> {
        Some(".interface")
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        Box::new(InterfaceTemplate {
            graphql_interface: self.graphql_interface.clone(),
            config: self.config.clone(),
        })
    }

    fn target(&self) -> FileTarget {
        FileTarget::Interface
    }
}
