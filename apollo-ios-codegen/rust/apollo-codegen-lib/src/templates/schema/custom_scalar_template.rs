//! Custom scalar type template for Apollo iOS code generation.
//!
//! Mirrors Swift's `CustomScalarTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/CustomScalarTemplate.swift`.

use std::sync::Arc;

use graphql_compiler::schema::{GraphQLNamedType, GraphQLScalarType};

use crate::templates::rendering_helpers::graphql_name_rendering::{
    render_named_type, RenderContext,
};
use crate::templates::rendering_helpers::template_string_documentation::render_documentation;
use crate::templates::{
    ConfigurationContext, HeaderCommentTemplate, NonFatalErrorRecorder, SchemaFileType, Scope,
    TemplateRenderer, TemplateTarget,
};

/// Provides the format to convert a GraphQL Custom Scalar into Swift code.
///
/// Mirrors Swift's `CustomScalarTemplate` struct.
pub struct CustomScalarTemplate {
    pub graphql_scalar: Arc<GraphQLScalarType>,
    pub config: ConfigurationContext,
}

impl TemplateRenderer for CustomScalarTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::SchemaFile(SchemaFileType::CustomScalar)
    }

    fn render_header_template(
        &self,
        _non_fatal_error_recorder: &NonFatalErrorRecorder,
    ) -> Option<String> {
        Some(HeaderCommentTemplate::editable_file_header(
            "implement advanced custom scalar functionality.",
        ))
    }

    fn render_body_template(&self, _non_fatal_error_recorder: &NonFatalErrorRecorder) -> String {
        let mut parts: Vec<String> = Vec::new();

        // Documentation (includes specifiedByURL if present)
        let doc_template = self.documentation_template();
        if let Some(doc) = render_documentation(doc_template.as_deref(), &self.config) {
            parts.push(doc);
        }

        // Type name documentation (for custom names)
        if let Some(type_doc) = self.graphql_scalar.name.type_name_documentation() {
            parts.push(type_doc);
        }

        let access_control = self.access_control_renderer(Scope::Parent).render();
        let typename = render_named_type(
            &GraphQLNamedType::Scalar(Arc::clone(&self.graphql_scalar)),
            &RenderContext::Typename {
                is_input_value: false,
            },
        );

        parts.push(format!(
            "{}typealias {} = String\n",
            access_control, typename,
        ));

        parts.join("\n")
    }
}

impl CustomScalarTemplate {
    /// Builds the documentation string, appending specifiedByURL if present.
    ///
    /// Mirrors Swift's `CustomScalarTemplate.documentationTemplate` property.
    ///
    /// Swift appends `Specified by: [](url)` when `GraphQLScalarType.specifiedByURL` is set,
    /// but that property is read from the JavaScript value's `specifiedByUrl` key while
    /// graphql-js exposes it as `specifiedByURL`, so it is never populated and the Swift CLI
    /// never emits the line. The URL is therefore intentionally ignored here.
    fn documentation_template(&self) -> Option<String> {
        let _ = &self.graphql_scalar.specified_by_url;
        self.graphql_scalar.documentation.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;
    use crate::templates::ConfigurationContext;
    use graphql_compiler::graphql_name::GraphQLName;

    fn make_config(json: &str) -> ConfigurationContext {
        let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
        ConfigurationContext::new(config, None)
    }

    fn default_config() -> ConfigurationContext {
        make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"embeddedInTarget": {"name": "TestTarget"}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        )
    }

    fn spm_config() -> ConfigurationContext {
        make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        )
    }

    fn other_config() -> ConfigurationContext {
        make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"other": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        )
    }

    fn embedded_internal_config() -> ConfigurationContext {
        make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"embeddedInTarget": {"name": "TestTarget"}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        )
    }

    fn embedded_public_config() -> ConfigurationContext {
        make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"embeddedInTarget": {"name": "TestTarget", "accessModifier": "public"}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        )
    }

    fn config_with_docs(include: bool) -> ConfigurationContext {
        let doc_option = if include { "include" } else { "exclude" };
        make_config(&format!(
            r#"{{
            "schemaNamespace": "TestSchema",
            "input": {{}},
            "output": {{
                "schemaTypes": {{ "path": "./gen", "moduleType": {{"embeddedInTarget": {{"name": "TestTarget"}}}} }},
                "operations": {{"inSchemaModule": {{}}}},
                "testMocks": {{"none": {{}}}}
            }},
            "options": {{ "schemaDocumentation": "{}" }}
        }}"#,
            doc_option
        ))
    }

    fn make_scalar(
        name: &str,
        custom_name: Option<&str>,
        documentation: Option<&str>,
        specified_by_url: Option<&str>,
    ) -> Arc<GraphQLScalarType> {
        let mut gql_name = GraphQLName::new(name.to_string());
        if let Some(cn) = custom_name {
            gql_name.custom_name = Some(cn.to_string());
        }
        Arc::new(GraphQLScalarType {
            name: gql_name,
            documentation: documentation.map(|s| s.to_string()),
            specified_by_url: specified_by_url.map(|s| s.to_string()),
        })
    }

    fn render_body(template: &CustomScalarTemplate) -> String {
        let recorder = NonFatalErrorRecorder::new();
        template.render_body_template(&recorder)
    }

    // MARK: - Import Statement Tests (via full render)

    #[test]
    fn test_render_generates_custom_scalar_import() {
        let scalar = make_scalar("aCustomScalar", None, None, None);
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: default_config(),
        };
        let result = template.render();
        assert!(
            result.body.contains("import ApolloAPI"),
            "body:\n{}",
            result.body
        );
        // 2.0.0+: custom scalar files import ApolloAPI with the Internal and Execution SPIs
        assert!(
            result
                .body
                .contains("@_spi(Internal) @_spi(Execution) import ApolloAPI"),
            "body:\n{}",
            result.body
        );
    }

    // MARK: - Casing Tests

    #[test]
    fn test_render_name_first_uppercased() {
        let scalar = make_scalar("aCustomScalar", None, None, None);
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("typealias ACustomScalar = String"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Header Tests

    #[test]
    fn test_render_editable_header() {
        let scalar = make_scalar("MyCustomScalar", None, None, None);
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: default_config(),
        };
        let recorder = NonFatalErrorRecorder::new();
        let header = template.render_header_template(&recorder);
        assert!(header.is_some());
        let header_str = header.unwrap();
        assert!(
            !header_str.contains("should not be edited"),
            "header:\n{}",
            header_str
        );
        assert!(
            header_str.contains("can be edited"),
            "header:\n{}",
            header_str
        );
    }

    // MARK: - Typealias Definition Tests

    #[test]
    fn test_render_string_typealias() {
        let scalar = make_scalar("MyCustomScalar", None, None, None);
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("typealias MyCustomScalar = String"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Access Level Tests

    #[test]
    fn test_render_spm_public_access() {
        let scalar = make_scalar("MyCustomScalar", None, None, None);
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("public typealias MyCustomScalar = String"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_other_public_access() {
        let scalar = make_scalar("MyCustomScalar", None, None, None);
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: other_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("public typealias MyCustomScalar = String"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_embedded_internal_no_access() {
        let scalar = make_scalar("MyCustomScalar", None, None, None);
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: embedded_internal_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("typealias MyCustomScalar = String"),
            "actual:\n{}",
            actual
        );
        assert!(!actual.contains("public"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_embedded_public_no_access_on_parent() {
        let scalar = make_scalar("MyCustomScalar", None, None, None);
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: embedded_public_config(),
        };
        let actual = render_body(&template);
        // Parent scope with embedded = no access modifier
        assert!(
            actual.contains("typealias MyCustomScalar = String"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Documentation Tests

    #[test]
    fn test_render_documentation_include() {
        let scalar = make_scalar(
            "CustomScalar",
            None,
            Some("This is some great documentation!"),
            None,
        );
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: config_with_docs(true),
        };
        let actual = render_body(&template);
        let expected = "\
/// This is some great documentation!
typealias CustomScalar = String
";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_render_documentation_with_specified_by_url() {
        let scalar = make_scalar(
            "CustomScalar",
            None,
            Some("This is some great documentation!"),
            Some("http://www.apollographql.com/scalarSpec"),
        );
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: config_with_docs(true),
        };
        let actual = render_body(&template);
        // The Swift CLI never renders the URL (see `documentation_template`).
        let expected = "\
/// This is some great documentation!
typealias CustomScalar = String
";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_render_documentation_exclude() {
        let scalar = make_scalar(
            "CustomScalar",
            None,
            Some("This is some great documentation!"),
            None,
        );
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: config_with_docs(false),
        };
        let actual = render_body(&template);
        let expected = "typealias CustomScalar = String\n";
        assert_eq!(actual, expected);
    }

    // MARK: - Reserved Keyword Tests

    #[test]
    fn test_render_reserved_keyword_suffixed() {
        for keyword in &["Type", "type"] {
            let scalar = make_scalar(keyword, None, None, None);
            let template = CustomScalarTemplate {
                graphql_scalar: scalar,
                config: default_config(),
            };
            let actual = render_body(&template);
            let expected_name = format!(
                "{}_Scalar",
                crate::templates::rendering_helpers::string_casing::first_uppercased(keyword)
            );
            assert!(
                actual.contains(&format!("typealias {} = String", expected_name)),
                "keyword={}, actual:\n{}",
                keyword,
                actual
            );
        }
    }

    // MARK: - Schema Customization Tests

    #[test]
    fn test_render_with_custom_name() {
        let scalar = make_scalar("MyScalar", Some("MyCustomScalar"), None, None);
        let template = CustomScalarTemplate {
            graphql_scalar: scalar,
            config: default_config(),
        };
        let actual = render_body(&template);
        let expected = "\
// Renamed from GraphQL schema value: 'MyScalar'
typealias MyCustomScalar = String
";
        assert_eq!(actual, expected);
    }
}
