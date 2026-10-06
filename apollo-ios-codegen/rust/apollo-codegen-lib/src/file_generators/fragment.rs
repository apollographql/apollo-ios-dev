//! File generator for GraphQL Fragment types.
//!
//! Mirrors Swift's `FragmentFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/FragmentFileGenerator.swift`.

use std::sync::Arc;

use ir;

use crate::templates::fragment_template::FragmentTemplate;
use crate::templates::rendering_helpers::ir_definition_rendering::generated_fragment_file_name;
use crate::templates::{ConfigurationContext, TemplateRenderer};

use super::{FileGenerator, FileTarget};

/// Generates a file containing the Swift representation of a GraphQL Fragment.
pub struct FragmentFileGenerator {
    /// Source IR fragment.
    pub ir_fragment: Arc<ir::NamedFragment>,
    /// Shared codegen configuration.
    pub config: ConfigurationContext,
}

impl FileGenerator for FragmentFileGenerator {
    fn file_name(&self) -> String {
        generated_fragment_file_name(&self.ir_fragment.definition.name, &self.config.capitalizer)
    }

    fn template(&self) -> Box<dyn TemplateRenderer + '_> {
        Box::new(FragmentTemplate {
            fragment: self.ir_fragment.clone(),
            config: self.config.clone(),
        })
    }

    fn target(&self) -> FileTarget {
        FileTarget::Fragment {
            file_path: self.ir_fragment.definition.file_path.clone(),
            is_local_cache_mutation: self.ir_fragment.definition.is_local_cache_mutation(),
        }
    }
}
