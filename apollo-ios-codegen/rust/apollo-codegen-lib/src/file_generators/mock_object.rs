//! File generator for test mock object files.
//!
//! Mirrors Swift's `MockObjectFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/MockObjectFileGenerator.swift`.

use std::sync::Arc;

use graphql_compiler::graphql_type::GraphQLType;
use graphql_compiler::schema::GraphQLObjectType;
use ir::ReferencedTypes;

use crate::templates::mock_object_template::MockObjectTemplate;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file providing the ability to mock a GraphQL Object for testing purposes.
pub struct MockObjectFileGenerator {
    pub graphql_object: Arc<GraphQLObjectType>,
    /// Fields as (response_key, type, deprecation_reason) tuples.
    pub fields: Vec<(String, GraphQLType, Option<String>)>,
    /// `ir.schema.referencedTypes`: used to pick default mock values for abstract fields.
    pub referenced_types: Arc<ReferencedTypes>,
    pub config: ConfigurationContext,
}

impl FileGenerator for MockObjectFileGenerator {
    fn file_name(&self) -> String {
        let name = self
            .graphql_object
            .name
            .custom_name
            .clone()
            .unwrap_or_else(|| self.graphql_object.name.schema_name.clone());
        format!("{}+Mock", name)
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        Box::new(MockObjectTemplate {
            graphql_object: self.graphql_object.clone(),
            fields: self.fields.clone(),
            referenced_types: Arc::clone(&self.referenced_types),
            config: self.config.clone(),
        })
    }

    fn target(&self) -> FileTarget {
        FileTarget::TestMock
    }
}
