//! Local cache mutation definition template for code generation.
//!
//! Generates Swift structs for local cache mutations. Structurally similar to
//! OperationDefinitionTemplate but uses MutableSelectionSet and LocalCacheMutation
//! protocol, and omits the operationDocument section.
//!
//! Mirrors Swift's `LocalCacheMutationDefinitionTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/LocalCacheMutationDefinitionTemplate.swift`.

use std::sync::Arc;

use crate::templates::rendering_helpers::ir_definition_rendering::rendered_selection_set_type;
use crate::templates::rendering_helpers::operation_template_renderer::{
    self, VariableDefinition,
};
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, Scope,
    TemplateRenderer, TemplateTarget,
};

use super::rendering_helpers::ir_definition_rendering::generated_definition_name_capitalized;
use super::rendering_helpers::selection_set_initializer_check::should_generate_selection_set_initializers;
use super::selection_set_template::SelectionSetTemplate;

/// Template for generating Swift code for a local cache mutation definition.
///
/// Mirrors Swift's `LocalCacheMutationDefinitionTemplate` struct.
pub struct LocalCacheMutationDefinitionTemplate {
    pub operation: Arc<ir::Operation>,
    pub config: ConfigurationContext,
    /// The schema's referenced types, used to resolve nested input object types when
    /// rendering variable default values.
    pub referenced_types: Arc<ir::ReferencedTypes>,
}

impl TemplateRenderer for LocalCacheMutationDefinitionTemplate {
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

    fn render_body_template(
        &self,
        non_fatal_error_recorder: &NonFatalErrorRecorder,
    ) -> String {
        let member_access = self.access_control_renderer(Scope::Member);
        let parent_access = self.access_control_renderer(Scope::Parent);
        let member_access_str = member_access.render();

        let mut result = String::new();

        // Class declaration with LocalCacheMutation conformance
        let definition_name = generated_definition_name_capitalized(
            &self.operation.definition.name,
            &self.operation.definition.operation_type.to_string(),
            true, // is_local_cache_mutation
            &self.config.capitalizer,
        );
        result.push_str(&format!(
            "{}{}struct {}: LocalCacheMutation {{\n",
            self.config.nonisolated_modifier(),
            parent_access.render(),
            definition_name,
        ));

        // operationType static let
        result.push_str(&format!(
            "  {}static let operationType: GraphQLOperationType = .{}\n",
            member_access_str,
            self.operation.definition.operation_type,
        ));

        // Variable properties (section: blank line before if non-empty)
        let variables = self.convert_variables();
        if !variables.is_empty() {
            let var_props = operation_template_renderer::render_variable_properties(
                &variables,
                &self.config,
            );
            result.push('\n');
            result.push_str(&indent(&var_props, 2));
            result.push('\n');
        }

        // Initializer (always preceded by blank line)
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

        // Variable accessors (graphQLOperation: false for local cache mutations)
        let var_accessors = operation_template_renderer::render_variable_accessors(
            &variables,
            &self.config,
            false,
        );
        if !var_accessors.is_empty() {
            result.push('\n');
            result.push_str(&indent(&var_accessors, 2));
            result.push('\n');
        }

        // Selection set (Data struct) - uses MutableSelectionSet
        let selection_set_type = rendered_selection_set_type(&self.config, true);
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
            member_access_str, selection_set_type
        ));
        result.push_str(&indent(&selection_body, 4));
        result.push_str("\n  }\n");

        result.push_str("}\n");

        result
    }
}

impl LocalCacheMutationDefinitionTemplate {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rendered_selection_set_type_is_mutable() {
        let config: crate::config::ApolloCodegenConfiguration =
            serde_json::from_str(r#"{
                "schemaNamespace": "TestSchema",
                "input": {},
                "output": {
                    "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
                    "operations": {"inSchemaModule": {}},
                    "testMocks": {"none": {}}
                }
            }"#).unwrap();
        let ctx = ConfigurationContext::new(config, None);
        let result = rendered_selection_set_type(&ctx, true);
        assert_eq!(result, "TestSchema.MutableSelectionSet");
    }

    #[test]
    fn test_indent() {
        assert_eq!(indent("hello", 2), "  hello");
        assert_eq!(indent("a\nb", 4), "    a\n    b");
    }
}
