//! Fragment template for code generation.
//!
//! Generates Swift structs for GraphQL named fragments.
//!
//! Mirrors Swift's `FragmentTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/FragmentTemplate.swift`.

use std::sync::Arc;

use crate::config::operation_document_format::OperationDocumentFormat;
use crate::templates::rendering_helpers::ir_definition_rendering::rendered_selection_set_type;
use crate::templates::rendering_helpers::string_single_line::converted_to_single_line;
use crate::templates::rendering_helpers::string_swift_name_escaping::as_fragment_name;
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, Scope, TemplateRenderer, TemplateTarget,
};

use super::rendering_helpers::selection_set_initializer_check::should_generate_selection_set_initializers;
use super::selection_set_template::SelectionSetTemplate;

/// Template for generating Swift code for a GraphQL named fragment.
///
/// Mirrors Swift's `FragmentTemplate` struct.
pub struct FragmentTemplate {
    pub fragment: Arc<ir::NamedFragment>,
    pub config: ConfigurationContext,
}

impl TemplateRenderer for FragmentTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::OperationFile {
            module_imports: Some(
                self.fragment
                    .definition
                    .module_imports()
                    .into_iter()
                    .collect(),
            ),
        }
    }

    fn render_body_template(&self, non_fatal_error_recorder: &NonFatalErrorRecorder) -> String {
        let include_definition = self
            .config
            .options()
            .operation_document_format
            .contains(OperationDocumentFormat::DEFINITION);
        let member_access = self.access_control_renderer(Scope::Member);
        let parent_access = self.access_control_renderer(Scope::Parent);

        let mut result = String::new();

        // Struct declaration; `Identifiable` conformance mirrors Swift 1.18.0.
        let fragment_name =
            as_fragment_name(&self.fragment.definition.name, &self.config.capitalizer);
        let is_mutable = self.fragment.definition.is_local_cache_mutation();
        let selection_set_type = rendered_selection_set_type(&self.config, is_mutable);
        let identifiable = if self.fragment.is_identifiable() {
            ", Identifiable"
        } else {
            ""
        };

        result.push_str(&format!(
            "{}{}struct {}: {}, Fragment{} {{
",
            self.config.nonisolated_modifier(),
            parent_access.render(),
            fragment_name,
            selection_set_type,
            identifiable,
        ));

        // Fragment definition (if config includes definitions)
        if include_definition {
            let source_single_line = converted_to_single_line(&self.fragment.definition.source);
            result.push_str(&format!(
                "  {}static var fragmentDefinition: StaticString {{\n    #\"{}\"#\n  }}\n\n",
                member_access.render(),
                source_single_line,
            ));
        }

        // Selection set body
        let generate_initializers = should_generate_selection_set_initializers(
            &self.config.config,
            self.fragment.as_ref(),
            true,
        );
        let selection_set_template = SelectionSetTemplate::new(
            self.fragment.as_ref(),
            generate_initializers,
            &self.config,
            non_fatal_error_recorder,
            &member_access,
        );
        let selection_body = selection_set_template.render_body();
        result.push_str(&indent(&selection_body, 2));
        result.push_str("\n}\n");

        result
    }
}

/// Indents every non-empty line by the specified number of spaces.
fn indent(text: &str, spaces: usize) -> String {
    let prefix: String = " ".repeat(spaces);
    text.lines()
        .map(|line| {
            if line.trim().is_empty() {
                String::new()
            } else {
                format!("{}{}", prefix, line)
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}
