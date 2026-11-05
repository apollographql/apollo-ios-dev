//! Object type template for Apollo iOS code generation.
//!
//! Mirrors Swift's `ObjectTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/ObjectTemplate.swift`.

use std::sync::Arc;

use graphql_compiler::schema::{GraphQLNamedType, GraphQLObjectType};

use crate::templates::rendering_helpers::graphql_name_rendering::{
    render_named_type, RenderContext,
};
use crate::templates::rendering_helpers::string_casing::first_uppercased;
use crate::templates::rendering_helpers::template_string_documentation::render_documentation;
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, SchemaFileType, TemplateRenderer, TemplateTarget,
};

/// Provides the format to convert a GraphQL Object into Swift code.
///
/// Mirrors Swift's `ObjectTemplate` struct.
pub struct ObjectTemplate {
    pub graphql_object: Arc<GraphQLObjectType>,
    pub config: ConfigurationContext,
}

impl TemplateRenderer for ObjectTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::SchemaFile(SchemaFileType::Object)
    }

    fn render_body_template(&self, _non_fatal_error_recorder: &NonFatalErrorRecorder) -> String {
        let mut parts: Vec<String> = Vec::new();

        // Documentation
        if let Some(doc) =
            render_documentation(self.graphql_object.documentation.as_deref(), &self.config)
        {
            parts.push(doc);
        }

        // Type name documentation (for custom names)
        if let Some(type_doc) = self.graphql_object.name.type_name_documentation() {
            parts.push(type_doc);
        }

        let typename = render_named_type(
            &GraphQLNamedType::Object(Arc::clone(&self.graphql_object)),
            &RenderContext::Typename {
                is_input_value: false,
            },
        );

        let implemented_interfaces = self.render_implemented_interfaces();

        let key_fields = self.render_key_fields();

        parts.push(format!(
            "{}static let {} = {}.Object(\n  typename: \"{}\",\n  implementedInterfaces: {},\n  keyFields: {}\n)",
            self.config.nonisolated_modifier(),
            typename,
            self.config.apollo_api_target_name(),
            self.graphql_object.name.schema_name,
            implemented_interfaces,
            key_fields,
        ));

        parts.join("\n")
    }
}

impl ObjectTemplate {
    fn render_key_fields(&self) -> String {
        match &self.graphql_object.key_fields {
            None => "nil".to_string(),
            Some(fields) if fields.is_empty() => "nil".to_string(),
            Some(fields) => render_list_of_quoted_strings(fields),
        }
    }

    fn render_implemented_interfaces(&self) -> String {
        if self.graphql_object.interfaces.is_empty() {
            return "[]".to_string();
        }

        let is_in_module = self.config.output().schema_types.is_in_module();
        let namespace_prefix = if !is_in_module {
            format!("{}.", first_uppercased(self.config.schema_namespace()))
        } else {
            String::new()
        };

        let items: Vec<String> = self
            .graphql_object
            .interfaces
            .iter()
            .map(|iface| {
                let iface_name = render_named_type(
                    &GraphQLNamedType::Interface(Arc::clone(iface)),
                    &RenderContext::Typename {
                        is_input_value: false,
                    },
                );
                format!("{}Interfaces.{}.self", namespace_prefix, iface_name)
            })
            .collect();

        render_bracketed_list(&items)
    }
}

/// Renders a list of quoted strings in Swift array literal format.
/// Single item: `["item"]`, multiple items: multi-line with indentation.
fn render_list_of_quoted_strings(items: &[String]) -> String {
    let quoted: Vec<String> = items.iter().map(|s| format!("\"{}\"", s)).collect();
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

/// Renders a bracketed list of items with proper Swift formatting.
/// Single item: `[item]`, multiple items: multi-line with indentation.
fn render_bracketed_list(items: &[String]) -> String {
    if items.len() == 1 {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;
    use crate::templates::ConfigurationContext;

    /// Whether this Apollo iOS version renders `@typePolicy` key fields into
    /// `ApolloAPI.Object(keyFields:)` (1.17.0+). The parity harness is the source of truth.
    const RENDERS_KEY_FIELDS: bool = true;

    fn assert_key_fields(actual: &str, expected: &str) {
        if RENDERS_KEY_FIELDS {
            assert!(actual.contains(expected), "actual:\n{}", actual);
        } else {
            assert!(!actual.contains("keyFields"), "actual:\n{}", actual);
        }
    }
    use graphql_compiler::graphql_name::GraphQLName;
    use graphql_compiler::schema::GraphQLInterfaceType;
    use indexmap::IndexMap;

    fn make_config(json: &str) -> ConfigurationContext {
        let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
        ConfigurationContext::new(config, None)
    }

    /// Default config: embedded in target (not in module), schemaNamespace "TestSchema"
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

    fn make_object(
        name: &str,
        custom_name: Option<&str>,
        interfaces: Vec<Arc<GraphQLInterfaceType>>,
        key_fields: Option<Vec<String>>,
        documentation: Option<String>,
    ) -> Arc<GraphQLObjectType> {
        let mut gql_name = GraphQLName::new(name.to_string());
        if let Some(cn) = custom_name {
            gql_name.custom_name = Some(cn.to_string());
        }
        Arc::new(GraphQLObjectType {
            name: gql_name,
            documentation,
            fields: IndexMap::new(),
            interfaces,
            key_fields,
        })
    }

    fn make_interface(name: &str, custom_name: Option<&str>) -> Arc<GraphQLInterfaceType> {
        let mut gql_name = GraphQLName::new(name.to_string());
        if let Some(cn) = custom_name {
            gql_name.custom_name = Some(cn.to_string());
        }
        Arc::new(GraphQLInterfaceType {
            name: gql_name,
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
            implementing_objects: vec![],
        })
    }

    fn render_body(template: &ObjectTemplate) -> String {
        let recorder = NonFatalErrorRecorder::new();
        template.render_body_template(&recorder)
    }

    // MARK: - Boilerplate tests

    #[test]
    fn test_render_generates_closing_paren() {
        let obj = make_object("Dog", None, vec![], None, None);
        let template = ObjectTemplate {
            graphql_object: obj,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.ends_with("\n)"),
            "Should end with closing paren, got:\n{}",
            actual
        );
    }

    // MARK: - Class Definition Tests

    #[test]
    fn test_render_given_schema_type_generates_correctly_cased() {
        let obj = make_object("dog", None, vec![], None, None);
        let template = ObjectTemplate {
            graphql_object: obj,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("static let Dog = ApolloAPI.Object("),
            "actual:\n{}",
            actual
        );
        assert!(actual.contains("typename: \"dog\""), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_interfaces_embedded_in_target_has_schema_namespace() {
        let interfaces = vec![make_interface("Animal", None), make_interface("Pet", None)];
        let obj = make_object("Dog", None, interfaces, None, None);
        let template = ObjectTemplate {
            graphql_object: obj,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("TestSchema.Interfaces.Animal.self"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("TestSchema.Interfaces.Pet.self"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_interfaces_not_embedded_no_schema_namespace() {
        let interfaces = vec![make_interface("Animal", None), make_interface("Pet", None)];
        let obj = make_object("Dog", None, interfaces, None, None);
        let template = ObjectTemplate {
            graphql_object: obj,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("Interfaces.Animal.self"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("Interfaces.Pet.self"),
            "actual:\n{}",
            actual
        );
        // Should NOT have schema namespace prefix
        assert!(
            !actual.contains("TestSchema.Interfaces"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_no_interfaces_generates_empty_array() {
        let obj = make_object("Dog", None, vec![], None, None);
        let template = ObjectTemplate {
            graphql_object: obj,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("implementedInterfaces: []"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_single_key_field() {
        let obj = make_object("Dog", None, vec![], Some(vec!["id".to_string()]), None);
        let template = ObjectTemplate {
            graphql_object: obj,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert_key_fields(&actual, "keyFields: [\"id\"]");
    }

    #[test]
    fn test_render_multiple_key_fields() {
        let obj = make_object(
            "Dog",
            None,
            vec![],
            Some(vec!["id".to_string(), "species".to_string()]),
            None,
        );
        let template = ObjectTemplate {
            graphql_object: obj,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert_key_fields(&actual, "keyFields: [\n");
        if RENDERS_KEY_FIELDS {
            assert!(actual.contains("\"id\""), "actual:\n{}", actual);
            assert!(actual.contains("\"species\""), "actual:\n{}", actual);
        }
    }

    // MARK: - Documentation Tests

    #[test]
    fn test_render_documentation_include_generates_doc_comment() {
        let obj = make_object(
            "Dog",
            None,
            vec![],
            None,
            Some("This is some great documentation!".to_string()),
        );
        let template = ObjectTemplate {
            graphql_object: obj,
            config: config_with_docs(true),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("/// This is some great documentation!"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("static let Dog = ApolloAPI.Object("),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_documentation_exclude_no_doc_comment() {
        let obj = make_object(
            "Dog",
            None,
            vec![],
            None,
            Some("This is some great documentation!".to_string()),
        );
        let template = ObjectTemplate {
            graphql_object: obj,
            config: config_with_docs(false),
        };
        let actual = render_body(&template);
        assert!(!actual.contains("///"), "actual:\n{}", actual);
        assert!(
            actual.starts_with("nonisolated static let Dog"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Reserved Keyword Tests

    #[test]
    fn test_render_reserved_keyword_has_suffixed_type() {
        for keyword in &["Type", "type"] {
            let obj = make_object(keyword, None, vec![], None, None);
            let template = ObjectTemplate {
                graphql_object: obj,
                config: default_config(),
            };
            let actual = render_body(&template);
            let expected_name = format!("{}_Object", first_uppercased(keyword));
            assert!(
                actual.contains(&format!("static let {} = ApolloAPI.Object(", expected_name)),
                "keyword={}, actual:\n{}",
                keyword,
                actual
            );
            assert!(
                actual.contains(&format!("typename: \"{}\"", keyword)),
                "keyword={}, actual:\n{}",
                keyword,
                actual
            );
        }
    }

    // MARK: - Schema Customization Tests

    #[test]
    fn test_render_with_custom_names() {
        let custom_interface = make_interface("MyInterface", Some("MyCustomInterface"));
        let obj = make_object(
            "MyObject",
            Some("MyCustomObject"),
            vec![custom_interface],
            None,
            None,
        );
        let template = ObjectTemplate {
            graphql_object: obj,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("// Renamed from GraphQL schema value: 'MyObject'"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("static let MyCustomObject = ApolloAPI.Object("),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("typename: \"MyObject\""),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("TestSchema.Interfaces.MyCustomInterface.self"),
            "actual:\n{}",
            actual
        );
        assert_key_fields(&actual, "keyFields: nil");
    }

    #[test]
    fn test_render_no_key_fields_renders_nil() {
        let obj = make_object("Dog", None, vec![], None, None);
        let template = ObjectTemplate {
            graphql_object: obj,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert_key_fields(&actual, "keyFields: nil");
    }
}
