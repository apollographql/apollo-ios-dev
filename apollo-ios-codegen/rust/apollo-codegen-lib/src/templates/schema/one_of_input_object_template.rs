//! OneOf input object type template for Apollo iOS code generation.
//!
//! Mirrors Swift's `OneOfInputObjectTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/OneOfInputObjectTemplate.swift`.

use std::sync::Arc;

use graphql_compiler::schema::{GraphQLInputField, GraphQLInputObjectType, GraphQLNamedType};

use crate::templates::SPI;
use crate::templates::rendering_helpers::graphql_name_rendering::{
    render_input_field, render_named_type, RenderContext,
};
use crate::templates::rendering_helpers::graphql_type_rendered::render_as_input_value;
use crate::templates::rendering_helpers::template_string_deprecation::render_deprecation_reason;
use crate::templates::rendering_helpers::template_string_documentation::render_documentation;
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, SchemaFileType, Scope, TemplateRenderer,
    TemplateTarget,
};

/// Provides the format to convert a GraphQL OneOf Input Object into Swift code.
///
/// OneOf input objects are rendered as Swift enums with a case per field.
/// Per D-48 decision.
///
/// Mirrors Swift's `OneOfInputObjectTemplate` struct.
pub struct OneOfInputObjectTemplate {
    pub graphql_input_object: Arc<GraphQLInputObjectType>,
    pub config: ConfigurationContext,
}

impl TemplateRenderer for OneOfInputObjectTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::SchemaFile(SchemaFileType::InputObject)
    }

    fn render_body_template(
        &self,
        _non_fatal_error_recorder: &NonFatalErrorRecorder,
    ) -> String {
        let member_access_control = self.access_control_renderer(Scope::Member);
        let parent_access_control = self.access_control_renderer(Scope::Parent).render();
        let member_str = member_access_control.render();
        let member_unsafe_str = member_access_control.render_with_spis(&[SPI::Unsafe]);

        let typename = render_named_type(
            &GraphQLNamedType::InputObject(Arc::clone(&self.graphql_input_object)),
            &RenderContext::Typename { is_input_value: false },
        );

        let mut parts: Vec<String> = Vec::new();

        // Documentation
        if let Some(doc) = render_documentation(
            self.graphql_input_object.documentation.as_deref(),
            &self.config,
        ) {
            parts.push(doc);
        }

        // Type name documentation (for custom names)
        if let Some(type_doc) = self.graphql_input_object.name.type_name_documentation() {
            parts.push(type_doc);
        }

        // Enum body
        let mut enum_body = Vec::new();

        // Cases
        let cases: Vec<String> = self
            .graphql_input_object
            .fields
            .values()
            .map(|field| self.field_case_template(field))
            .collect();
        enum_body.push(cases.join("\n"));

        // __data computed property
        let case_data_entries: Vec<String> = self
            .graphql_input_object
            .fields
            .values()
            .map(|field| self.field_case_data_template(field))
            .collect();

        enum_body.push(String::new());
        enum_body.push(format!(
            "  {}var __data: InputDict {{\n    switch self {{\n{}\n    }}\n  }}",
            member_unsafe_str,
            case_data_entries.join("\n"),
        ));

        parts.push(format!(
            "{}{}enum {}: OneOfInputObject {{\n{}\n}}",
            self.config.nonisolated_modifier(),
            parent_access_control,
            typename,
            enum_body.join("\n"),
        ));

        parts.join("\n")
    }
}

impl OneOfInputObjectTemplate {
    fn field_case_template(&self, field: &GraphQLInputField) -> String {
        let mut case_parts: Vec<String> = Vec::new();

        // Documentation
        if let Some(doc) =
            render_documentation(field.documentation.as_deref(), &self.config)
        {
            case_parts.push(format!("  {}", doc));
        }

        // Deprecation reason
        if let Some(depr) =
            render_deprecation_reason(field.deprecation_reason.as_deref(), &self.config)
        {
            case_parts.push(format!("  {}", depr));
        }

        // Type name documentation (for custom names)
        if let Some(type_doc) = field.name.type_name_documentation() {
            case_parts.push(format!("  {}", type_doc));
        }

        let field_name = render_input_field(field, &self.config);
        let type_str =
            render_as_input_value(&field.type_, false, &self.config.config);

        case_parts.push(format!("  case {}({})", field_name, type_str));

        case_parts.join("\n")
    }

    fn field_case_data_template(&self, field: &GraphQLInputField) -> String {
        let field_name = render_input_field(field, &self.config);
        let schema_name = &field.name.schema_name;

        format!(
            "    case .{}(let value):\n      return InputDict([\"{}\": value])",
            field_name, schema_name
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;
    use crate::templates::ConfigurationContext;

    /// Swift type GraphQL `Int` maps to in this Apollo iOS version (`Int32` from 2.0.0).
    const INT_SWIFT_TYPE: &str = "Int32";
    use graphql_compiler::graphql_name::GraphQLName;
    use graphql_compiler::graphql_type::GraphQLType;
    use graphql_compiler::schema::{GraphQLEnumType, GraphQLScalarType};
    use indexmap::IndexMap;

    fn make_config(json: &str) -> ConfigurationContext {
        let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
        ConfigurationContext::new(config, None)
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

    fn spm_config_with_options(docs: &str, warnings: &str) -> ConfigurationContext {
        make_config(&format!(
            r#"{{
            "schemaNamespace": "TestSchema",
            "input": {{}},
            "output": {{
                "schemaTypes": {{ "path": "./gen", "moduleType": {{"swiftPackageManager": {{}}}} }},
                "operations": {{"inSchemaModule": {{}}}},
                "testMocks": {{"none": {{}}}}
            }},
            "options": {{
                "schemaDocumentation": "{}",
                "warningsOnDeprecatedUsage": "{}"
            }}
        }}"#,
            docs, warnings
        ))
    }

    fn make_string_type() -> GraphQLType {
        GraphQLType::NonNull(Box::new(GraphQLType::Scalar(Arc::new(
            GraphQLScalarType {
                name: GraphQLName::new("String".to_string()),
                documentation: None,
                specified_by_url: None,
            },
        ))))
    }

    fn make_nullable_string_type() -> GraphQLType {
        GraphQLType::Scalar(Arc::new(GraphQLScalarType {
            name: GraphQLName::new("String".to_string()),
            documentation: None,
            specified_by_url: None,
        }))
    }

    fn make_int_type() -> GraphQLType {
        GraphQLType::NonNull(Box::new(GraphQLType::Scalar(Arc::new(
            GraphQLScalarType {
                name: GraphQLName::new("Int".to_string()),
                documentation: None,
                specified_by_url: None,
            },
        ))))
    }

    fn make_field(name: &str, type_: GraphQLType) -> (String, GraphQLInputField) {
        (
            name.to_string(),
            GraphQLInputField {
                name: GraphQLName::new(name.to_string()),
                type_,
                documentation: None,
                deprecation_reason: None,
                default_value: None,
            },
        )
    }

    fn make_field_with_docs(
        name: &str,
        type_: GraphQLType,
        docs: &str,
    ) -> (String, GraphQLInputField) {
        (
            name.to_string(),
            GraphQLInputField {
                name: GraphQLName::new(name.to_string()),
                type_,
                documentation: Some(docs.to_string()),
                deprecation_reason: None,
                default_value: None,
            },
        )
    }

    fn make_field_deprecated(
        name: &str,
        type_: GraphQLType,
        reason: &str,
    ) -> (String, GraphQLInputField) {
        (
            name.to_string(),
            GraphQLInputField {
                name: GraphQLName::new(name.to_string()),
                type_,
                documentation: None,
                deprecation_reason: Some(reason.to_string()),
                default_value: None,
            },
        )
    }

    fn make_one_of_input(
        name: &str,
        fields: Vec<(String, GraphQLInputField)>,
    ) -> Arc<GraphQLInputObjectType> {
        let field_map: IndexMap<String, GraphQLInputField> = fields.into_iter().collect();
        Arc::new(GraphQLInputObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            is_one_of: true,
            fields: field_map,
        })
    }

    fn make_one_of_input_with_docs(
        name: &str,
        fields: Vec<(String, GraphQLInputField)>,
        docs: &str,
    ) -> Arc<GraphQLInputObjectType> {
        let field_map: IndexMap<String, GraphQLInputField> = fields.into_iter().collect();
        Arc::new(GraphQLInputObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: Some(docs.to_string()),
            is_one_of: true,
            fields: field_map,
        })
    }

    fn render_body(template: &OneOfInputObjectTemplate) -> String {
        let recorder = NonFatalErrorRecorder::new();
        template.render_body_template(&recorder)
    }

    // MARK: - Basic Tests

    #[test]
    fn test_render_single_field_one_of() {
        let input = make_one_of_input(
            "MockOneOf",
            vec![make_field("fieldOne", make_string_type())],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("public enum MockOneOf: OneOfInputObject {"), "actual:\n{}", actual);
        assert!(actual.contains("case fieldOne(String)"), "actual:\n{}", actual);
        assert!(actual.contains("case .fieldOne(let value):"), "actual:\n{}", actual);
        assert!(actual.contains("return InputDict([\"fieldOne\": value])"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_multiple_fields_one_of() {
        let input = make_one_of_input(
            "MockOneOf",
            vec![
                make_field("fieldOne", make_string_type()),
                make_field("fieldTwo", make_int_type()),
            ],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("case fieldOne(String)"), "actual:\n{}", actual);
        assert!(actual.contains(&format!("case fieldTwo({})", INT_SWIFT_TYPE)), "actual:\n{}", actual);
        assert!(actual.contains("case .fieldOne(let value):"), "actual:\n{}", actual);
        assert!(actual.contains("case .fieldTwo(let value):"), "actual:\n{}", actual);
    }

    // MARK: - Access Level Tests

    #[test]
    fn test_render_spm_public_access() {
        let input = make_one_of_input(
            "MockOneOf",
            vec![make_field("fieldOne", make_string_type())],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("public enum MockOneOf: OneOfInputObject {"), "actual:\n{}", actual);
        assert!(actual.contains("public var __data: InputDict {"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_embedded_public_access() {
        let input = make_one_of_input(
            "MockOneOf",
            vec![make_field("fieldOne", make_string_type())],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: embedded_public_config(),
        };
        let actual = render_body(&template);
        // Parent scope = no access modifier for embedded
        assert!(actual.contains("enum MockOneOf: OneOfInputObject {"), "actual:\n{}", actual);
        assert!(!actual.starts_with("public enum"), "actual:\n{}", actual);
        // Member scope = public
        assert!(actual.contains("public var __data: InputDict {"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_embedded_internal_access() {
        let input = make_one_of_input(
            "MockOneOf",
            vec![make_field("fieldOne", make_string_type())],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: embedded_internal_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("enum MockOneOf: OneOfInputObject {"), "actual:\n{}", actual);
        assert!(!actual.contains("public"), "actual:\n{}", actual);
        assert!(actual.contains("var __data: InputDict {"), "actual:\n{}", actual);
    }

    // MARK: - Documentation Tests

    #[test]
    fn test_render_with_documentation() {
        let input = make_one_of_input_with_docs(
            "MockOneOf",
            vec![make_field_with_docs("fieldOne", make_string_type(), "Field docs")],
            "Input docs",
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("include", "include"),
        };
        let actual = render_body(&template);
        assert!(actual.contains("/// Input docs"), "actual:\n{}", actual);
        assert!(actual.contains("/// Field docs"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_without_documentation() {
        let input = make_one_of_input_with_docs(
            "MockOneOf",
            vec![make_field_with_docs("fieldOne", make_string_type(), "Field docs")],
            "Input docs",
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("exclude", "include"),
        };
        let actual = render_body(&template);
        assert!(!actual.contains("/// Input docs"), "actual:\n{}", actual);
        assert!(!actual.contains("/// Field docs"), "actual:\n{}", actual);
    }

    // MARK: - Deprecation Tests

    #[test]
    fn test_render_with_deprecated_field() {
        let input = make_one_of_input(
            "MockOneOf",
            vec![make_field_deprecated("fieldOne", make_string_type(), "No longer used")],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("include", "include"),
        };
        let actual = render_body(&template);
        assert!(actual.contains("@available(*, deprecated, message: \"No longer used\")"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_deprecated_field_excluded() {
        let input = make_one_of_input(
            "MockOneOf",
            vec![make_field_deprecated("fieldOne", make_string_type(), "No longer used")],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("include", "exclude"),
        };
        let actual = render_body(&template);
        assert!(!actual.contains("@available"), "actual:\n{}", actual);
    }

    // MARK: - Enum type field test

    #[test]
    fn test_render_with_enum_field() {
        let enum_type = GraphQLType::NonNull(Box::new(GraphQLType::Enum(Arc::new(
            GraphQLEnumType {
                name: GraphQLName::new("Status".to_string()),
                documentation: None,
                values: vec![],
            },
        ))));
        let input = make_one_of_input(
            "MockOneOf",
            vec![make_field("status", enum_type)],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("case status(GraphQLEnum<Status>)"), "actual:\n{}", actual);
    }

    // MARK: - Nullable field type test

    #[test]
    fn test_render_with_nullable_field() {
        let input = make_one_of_input(
            "MockOneOf",
            vec![make_field("fieldOne", make_nullable_string_type())],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        // render_as_input_value with in_nullable=false for oneOf case types
        assert!(actual.contains("case fieldOne(String)"), "actual:\n{}", actual);
    }

    // MARK: - Custom name test

    #[test]
    fn test_render_with_custom_names() {
        let mut custom_field_name = GraphQLName::new("myField".to_string());
        custom_field_name.custom_name = Some("myCustomField".to_string());
        let custom_field = GraphQLInputField {
            name: custom_field_name,
            type_: make_string_type(),
            documentation: None,
            deprecation_reason: None,
            default_value: None,
        };

        let mut fields: IndexMap<String, GraphQLInputField> = IndexMap::new();
        fields.insert("myField".to_string(), custom_field);

        let mut gql_name = GraphQLName::new("MyOneOf".to_string());
        gql_name.custom_name = Some("MyCustomOneOf".to_string());
        let input = Arc::new(GraphQLInputObjectType {
            name: gql_name,
            documentation: None,
            is_one_of: true,
            fields,
        });

        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("// Renamed from GraphQL schema value: 'MyOneOf'"), "actual:\n{}", actual);
        assert!(actual.contains("enum MyCustomOneOf: OneOfInputObject {"), "actual:\n{}", actual);
        assert!(actual.contains("case myCustomField(String)"), "actual:\n{}", actual);
        assert!(actual.contains("case .myCustomField(let value):"), "actual:\n{}", actual);
        assert!(actual.contains("\"myField\": value"), "actual:\n{}", actual);
    }

    // MARK: - Reserved keyword test

    #[test]
    fn test_render_reserved_keyword_field() {
        let input = make_one_of_input(
            "MockOneOf",
            vec![make_field("class", make_string_type())],
        );
        let config = make_config(
            r#"{
            "schemaNamespace": "TestSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            },
            "options": {
                "conversionStrategies": { "inputObjects": "none" }
            }
        }"#,
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config,
        };
        let actual = render_body(&template);
        assert!(actual.contains("case `class`(String)"), "actual:\n{}", actual);
        assert!(actual.contains("case .`class`(let value):"), "actual:\n{}", actual);
    }

    // MARK: - Type name suffix test

    #[test]
    fn test_render_reserved_keyword_type_name() {
        let input = make_one_of_input(
            "Type",
            vec![make_field("fieldOne", make_string_type())],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("enum Type_InputObject: OneOfInputObject {"), "actual:\n{}", actual);
    }

    // MARK: - Casing test

    #[test]
    fn test_render_lowercased_name() {
        let input = make_one_of_input(
            "mockOneOf",
            vec![make_field("fieldOne", make_string_type())],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("enum MockOneOf: OneOfInputObject {"), "actual:\n{}", actual);
    }

    // MARK: - __data structure test

    #[test]
    fn test_render_data_switch_structure() {
        let input = make_one_of_input(
            "MockOneOf",
            vec![
                make_field("fieldOne", make_string_type()),
                make_field("fieldTwo", make_int_type()),
            ],
        );
        let template = OneOfInputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("switch self {"), "actual:\n{}", actual);
        assert!(
            actual.contains("case .fieldOne(let value):\n      return InputDict([\"fieldOne\": value])"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("case .fieldTwo(let value):\n      return InputDict([\"fieldTwo\": value])"),
            "actual:\n{}",
            actual
        );
    }
}
