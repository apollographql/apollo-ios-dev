//! File generator for GraphQL Operation types (queries, mutations, subscriptions).
//!
//! Mirrors Swift's `OperationFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/OperationFileGenerator.swift`.

use std::sync::Arc;

use ir;

use crate::templates::local_cache_mutation_definition_template::LocalCacheMutationDefinitionTemplate;
use crate::templates::operation_definition_template::OperationDefinitionTemplate;
use crate::templates::rendering_helpers::ir_definition_rendering::generated_definition_name_capitalized;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file containing the Swift representation of a GraphQL Operation.
pub struct OperationFileGenerator {
    /// Source IR operation.
    pub ir_operation: Arc<ir::Operation>,
    /// The persisted query identifier for the operation.
    pub operation_identifier: Option<String>,
    /// Shared codegen configuration.
    pub config: ConfigurationContext,
    /// The schema\'s referenced types (resolves nested input object types in defaults).
    pub referenced_types: Arc<ir::ReferencedTypes>,
}

impl FileGenerator for OperationFileGenerator {
    fn file_name(&self) -> String {
        generated_definition_name_capitalized(
            &self.ir_operation.definition.name,
            &self.ir_operation.definition.operation_type.to_string(),
            self.ir_operation.definition.is_local_cache_mutation(),
            &self.config.capitalizer,
        )
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        if self.ir_operation.definition.is_local_cache_mutation() {
            Box::new(LocalCacheMutationDefinitionTemplate {
                operation: self.ir_operation.clone(),
                config: self.config.clone(),
                referenced_types: Arc::clone(&self.referenced_types),
            })
        } else {
            Box::new(OperationDefinitionTemplate {
                operation: self.ir_operation.clone(),
                operation_identifier: self.operation_identifier.clone(),
                config: self.config.clone(),
                referenced_types: Arc::clone(&self.referenced_types),
            })
        }
    }

    fn target(&self) -> FileTarget {
        FileTarget::Operation {
            operation_type: self.ir_operation.definition.operation_type.clone(),
            file_path: self.ir_operation.definition.file_path.clone(),
            is_local_cache_mutation: self.ir_operation.definition.is_local_cache_mutation(),
        }
    }
}
