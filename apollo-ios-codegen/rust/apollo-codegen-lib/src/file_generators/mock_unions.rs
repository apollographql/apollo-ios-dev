//! File generator for test mock unions file.
//!
//! Mirrors Swift's `MockUnionsFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/MockUnionsFileGenerator.swift`.

use std::sync::Arc;

use graphql_compiler::schema::GraphQLUnionType;
use indexmap::IndexSet;

use crate::templates::mock_unions_template::MockUnionsTemplate;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file providing the ability to mock GraphQL Union types for testing purposes.
pub struct MockUnionsFileGenerator {
    pub graphql_unions: IndexSet<Arc<GraphQLUnionType>>,
    pub config: ConfigurationContext,
}

impl FileGenerator for MockUnionsFileGenerator {
    fn file_name(&self) -> String {
        "MockObject+Unions".to_string()
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        Box::new(MockUnionsTemplate {
            graphql_unions: self.graphql_unions.clone(),
            config: self.config.clone(),
        })
    }

    fn target(&self) -> FileTarget {
        FileTarget::TestMock
    }
}
