//! Interface type template for Apollo iOS code generation.
//!
//! Mirrors Swift's `InterfaceTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/InterfaceTemplate.swift`.

use std::sync::Arc;

use graphql_compiler::schema::{GraphQLInterfaceType, GraphQLNamedType};

use crate::templates::rendering_helpers::graphql_name_rendering::{render_named_type, RenderContext};
use crate::templates::rendering_helpers::template_string_documentation::render_documentation;
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, SchemaFileType, TemplateRenderer,
    TemplateTarget,
};

/// Provides the format to convert a GraphQL Interface into Swift code.
///
/// Mirrors Swift's `InterfaceTemplate` struct.
pub struct InterfaceTemplate {
    pub graphql_interface: Arc<GraphQLInterfaceType>,
    pub config: ConfigurationContext,
}

impl TemplateRenderer for InterfaceTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::SchemaFile(SchemaFileType::Interface)
    }

    fn render_body_template(
        &self,
        _non_fatal_error_recorder: &NonFatalErrorRecorder,
    ) -> String {
        let mut parts: Vec<String> = Vec::new();

        // Documentation
        if let Some(doc) = render_documentation(
            self.graphql_interface.documentation.as_deref(),
            &self.config,
        ) {
            parts.push(doc);
        }

        // Type name documentation (for custom names)
        if let Some(type_doc) = self.graphql_interface.name.type_name_documentation() {
            parts.push(type_doc);
        }

        let typename = render_named_type(
            &GraphQLNamedType::Interface(Arc::clone(&self.graphql_interface)),
            &RenderContext::Typename { is_input_value: false },
        );

        let key_fields = self.render_key_fields();
        let implementing_objects = self.render_implementing_objects();

        parts.push(format!(
            "{}static let {} = {}.Interface(\n  name: \"{}\",\n  keyFields: {},\n  implementingObjects: {}\n)",
            self.config.nonisolated_modifier(),
            typename,
            self.config.apollo_api_target_name(),
            self.graphql_interface.name.schema_name,
            key_fields,
            implementing_objects,
        ));

        parts.join("\n")
    }
}

impl InterfaceTemplate {
    fn render_key_fields(&self) -> String {
        match &self.graphql_interface.key_fields {
            None => "nil".to_string(),
            Some(fields) if fields.is_empty() => "nil".to_string(),
            Some(fields) => {
                let quoted: Vec<String> = fields.iter().map(|s| format!("\"{}\"", s)).collect();
                if quoted.len() == 1 {
                    format!("[{}]", quoted[0])
                } else {
                    let inner = quoted
                        .iter()
                        .map(|s| format!("    {}", s))
                        .collect::<Vec<_>>()
                        .join(",\n");
                    format!("[\n{}\n  ]", inner)
                }
            }
        }
    }

    fn render_implementing_objects(&self) -> String {
        let items: Vec<String> = self
            .graphql_interface
            .implementing_objects
            .iter()
            .map(|obj| {
                let type_name = render_named_type(
                    &GraphQLNamedType::Object(Arc::clone(obj)),
                    &RenderContext::Typename { is_input_value: false },
                );
                format!("\"{}\"", type_name)
            })
            .collect();

        if items.is_empty() {
            "[]".to_string()
        } else if items.len() == 1 {
            format!("[{}]", items[0])
        } else {
            let inner = items
                .iter()
                .map(|s| format!("    {}", s))
                .collect::<Vec<_>>()
                .join(",\n");
            format!("[\n{}\n  ]", inner)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;
    use crate::templates::ConfigurationContext;
    use crate::templates::rendering_helpers::string_casing::first_uppercased;
    use graphql_compiler::graphql_name::GraphQLName;
    use graphql_compiler::schema::GraphQLObjectType;
    use indexmap::IndexMap;

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

    fn make_interface(
        name: &str,
        custom_name: Option<&str>,
        key_fields: Option<Vec<String>>,
        implementing_objects: Vec<Arc<GraphQLObjectType>>,
        documentation: Option<String>,
    ) -> Arc<GraphQLInterfaceType> {
        let mut gql_name = GraphQLName::new(name.to_string());
        if let Some(cn) = custom_name {
            gql_name.custom_name = Some(cn.to_string());
        }
        Arc::new(GraphQLInterfaceType {
            name: gql_name,
            documentation,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields,
            implementing_objects,
        })
    }

    fn make_object(name: &str) -> Arc<GraphQLObjectType> {
        Arc::new(GraphQLObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        })
    }

    fn render_body(template: &InterfaceTemplate) -> String {
        let recorder = NonFatalErrorRecorder::new();
        template.render_body_template(&recorder)
    }

    // MARK: - Casing Tests

    #[test]
    fn test_render_given_schema_interface_correctly_cased() {
        let iface = make_interface("aDog", None, None, vec![], None);
        let template = InterfaceTemplate {
            graphql_interface: iface,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("static let ADog = ApolloAPI.Interface("),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("name: \"aDog\""),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("keyFields: nil"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("implementingObjects: []"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Documentation Tests

    #[test]
    fn test_render_documentation_include_generates_doc_comment() {
        let iface = make_interface(
            "Dog",
            None,
            None,
            vec![],
            Some("This is some great documentation!".to_string()),
        );
        let template = InterfaceTemplate {
            graphql_interface: iface,
            config: config_with_docs(true),
        };
        let actual = render_body(&template);
        assert!(
            actual.starts_with("/// This is some great documentation!\nnonisolated static let Dog = ApolloAPI.Interface("),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_documentation_exclude_no_doc_comment() {
        let iface = make_interface(
            "Dog",
            None,
            None,
            vec![],
            Some("This is some great documentation!".to_string()),
        );
        let template = InterfaceTemplate {
            graphql_interface: iface,
            config: config_with_docs(false),
        };
        let actual = render_body(&template);
        assert!(
            !actual.contains("///"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.starts_with("nonisolated static let Dog = ApolloAPI.Interface("),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Reserved Keyword Tests

    #[test]
    fn test_render_reserved_keyword_has_suffixed_type() {
        for keyword in &["Type", "type"] {
            let iface = make_interface(keyword, None, None, vec![], None);
            let template = InterfaceTemplate {
                graphql_interface: iface,
                config: default_config(),
            };
            let actual = render_body(&template);
            let expected_name = format!("{}_Interface", first_uppercased(keyword));
            assert!(
                actual.contains(&format!("static let {} = ApolloAPI.Interface(", expected_name)),
                "keyword={}, actual:\n{}",
                keyword,
                actual
            );
            assert!(
                actual.contains(&format!("name: \"{}\"", keyword)),
                "keyword={}, actual:\n{}",
                keyword,
                actual
            );
        }
    }

    // MARK: - Schema Customization Tests

    #[test]
    fn test_render_with_custom_name() {
        let iface = make_interface("MyInterface", Some("MyCustomInterface"), None, vec![], None);
        let template = InterfaceTemplate {
            graphql_interface: iface,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("// Renamed from GraphQL schema value: 'MyInterface'"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("static let MyCustomInterface = ApolloAPI.Interface("),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("name: \"MyInterface\""),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Key Fields Tests

    #[test]
    fn test_render_with_key_fields_includes_them() {
        let iface = make_interface(
            "IndexedNode",
            None,
            Some(vec!["parentID".to_string(), "index".to_string()]),
            vec![],
            None,
        );
        let template = InterfaceTemplate {
            graphql_interface: iface,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("keyFields: ["),
            "keyFields should appear in output, actual:\n{}",
            actual
        );
        assert!(
            actual.contains("\"parentID\""),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("\"index\""),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_no_key_fields_renders_nil() {
        let iface = make_interface("Dog", None, None, vec![], None);
        let template = InterfaceTemplate {
            graphql_interface: iface,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("keyFields: nil"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Implementing Objects Tests

    #[test]
    fn test_render_with_implementing_objects_includes_them() {
        let obj1 = make_object("MyObject");
        let obj2 = make_object("SecondObject");
        let iface = make_interface("MyInterface", None, None, vec![obj1, obj2], None);
        let template = InterfaceTemplate {
            graphql_interface: iface,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("implementingObjects: ["),
            "implementingObjects should appear in output, actual:\n{}",
            actual
        );
        assert!(
            actual.contains("\"MyObject\""),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("\"SecondObject\""),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_no_implementing_objects_renders_empty_array() {
        let iface = make_interface("Dog", None, None, vec![], None);
        let template = InterfaceTemplate {
            graphql_interface: iface,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("implementingObjects: []"),
            "actual:\n{}",
            actual
        );
    }
}
