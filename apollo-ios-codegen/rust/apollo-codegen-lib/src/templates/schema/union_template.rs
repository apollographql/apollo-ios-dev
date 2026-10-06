//! Union type template for Apollo iOS code generation.
//!
//! Mirrors Swift's `UnionTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/UnionTemplate.swift`.

use std::sync::Arc;

use graphql_compiler::schema::{GraphQLNamedType, GraphQLUnionType};

use crate::templates::rendering_helpers::graphql_name_rendering::{render_named_type, RenderContext};
use crate::templates::rendering_helpers::string_casing::first_uppercased;
use crate::templates::rendering_helpers::template_string_documentation::render_documentation;
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, SchemaFileType, TemplateRenderer,
    TemplateTarget,
};

/// Provides the format to convert a GraphQL Union into Swift code.
///
/// Mirrors Swift's `UnionTemplate` struct.
pub struct UnionTemplate {
    pub graphql_union: Arc<GraphQLUnionType>,
    pub config: ConfigurationContext,
}

impl TemplateRenderer for UnionTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::SchemaFile(SchemaFileType::Union)
    }

    fn render_body_template(
        &self,
        _non_fatal_error_recorder: &NonFatalErrorRecorder,
    ) -> String {
        let mut parts: Vec<String> = Vec::new();

        // Documentation
        if let Some(doc) = render_documentation(
            self.graphql_union.documentation.as_deref(),
            &self.config,
        ) {
            parts.push(doc);
        }

        // Type name documentation (for custom names)
        if let Some(type_doc) = self.graphql_union.name.type_name_documentation() {
            parts.push(type_doc);
        }

        let typename = render_named_type(
            &GraphQLNamedType::Union(Arc::clone(&self.graphql_union)),
            &RenderContext::Typename { is_input_value: false },
        );

        let possible_types = self.render_possible_types();

        parts.push(format!(
            "{}static let {} = Union(\n  name: \"{}\",\n  possibleTypes: {}\n)",
            self.config.nonisolated_modifier(),
            typename,
            self.graphql_union.name.schema_name,
            possible_types,
        ));

        parts.join("\n")
    }
}

impl UnionTemplate {
    fn render_possible_types(&self) -> String {
        if self.graphql_union.types.is_empty() {
            return "[]".to_string();
        }

        let is_in_module = self.config.output().schema_types.is_in_module();
        let namespace_prefix = if !is_in_module {
            format!("{}.", first_uppercased(self.config.schema_namespace()))
        } else {
            String::new()
        };

        let items: Vec<String> = self
            .graphql_union
            .types
            .iter()
            .map(|obj_type| {
                let type_name = render_named_type(
                    &GraphQLNamedType::Object(Arc::clone(obj_type)),
                    &RenderContext::Typename { is_input_value: false },
                );
                format!("{}Objects.{}.self", namespace_prefix, type_name)
            })
            .collect();

        render_bracketed_list(&items)
    }
}

/// Renders a bracketed list of items with proper Swift formatting.
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

    fn config_with_namespace(ns: &str) -> ConfigurationContext {
        make_config(&format!(
            r#"{{
            "schemaNamespace": "{}",
            "input": {{}},
            "output": {{
                "schemaTypes": {{ "path": "./gen", "moduleType": {{"embeddedInTarget": {{"name": "TestTarget"}}}} }},
                "operations": {{"inSchemaModule": {{}}}},
                "testMocks": {{"none": {{}}}}
            }}
        }}"#,
            ns
        ))
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

    fn make_object(name: &str) -> Arc<GraphQLObjectType> {
        Arc::new(GraphQLObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        })
    }

    fn make_object_with_custom_name(name: &str, custom_name: &str) -> Arc<GraphQLObjectType> {
        let mut gql_name = GraphQLName::new(name.to_string());
        gql_name.custom_name = Some(custom_name.to_string());
        Arc::new(GraphQLObjectType {
            name: gql_name,
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        })
    }

    fn default_types() -> Vec<Arc<GraphQLObjectType>> {
        vec![
            make_object("cat"),
            make_object("bird"),
            make_object("rat"),
            make_object("petRock"),
        ]
    }

    fn make_union(
        name: &str,
        custom_name: Option<&str>,
        types: Vec<Arc<GraphQLObjectType>>,
        documentation: Option<String>,
    ) -> Arc<GraphQLUnionType> {
        let mut gql_name = GraphQLName::new(name.to_string());
        if let Some(cn) = custom_name {
            gql_name.custom_name = Some(cn.to_string());
        }
        Arc::new(GraphQLUnionType {
            name: gql_name,
            documentation,
            types,
        })
    }

    fn render_body(template: &UnionTemplate) -> String {
        let recorder = NonFatalErrorRecorder::new();
        template.render_body_template(&recorder)
    }

    // MARK: - Boilerplate tests

    #[test]
    fn test_render_generates_closing_paren() {
        let union = make_union("ClassroomPet", None, default_types(), None);
        let template = UnionTemplate {
            graphql_union: union,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(actual.ends_with("\n)"), "actual:\n{}", actual);
    }

    // MARK: - Casing Tests

    #[test]
    fn test_render_lowercase_schema_name_capitalized() {
        let union = make_union("ClassroomPet", None, default_types(), None);
        let template = UnionTemplate {
            graphql_union: union,
            config: config_with_namespace("lowercased"),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("Lowercased.Objects.Cat.self"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("Lowercased.Objects.PetRock.self"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_uppercase_schema_name() {
        let union = make_union("ClassroomPet", None, default_types(), None);
        let template = UnionTemplate {
            graphql_union: union,
            config: config_with_namespace("UPPER"),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("UPPER.Objects.Cat.self"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_capitalized_schema_name() {
        let union = make_union("ClassroomPet", None, default_types(), None);
        let template = UnionTemplate {
            graphql_union: union,
            config: config_with_namespace("MySchema"),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("MySchema.Objects.Cat.self"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Class Generation Tests

    #[test]
    fn test_render_generates_swift_definition() {
        let union = make_union("ClassroomPet", None, default_types(), None);
        let template = UnionTemplate {
            graphql_union: union,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("static let ClassroomPet = Union("),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_lowercase_name_generates_uppercased() {
        let union = make_union("classroomPet", None, default_types(), None);
        let template = UnionTemplate {
            graphql_union: union,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("static let ClassroomPet = Union("),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_generates_name_property() {
        let union = make_union("ClassroomPet", None, default_types(), None);
        let template = UnionTemplate {
            graphql_union: union,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("name: \"ClassroomPet\""),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_lowercase_name_property_preserves_case() {
        let union = make_union("classroomPet", None, default_types(), None);
        let template = UnionTemplate {
            graphql_union: union,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("name: \"classroomPet\""),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_embedded_in_target_has_schema_namespace() {
        let union = make_union("ClassroomPet", None, default_types(), None);
        let template = UnionTemplate {
            graphql_union: union,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("TestSchema.Objects.Cat.self"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("TestSchema.Objects.PetRock.self"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_not_embedded_no_schema_namespace() {
        let union = make_union("ClassroomPet", None, default_types(), None);
        let template = UnionTemplate {
            graphql_union: union,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("Objects.Cat.self"),
            "actual:\n{}",
            actual
        );
        assert!(
            !actual.contains("TestSchema.Objects"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Documentation Tests

    #[test]
    fn test_render_documentation_include() {
        let union = make_union(
            "ClassroomPet",
            None,
            default_types(),
            Some("This is some great documentation!".to_string()),
        );
        let template = UnionTemplate {
            graphql_union: union,
            config: config_with_docs(true),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("/// This is some great documentation!"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_documentation_exclude() {
        let union = make_union(
            "ClassroomPet",
            None,
            default_types(),
            Some("This is some great documentation!".to_string()),
        );
        let template = UnionTemplate {
            graphql_union: union,
            config: config_with_docs(false),
        };
        let actual = render_body(&template);
        assert!(
            !actual.contains("///"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Reserved Keyword Tests

    #[test]
    fn test_render_reserved_keyword_has_suffixed_type() {
        for keyword in &["Type", "type"] {
            let union = make_union(keyword, None, default_types(), None);
            let template = UnionTemplate {
                graphql_union: union,
                config: default_config(),
            };
            let actual = render_body(&template);
            let expected_name = format!("{}_Union", first_uppercased(keyword));
            assert!(
                actual.contains(&format!("static let {} = Union(", expected_name)),
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
    fn test_render_with_custom_names() {
        let custom_obj = make_object_with_custom_name("MyObject", "MyCustomObject");
        let cat = make_object("cat");
        let union = make_union(
            "MyUnion",
            Some("MyCustomUnion"),
            vec![cat, custom_obj],
            None,
        );
        let template = UnionTemplate {
            graphql_union: union,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("// Renamed from GraphQL schema value: 'MyUnion'"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("static let MyCustomUnion = Union("),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("name: \"MyUnion\""),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("TestSchema.Objects.Cat.self"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("TestSchema.Objects.MyCustomObject.self"),
            "actual:\n{}",
            actual
        );
    }
}
