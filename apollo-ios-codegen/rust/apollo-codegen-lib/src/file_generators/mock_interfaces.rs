//! File generator for test mock interfaces file.
//!
//! Mirrors Swift's `MockInterfacesFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/MockInterfacesFileGenerator.swift`.

use std::sync::Arc;

use graphql_compiler::schema::GraphQLInterfaceType;
use indexmap::IndexSet;

use crate::templates::mock_interfaces_template::MockInterfacesTemplate;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file providing the ability to mock GraphQL Interface types for testing purposes.
pub struct MockInterfacesFileGenerator {
    pub graphql_interfaces: IndexSet<Arc<GraphQLInterfaceType>>,
    pub config: ConfigurationContext,
}

impl FileGenerator for MockInterfacesFileGenerator {
    fn file_name(&self) -> String {
        "MockObject+Interfaces".to_string()
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        Box::new(MockInterfacesTemplate {
            graphql_interfaces: self.graphql_interfaces.clone(),
            config: self.config.clone(),
        })
    }

    fn target(&self) -> FileTarget {
        FileTarget::TestMock
    }
}
