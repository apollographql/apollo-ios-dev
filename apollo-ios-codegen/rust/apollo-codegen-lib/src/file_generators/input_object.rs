//! File generator for GraphQL Input Object types.
//!
//! Mirrors Swift's `InputObjectFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/InputObjectFileGenerator.swift`.

use std::sync::Arc;

use graphql_compiler::schema::GraphQLInputObjectType;

use crate::templates::schema::input_object_template::InputObjectTemplate;
use crate::templates::schema::one_of_input_object_template::OneOfInputObjectTemplate;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file containing the Swift representation of a GraphQL Input Object.
///
/// Uses `OneOfInputObjectTemplate` for `@oneOf` input objects, otherwise `InputObjectTemplate`.
pub struct InputObjectFileGenerator {
    pub graphql_input_object: Arc<GraphQLInputObjectType>,
    pub config: ConfigurationContext,
}

impl FileGenerator for InputObjectFileGenerator {
    fn file_name(&self) -> String {
        // Mirrors Swift `render(as: .filename)`: a customized name is used unchanged.
        self.graphql_input_object
            .name
            .custom_name
            .clone()
            .unwrap_or_else(|| self.graphql_input_object.name.schema_name.clone())
    }

    fn file_suffix(&self) -> Option<&str> {
        Some(".inputObject")
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        if self.graphql_input_object.is_one_of {
            Box::new(OneOfInputObjectTemplate {
                graphql_input_object: self.graphql_input_object.clone(),
                config: self.config.clone(),
            })
        } else {
            Box::new(InputObjectTemplate {
                graphql_input_object: self.graphql_input_object.clone(),
                config: self.config.clone(),
            })
        }
    }

    fn target(&self) -> FileTarget {
        FileTarget::InputObject
    }
}
