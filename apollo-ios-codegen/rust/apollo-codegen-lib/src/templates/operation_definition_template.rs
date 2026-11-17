//! Operation definition template for code generation.
//!
//! Generates Swift structs for GraphQL operations (queries, mutations, subscriptions).
//!
//! Mirrors Swift's `OperationDefinitionTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/OperationDefinitionTemplate.swift`.

use std::sync::Arc;

use graphql_compiler::compilation_result::OperationType;

use crate::config::operation_document_format::OperationDocumentFormat;
use crate::templates::rendering_helpers::ir_definition_rendering::{
    generated_definition_name_capitalized, rendered_selection_set_type,
};
use crate::templates::rendering_helpers::operation_template_renderer::{self, VariableDefinition};
use crate::templates::rendering_helpers::string_single_line::converted_to_single_line;
use crate::templates::rendering_helpers::string_swift_name_escaping::as_fragment_name;
use crate::templates::{
    AccessControlRenderer, ConfigurationContext, NonFatalErrorRecorder, Scope, TemplateRenderer,
    TemplateTarget,
};

use super::deferred_fragments_metadata_template::DeferredFragmentsMetadataTemplate;
use super::rendering_helpers::selection_set_initializer_check::should_generate_selection_set_initializers;
use super::selection_set_template::SelectionSetTemplate;

/// Template for generating Swift code for a GraphQL operation definition.
///
/// Mirrors Swift's `OperationDefinitionTemplate` struct.
pub struct OperationDefinitionTemplate {
    pub operation: Arc<ir::Operation>,
    /// The persisted query identifier for the operation.
    pub operation_identifier: Option<String>,
    pub config: ConfigurationContext,
    /// The schema's referenced types, used to resolve nested input object types when
    /// rendering variable default values.
    pub referenced_types: Arc<ir::ReferencedTypes>,
}

impl TemplateRenderer for OperationDefinitionTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::OperationFile {
            module_imports: Some(
                self.operation
                    .definition
                    .module_imports()
                    .into_iter()
                    .collect(),
            ),
        }
    }

    fn render_body_template(&self, non_fatal_error_recorder: &NonFatalErrorRecorder) -> String {
        let member_access = self.access_control_renderer(Scope::Member);
        let parent_access = self.access_control_renderer(Scope::Parent);

        let mut result = String::new();

        // Operation declaration
        result.push_str(&self.render_operation_declaration(&parent_access, &member_access));

        // Document type
        let doc_type = self.render_document_type(&member_access);
        result.push_str(&doc_type);

        // Variable properties (section: blank line before if non-empty)
        let variables = self.convert_variables();
        if !variables.is_empty() {
            let var_props =
                operation_template_renderer::render_variable_properties(&variables, &self.config);
            result.push('\n');
            result.push_str(&indent(&var_props, 2));
            result.push('\n');
        }

        // Initializer (always preceded by blank line from DocumentType or VariableProperties)
        result.push('\n');
        let referenced_types = Arc::clone(&self.referenced_types);
        let resolve_input_object = move |name: &str| {
            referenced_types
                .input_objects
                .iter()
                .find(|t| t.name.schema_name == name)
                .cloned()
        };
        let init = operation_template_renderer::render_initializer_resolving(
            &variables,
            &self.config,
            &resolve_input_object,
        );
        result.push_str(&indent(&init, 2));
        result.push('\n');

        // Variable accessors
        let var_accessors =
            operation_template_renderer::render_variable_accessors(&variables, &self.config, true);
        if !var_accessors.is_empty() {
            result.push('\n');
            result.push_str(&indent(&var_accessors, 2));
            result.push('\n');
        }

        // Selection set (Data struct)
        let selection_set_type = rendered_selection_set_type(&self.config, false);
        let generate_initializers = should_generate_selection_set_initializers(
            &self.config.config,
            self.operation.as_ref(),
            false,
        );
        let selection_set_template = SelectionSetTemplate::new(
            self.operation.as_ref(),
            generate_initializers,
            &self.config,
            non_fatal_error_recorder,
            &member_access,
        );
        let selection_body = selection_set_template.render_body();
        result.push('\n');
        result.push_str(&format!(
            "  {}{}struct Data: {} {{\n",
            self.config.nonisolated_modifier(),
            member_access.render(),
            selection_set_type
        ));
        result.push_str(&indent(&selection_body, 4));
        result.push_str("\n  }\n");

        // Deferred fragments metadata, rendered inside the operation class as a
        // `section:` (Swift 2.0.0): preceded by a blank line, omitted when empty.
        if self.operation.contains_deferred_fragment {
            let deferred = DeferredFragmentsMetadataTemplate {
                operation: &self.operation,
                config: &self.config,
                render_access_control: parent_access.render(),
            };
            let deferred_output = deferred.render();
            if !deferred_output.is_empty() {
                result.push('\n');
                result.push_str(&indent(&deferred_output, 2));
                result.push('\n');
            }
        }

        result.push_str("}\n");

        result
    }
}

impl OperationDefinitionTemplate {
    /// Renders the operation struct declaration.
    fn render_operation_declaration(
        &self,
        parent_access: &AccessControlRenderer,
        member_access: &AccessControlRenderer,
    ) -> String {
        let definition_name = generated_definition_name_capitalized(
            &self.operation.definition.name,
            &self.operation.definition.operation_type.to_string(),
            self.operation.definition.is_local_cache_mutation(),
            &self.config.capitalizer,
        );
        let protocol_name = rendered_protocol_name(&self.operation.definition.operation_type);

        format!(
            "{}{}struct {}: {} {{\n  {}static let operationName: String = \"{}\"\n",
            self.config.nonisolated_modifier(),
            parent_access.render(),
            definition_name,
            protocol_name,
            member_access.render(),
            self.operation.definition.name,
        )
    }

    /// Renders the DocumentType section.
    fn render_document_type(&self, member_access: &AccessControlRenderer) -> String {
        let include_fragments = !self.operation.referenced_fragments.is_empty();
        let include_definition = self
            .config
            .options()
            .operation_document_format
            .contains(OperationDocumentFormat::DEFINITION);
        let include_operation_id = self
            .config
            .options()
            .operation_document_format
            .contains(OperationDocumentFormat::OPERATION_ID);

        let mut result = format!(
            "  {}static let operationDocument: {}.OperationDocument = .init(\n",
            member_access.render(),
            self.config.apollo_api_target_name(),
        );

        if include_operation_id {
            let op_id = self
                .operation_identifier
                .as_deref()
                .expect("operationIdentifier is missing.");
            result.push_str(&format!("    operationIdentifier: \"{}\"", op_id));
            if include_definition {
                result.push(',');
            }
            result.push('\n');
        }

        if include_definition {
            let formatted_source = format!(
                "#\"{}\"#",
                converted_to_single_line(&self.operation.definition.source)
            );
            result.push_str(&format!(
                "    definition: .init(\n      {}",
                formatted_source
            ));

            if include_fragments {
                result.push_str(",\n      fragments: [");
                let fragment_refs: Vec<String> = self
                    .operation
                    .referenced_fragments
                    .iter()
                    .map(|f| {
                        format!(
                            "{}.self",
                            as_fragment_name(f.name(), &self.config.capitalizer)
                        )
                    })
                    .collect();
                result.push_str(&fragment_refs.join(", "));
                result.push(']');
            }

            result.push_str("\n    ))\n");
        } else {
            result.push_str("  )\n");
        }

        result
    }

    /// Converts the operation's compilation result variables to the template renderer's
    /// VariableDefinition type.
    fn convert_variables(&self) -> Vec<VariableDefinition> {
        self.operation
            .definition
            .variables
            .iter()
            .map(|v| VariableDefinition {
                name: v.name.clone(),
                type_: v.type_.clone(),
                default_value: v.default_value.clone(),
            })
            .collect()
    }
}

/// Returns the Swift protocol name for the given operation type.
fn rendered_protocol_name(op_type: &OperationType) -> &'static str {
    match op_type {
        OperationType::Query => "GraphQLQuery",
        OperationType::Mutation => "GraphQLMutation",
        OperationType::Subscription => "GraphQLSubscription",
    }
}

/// Indents every non-empty line by the specified number of spaces.
fn indent(text: &str, spaces: usize) -> String {
    let prefix: String = " ".repeat(spaces);
    text.lines()
        .map(|line| {
            // Like TemplateString.joinedAsLines: only strictly empty lines stay unindented.
            if line.is_empty() {
                String::new()
            } else {
                format!("{}{}", prefix, line)
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rendered_protocol_name_query() {
        assert_eq!(
            rendered_protocol_name(&OperationType::Query),
            "GraphQLQuery"
        );
    }

    #[test]
    fn test_rendered_protocol_name_mutation() {
        assert_eq!(
            rendered_protocol_name(&OperationType::Mutation),
            "GraphQLMutation"
        );
    }

    #[test]
    fn test_rendered_protocol_name_subscription() {
        assert_eq!(
            rendered_protocol_name(&OperationType::Subscription),
            "GraphQLSubscription"
        );
    }

    #[test]
    fn test_indent_basic() {
        assert_eq!(indent("hello", 2), "  hello");
    }

    #[test]
    fn test_indent_multiline() {
        assert_eq!(indent("hello\nworld", 4), "    hello\n    world");
    }

    #[test]
    fn test_indent_empty_lines() {
        assert_eq!(indent("hello\n\nworld", 2), "  hello\n\n  world");
    }
}
