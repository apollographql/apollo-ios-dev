//! Schema module namespace template for Apollo iOS code generation.
//!
//! Mirrors Swift's `SchemaModuleNamespaceTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/SchemaModuleNamespaceTemplate.swift`.

use crate::templates::rendering_helpers::string_casing::first_uppercased;
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, Scope, TemplateRenderer, TemplateTarget,
};

/// Provides the format to define a namespace that wraps other templates
/// to prevent naming collisions in Swift code.
///
/// Mirrors Swift's `SchemaModuleNamespaceTemplate` struct.
pub struct SchemaModuleNamespaceTemplate {
    pub config: ConfigurationContext,
}

impl TemplateRenderer for SchemaModuleNamespaceTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::ModuleFile
    }

    fn render_body_template(
        &self,
        _non_fatal_error_recorder: &NonFatalErrorRecorder,
    ) -> String {
        let access_control = self.access_control_renderer(Scope::Namespace).render();
        let namespace = first_uppercased(self.config.schema_namespace());
        format!("{}enum {} {{ }}\n", access_control, namespace)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;
    use crate::templates::ConfigurationContext;

    fn make_config(json: &str) -> ConfigurationContext {
        let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
        ConfigurationContext::new(config, None)
    }

    fn config_with_namespace_and_module(ns: &str, module_json: &str) -> ConfigurationContext {
        make_config(&format!(
            r#"{{
            "schemaNamespace": "{}",
            "input": {{}},
            "output": {{
                "schemaTypes": {{ "path": "./gen", "moduleType": {} }},
                "operations": {{"inSchemaModule": {{}}}},
                "testMocks": {{"none": {{}}}}
            }}
        }}"#,
            ns, module_json
        ))
    }

    fn render_body(template: &SchemaModuleNamespaceTemplate) -> String {
        let recorder = NonFatalErrorRecorder::new();
        template.render_body_template(&recorder)
    }

    // MARK: - Casing Tests

    #[test]
    fn test_render_lowercase_schema_name_capitalized() {
        let template = SchemaModuleNamespaceTemplate {
            config: config_with_namespace_and_module(
                "schema",
                r#"{"embeddedInTarget": {"name": "TestTarget"}}"#,
            ),
        };
        let actual = render_body(&template);
        let expected = "enum Schema { }\n";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_render_uppercase_schema_name() {
        let template = SchemaModuleNamespaceTemplate {
            config: config_with_namespace_and_module(
                "SCHEMA",
                r#"{"embeddedInTarget": {"name": "TestTarget"}}"#,
            ),
        };
        let actual = render_body(&template);
        let expected = "enum SCHEMA { }\n";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_render_capitalized_schema_name() {
        let template = SchemaModuleNamespaceTemplate {
            config: config_with_namespace_and_module(
                "MySchema",
                r#"{"embeddedInTarget": {"name": "TestTarget"}}"#,
            ),
        };
        let actual = render_body(&template);
        let expected = "enum MySchema { }\n";
        assert_eq!(actual, expected);
    }

    // MARK: - Access Level Tests

    #[test]
    fn test_render_embedded_internal_no_access_modifier() {
        let template = SchemaModuleNamespaceTemplate {
            config: config_with_namespace_and_module(
                "MySchema",
                r#"{"embeddedInTarget": {"name": "TestTarget"}}"#,
            ),
        };
        let actual = render_body(&template);
        let expected = "enum MySchema { }\n";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_render_embedded_public_has_public_access() {
        let template = SchemaModuleNamespaceTemplate {
            config: config_with_namespace_and_module(
                "MySchema",
                r#"{"embeddedInTarget": {"name": "TestTarget", "accessModifier": "public"}}"#,
            ),
        };
        let actual = render_body(&template);
        let expected = "public enum MySchema { }\n";
        assert_eq!(actual, expected);
    }
}
