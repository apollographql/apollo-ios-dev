//! Mock interfaces template for Apollo iOS code generation.
//!
//! Renders `extension MockObject` with Interface typealiases for each interface type.
//!
//! Mirrors Swift's `MockInterfacesTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/MockInterfacesTemplate.swift`.

use std::sync::Arc;

use indexmap::IndexSet;

use graphql_compiler::schema::{GraphQLInterfaceType, GraphQLNamedType};

use crate::templates::rendering_helpers::graphql_name_rendering::{render_named_type, RenderContext};
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, Scope, TemplateRenderer, TemplateTarget,
};

/// Provides the format to convert GraphQL Interface types into Swift test mock typealiases.
///
/// Mirrors Swift's `MockInterfacesTemplate` struct.
pub struct MockInterfacesTemplate {
    pub graphql_interfaces: IndexSet<Arc<GraphQLInterfaceType>>,
    pub config: ConfigurationContext,
}

impl TemplateRenderer for MockInterfacesTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::TestMockFile
    }

    fn render_body_template(
        &self,
        _non_fatal_error_recorder: &NonFatalErrorRecorder,
    ) -> String {
        let access = self.access_control_renderer(Scope::Parent).render();

        let lines: Vec<String> = self
            .graphql_interfaces
            .iter()
            .map(|i| {
                let name = render_named_type(
                    &GraphQLNamedType::Interface(Arc::clone(i)),
                    &RenderContext::Typename { is_input_value: false },
                );
                format!("  typealias {} = Interface", name)
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
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;
    use crate::templates::ConfigurationContext;
    use graphql_compiler::graphql_name::GraphQLName;
    use graphql_compiler::schema::GraphQLInterfaceType;
    use indexmap::IndexMap;
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

    fn mock_interface(name: &str) -> Arc<GraphQLInterfaceType> {
        Arc::new(GraphQLInterfaceType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
            implementing_objects: vec![],
        })
    }

    fn build_subject(
        interfaces: IndexSet<Arc<GraphQLInterfaceType>>,
        config: ConfigurationContext,
    ) -> MockInterfacesTemplate {
        MockInterfacesTemplate {
            graphql_interfaces: interfaces,
            config,
        }
    }

    fn render_body(subject: &MockInterfacesTemplate) -> String {
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
    fn test__render__given_single_interface_type_generates_extension_with_typealias() {
        let pet = mock_interface("Pet");
        let mut interfaces = IndexSet::new();
        interfaces.insert(pet);
        let subject = build_subject(interfaces, swift_package_config());

        let expected = "public extension MockObject {\n  typealias Pet = Interface\n}\n";

        let actual = render_body(&subject);
        assert_eq!(actual, expected);
    }

    #[test]
    fn test__render__given_multiple_interface_types_generates_extension_with_typealiases_correctly_cased()
    {
        let iface_a = mock_interface("InterfaceA");
        let iface_b = mock_interface("interfaceB");
        let iface_c = mock_interface("Interfacec");
        let mut interfaces = IndexSet::new();
        interfaces.insert(iface_a);
        interfaces.insert(iface_b);
        interfaces.insert(iface_c);
        let subject = build_subject(interfaces, swift_package_config());

        let expected =
            "public extension MockObject {\n  typealias InterfaceA = Interface\n  typealias InterfaceB = Interface\n  typealias Interfacec = Interface\n}\n";

        let actual = render_body(&subject);
        assert_eq!(actual, expected);
    }

    // MARK: - Access Level Tests

    #[test]
    fn test__render__given_interface_type_when_test_mocks_is_swift_package_should_render_with_public_access()
    {
        let pet = mock_interface("Pet");
        let mut interfaces = IndexSet::new();
        interfaces.insert(pet);
        let subject = build_subject(interfaces, swift_package_config());

        let actual = render_body(&subject);
        assert!(actual.starts_with("public extension MockObject {"));
    }

    #[test]
    fn test__render__given_interface_type_when_test_mocks_absolute_with_public_access_modifier_should_render_with_public_access()
    {
        let pet = mock_interface("Pet");
        let mut interfaces = IndexSet::new();
        interfaces.insert(pet);
        let subject = build_subject(interfaces, absolute_public_config());

        let actual = render_body(&subject);
        assert!(actual.starts_with("public extension MockObject {"));
    }

    #[test]
    fn test__render__given_interface_type_when_test_mocks_absolute_with_internal_access_modifier_should_render_with_internal_access()
    {
        let pet = mock_interface("Pet");
        let mut interfaces = IndexSet::new();
        interfaces.insert(pet);
        let subject = build_subject(interfaces, absolute_internal_config());

        let actual = render_body(&subject);
        assert!(actual.starts_with("extension MockObject {"));
        assert!(!actual.starts_with("public extension MockObject {"));
    }

    // MARK: - Reserved Keyword Tests

    #[test]
    fn test__render__using_reserved_keyword_generates_type_with_suffix() {
        for keyword in &["Type", "type"] {
            let iface = mock_interface(keyword);
            let mut interfaces = IndexSet::new();
            interfaces.insert(iface);
            let subject = build_subject(interfaces, swift_package_config());

            let actual = render_body(&subject);

            assert!(
                actual.contains("typealias Type_Interface = Interface"),
                "Expected 'Type_Interface' for keyword '{}', got: {}",
                keyword,
                actual
            );
        }
    }

    // MARK: - Schema Customization Tests

    #[test]
    fn test__render__given_interface_with_custom_name_should_render_with_custom_name() {
        let mut iface = GraphQLInterfaceType {
            name: GraphQLName::new("MyInterface".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
            implementing_objects: vec![],
        };
        iface.name.custom_name = Some("MyCustomInterface".to_string());
        let iface = Arc::new(iface);

        let mut interfaces = IndexSet::new();
        interfaces.insert(iface);
        let subject = build_subject(interfaces, swift_package_config());

        let expected =
            "public extension MockObject {\n  typealias MyCustomInterface = Interface\n}\n";

        let actual = render_body(&subject);
        assert_eq!(actual, expected);
    }
}
