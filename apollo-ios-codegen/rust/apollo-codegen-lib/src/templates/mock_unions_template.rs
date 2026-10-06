//! Mock unions template for Apollo iOS code generation.
//!
//! Renders `extension MockObject` with Union typealiases for each union type.
//!
//! Mirrors Swift's `MockUnionsTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/MockUnionsTemplate.swift`.

use std::sync::Arc;

use indexmap::IndexSet;

use graphql_compiler::schema::{GraphQLNamedType, GraphQLUnionType};

use crate::templates::rendering_helpers::graphql_name_rendering::{
    render_named_type, RenderContext,
};
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, Scope, TemplateRenderer, TemplateTarget,
};

/// Provides the format to convert GraphQL Union types into Swift test mock typealiases.
///
/// Mirrors Swift's `MockUnionsTemplate` struct.
pub struct MockUnionsTemplate {
    pub graphql_unions: IndexSet<Arc<GraphQLUnionType>>,
    pub config: ConfigurationContext,
}

impl TemplateRenderer for MockUnionsTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::TestMockFile
    }

    fn render_body_template(&self, _non_fatal_error_recorder: &NonFatalErrorRecorder) -> String {
        let access = self.access_control_renderer(Scope::Parent).render();

        let lines: Vec<String> = self
            .graphql_unions
            .iter()
            .map(|u| {
                let name = render_named_type(
                    &GraphQLNamedType::Union(Arc::clone(u)),
                    &RenderContext::Typename {
                        is_input_value: false,
                    },
                );
                format!("  typealias {} = Union", name)
            })
            .collect();

        format!(
            "{}extension MockObject {{\n{}\n}}\n",
            access,
            lines.join("\n"),
        )
    }
}

#[cfg(test)]
#[allow(non_snake_case)] // test names mirror the Swift test suite
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;
    use crate::templates::ConfigurationContext;
    use graphql_compiler::graphql_name::GraphQLName;
    use graphql_compiler::schema::GraphQLUnionType;
    use std::sync::Arc;

    fn make_config(json: &str) -> ConfigurationContext {
        let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
        ConfigurationContext::new(config, None)
    }

    fn swift_package_config() -> ConfigurationContext {
        make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"swiftPackage": {"targetName": null}}
            }
        }"#,
        )
    }

    fn absolute_public_config() -> ConfigurationContext {
        make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"absolute": {"path": "", "accessModifier": "public"}}
            }
        }"#,
        )
    }

    fn absolute_internal_config() -> ConfigurationContext {
        make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"absolute": {"path": "", "accessModifier": "internal"}}
            }
        }"#,
        )
    }

    fn mock_union(name: &str) -> Arc<GraphQLUnionType> {
        Arc::new(GraphQLUnionType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            types: vec![],
        })
    }

    fn build_subject(
        unions: IndexSet<Arc<GraphQLUnionType>>,
        config: ConfigurationContext,
    ) -> MockUnionsTemplate {
        MockUnionsTemplate {
            graphql_unions: unions,
            config,
        }
    }

    fn render_body(subject: &MockUnionsTemplate) -> String {
        let recorder = NonFatalErrorRecorder::new();
        subject.render_body_template(&recorder)
    }

    // MARK: - Boilerplate Tests

    #[test]
    fn test__target__is_test_mock_file() {
        let subject = build_subject(IndexSet::new(), swift_package_config());
        assert!(matches!(subject.target(), TemplateTarget::TestMockFile));
    }

    // MARK: - Typealias Tests

    #[test]
    fn test__render__given_single_union_type_generates_extension_with_typealias() {
        let pet = mock_union("Pet");
        let mut unions = IndexSet::new();
        unions.insert(pet);
        let subject = build_subject(unions, swift_package_config());

        let expected = "public extension MockObject {\n  typealias Pet = Union\n}\n";

        let actual = render_body(&subject);
        assert_eq!(actual, expected);
    }

    #[test]
    fn test__render__given_multiple_union_types_generates_extension_with_typealiases_correctly_cased(
    ) {
        let union_a = mock_union("UnionA");
        let union_b = mock_union("unionB");
        let union_c = mock_union("Unionc");
        let mut unions = IndexSet::new();
        unions.insert(union_a);
        unions.insert(union_b);
        unions.insert(union_c);
        let subject = build_subject(unions, swift_package_config());

        let expected =
            "public extension MockObject {\n  typealias UnionA = Union\n  typealias UnionB = Union\n  typealias Unionc = Union\n}\n";

        let actual = render_body(&subject);
        assert_eq!(actual, expected);
    }

    // MARK: - Access Level Tests

    #[test]
    fn test__render__given_union_type_when_test_mocks_is_swift_package_should_render_with_public_access(
    ) {
        let pet = mock_union("Pet");
        let mut unions = IndexSet::new();
        unions.insert(pet);
        let subject = build_subject(unions, swift_package_config());

        let actual = render_body(&subject);
        assert!(actual.starts_with("public extension MockObject {"));
    }

    #[test]
    fn test__render__given_union_type_when_test_mocks_absolute_with_public_access_modifier_should_render_with_public_access(
    ) {
        let pet = mock_union("Pet");
        let mut unions = IndexSet::new();
        unions.insert(pet);
        let subject = build_subject(unions, absolute_public_config());

        let actual = render_body(&subject);
        assert!(actual.starts_with("public extension MockObject {"));
    }

    #[test]
    fn test__render__given_union_type_when_test_mocks_absolute_with_internal_access_modifier_should_render_with_internal_access(
    ) {
        let pet = mock_union("Pet");
        let mut unions = IndexSet::new();
        unions.insert(pet);
        let subject = build_subject(unions, absolute_internal_config());

        let actual = render_body(&subject);
        assert!(actual.starts_with("extension MockObject {"));
        assert!(!actual.starts_with("public extension MockObject {"));
    }

    // MARK: - Reserved Keyword Tests

    #[test]
    fn test__render__using_reserved_keyword_generates_type_with_suffix() {
        for keyword in &["Type", "type"] {
            let union = mock_union(keyword);
            let mut unions = IndexSet::new();
            unions.insert(union);
            let subject = build_subject(unions, swift_package_config());

            let actual = render_body(&subject);

            // "Type" -> first_uppercased -> "Type" -> matches TYPE_NAMES_TO_SUFFIX -> "Type_Union"
            // "type" -> first_uppercased -> "Type" -> matches TYPE_NAMES_TO_SUFFIX -> "Type_Union"
            assert!(
                actual.contains("typealias Type_Union = Union"),
                "Expected 'Type_Union' for keyword '{}', got: {}",
                keyword,
                actual
            );
        }
    }

    // MARK: - Schema Customization Tests

    #[test]
    fn test__render__given_union_with_custom_name_should_render_with_custom_name() {
        let mut union = GraphQLUnionType {
            name: GraphQLName::new("MyUnion".to_string()),
            documentation: None,
            types: vec![],
        };
        union.name.custom_name = Some("MyCustomUnion".to_string());
        let union = Arc::new(union);

        let mut unions = IndexSet::new();
        unions.insert(union);
        let subject = build_subject(unions, swift_package_config());

        let expected = "public extension MockObject {\n  typealias MyCustomUnion = Union\n}\n";

        let actual = render_body(&subject);
        assert_eq!(actual, expected);
    }
}
