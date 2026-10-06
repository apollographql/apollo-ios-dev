//! Input object type template for Apollo iOS code generation.
//!
//! Mirrors Swift's `InputObjectTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/InputObjectTemplate.swift`.

use std::sync::Arc;

use graphql_compiler::graphql_type::GraphQLType;
use graphql_compiler::schema::{GraphQLInputField, GraphQLInputObjectType, GraphQLNamedType};
use indexmap::IndexMap;

use crate::templates::SPI;
use crate::config::composition::Composition;
use crate::templates::rendering_helpers::graphql_input_field_rendered::{
    has_default_value, is_nullable, render_input_value_type,
};
use crate::templates::rendering_helpers::graphql_name_rendering::{
    render_input_field, render_named_type, RenderContext,
};
use crate::templates::rendering_helpers::template_string_deprecation::render_deprecation_reason;
use crate::templates::rendering_helpers::template_string_documentation::render_documentation;
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, SchemaFileType, Scope, TemplateRenderer,
    TemplateTarget,
};

/// Provides the format to convert a GraphQL Input Object into Swift code.
///
/// Mirrors Swift's `InputObjectTemplate` struct.
pub struct InputObjectTemplate {
    pub graphql_input_object: Arc<GraphQLInputObjectType>,
    pub config: ConfigurationContext,
}

impl TemplateRenderer for InputObjectTemplate {
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
        let (valid_fields, deprecated_fields) =
            filter_fields(&self.graphql_input_object.fields);
        let member_access_control = self.access_control_renderer(Scope::Member);
        let parent_access_control = self.access_control_renderer(Scope::Parent).render();
        let member_str = member_access_control.render();
        // SPI annotations only apply to public declarations (Swift 2.1.0 AccessControlRenderer).
        let member_unsafe_str = member_access_control.render_with_spis(&[SPI::Unsafe]);

        let typename = render_named_type(
            &GraphQLNamedType::InputObject(Arc::clone(&self.graphql_input_object)),
            &RenderContext::Typename { is_input_value: false },
        );

        let should_include_deprecated_warnings = self.should_include_deprecated_warnings();

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

        // Struct definition opening
        let mut struct_body = Vec::new();

        // __data property and raw init
        struct_body.push(format!(
            "  {}private(set) var __data: InputDict",
            member_unsafe_str
        ));
        struct_body.push(String::new());
        struct_body.push(format!(
            "  {}init(_ data: InputDict) {{\n    __data = data\n  }}",
            member_unsafe_str
        ));
        struct_body.push(String::new());

        // Conditional: Non-deprecated initializer
        if !deprecated_fields.is_empty()
            && !valid_fields.is_empty()
            && should_include_deprecated_warnings
        {
            struct_body.push(format!(
                "  {}init(\n{}\n  ) {{\n    __data = InputDict([\n{}\n    ])\n  }}",
                member_str,
                self.initializer_parameters_template(&valid_fields),
                self.input_dict_initializer_template(&valid_fields),
            ));
        }

        // Conditional: Deprecation annotation on the all-fields initializer
        if !deprecated_fields.is_empty() && should_include_deprecated_warnings {
            struct_body.push(String::new());
            struct_body.push(format!(
                "  @available(*, deprecated, message: \"{}\")",
                self.deprecated_message(&deprecated_fields)
            ));
        }

        // All-fields initializer
        struct_body.push(format!(
            "  {}init(\n{}\n  ) {{\n    __data = InputDict([\n{}\n    ])\n  }}",
            member_str,
            self.initializer_parameters_template(&self.graphql_input_object.fields),
            self.input_dict_initializer_template(&self.graphql_input_object.fields),
        ));

        // Field properties
        for (_key, field) in &self.graphql_input_object.fields {
            struct_body.push(String::new());
            struct_body.push(self.field_property_template(field));
        }

        parts.push(format!(
            "{}{}struct {}: InputObject {{\n{}\n}}\n",
            self.config.nonisolated_modifier(),
            parent_access_control,
            typename,
            struct_body.join("\n"),
        ));

        parts.join("\n")
    }
}

impl InputObjectTemplate {
    fn should_include_deprecated_warnings(&self) -> bool {
        self.config.options().warnings_on_deprecated_usage == Composition::Include
    }

    fn deprecated_message(&self, fields: &IndexMap<String, GraphQLInputField>) -> String {
        if fields.is_empty() {
            return String::new();
        }

        let names: Vec<String> = fields
            .values()
            .map(|f| render_input_field(f, &self.config))
            .collect();
        let names_str = names.join(", ");

        if fields.len() > 1 {
            format!("Arguments '{}' are deprecated.", names_str)
        } else {
            format!("Argument '{}' is deprecated.", names_str)
        }
    }

    fn initializer_parameters_template(
        &self,
        fields: &IndexMap<String, GraphQLInputField>,
    ) -> String {
        let params: Vec<String> = fields
            .values()
            .map(|field| {
                let field_name = render_input_field(field, &self.config);
                let type_str =
                    render_input_value_type(field, true, &self.config.config);
                format!("    {}: {}", field_name, type_str)
            })
            .collect();
        params.join(",\n")
    }

    fn input_dict_initializer_template(
        &self,
        fields: &IndexMap<String, GraphQLInputField>,
    ) -> String {
        let entries: Vec<String> = fields
            .values()
            .map(|field| {
                let field_name = render_input_field(field, &self.config);
                let schema_name = &field.name.schema_name;
                let null_coalescing =
                    if !is_nullable(field) && has_default_value(field) {
                        " ?? GraphQLNullable.none"
                    } else {
                        ""
                    };
                format!(
                    "      \"{}\": {}{}",
                    schema_name, field_name, null_coalescing
                )
            })
            .collect();
        entries.join(",\n")
    }

    fn field_property_template(&self, field: &GraphQLInputField) -> String {
        let member_str = self.access_control_renderer(Scope::Member).render();
        let field_name = render_input_field(field, &self.config);
        let type_str = render_input_value_type(field, false, &self.config.config);
        let schema_name = &field.name.schema_name;

        let mut property_parts: Vec<String> = Vec::new();

        // Documentation
        if let Some(doc) =
            render_documentation(field.documentation.as_deref(), &self.config)
        {
            // Indent every line of multiline doc comments
            let indented = doc.lines().map(|line| format!("  {}", line)).collect::<Vec<_>>().join("\n");
            property_parts.push(indented);
        }

        // Deprecation reason
        if let Some(depr) =
            render_deprecation_reason(field.deprecation_reason.as_deref(), &self.config)
        {
            let indented = depr.lines().map(|line| format!("  {}", line)).collect::<Vec<_>>().join("\n");
            property_parts.push(indented);
        }

        // Type name documentation (for custom names)
        if let Some(type_doc) = field.name.type_name_documentation() {
            property_parts.push(format!("  {}", type_doc));
        }

        property_parts.push(format!(
            "  {}var {}: {} {{\n    get {{ __data[\"{}\"] }}\n    set {{ __data[\"{}\"] = newValue }}\n  }}",
            member_str, field_name, type_str, schema_name, schema_name
        ));

        property_parts.join("\n")
    }
}

/// Splits input fields into (valid, deprecated) tuples.
///
/// Mirrors Swift's `GraphQLInputFieldDictionary.filterFields()` extension.
fn filter_fields(
    fields: &IndexMap<String, GraphQLInputField>,
) -> (
    IndexMap<String, GraphQLInputField>,
    IndexMap<String, GraphQLInputField>,
) {
    let mut valid = IndexMap::new();
    let mut deprecated = IndexMap::new();
    for (key, value) in fields {
        if value.deprecation_reason.is_some() {
            deprecated.insert(key.clone(), value.clone());
        } else {
            valid.insert(key.clone(), value.clone());
        }
    }
    (valid, deprecated)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;
    use crate::templates::ConfigurationContext;

    /// Swift type GraphQL `Int` maps to in this Apollo iOS version (`Int32` from 2.0.0).
    const INT_SWIFT_TYPE: &str = "Int32";
    use graphql_compiler::graphql_name::GraphQLName;
    use graphql_compiler::graphql_value::GraphQLValue;
    use graphql_compiler::schema::{
        GraphQLEnumType, GraphQLScalarType,
    };

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

    fn spm_config_with_namespace(ns: &str) -> ConfigurationContext {
        make_config(&format!(
            r#"{{
            "schemaNamespace": "{}",
            "input": {{}},
            "output": {{
                "schemaTypes": {{ "path": "./gen", "moduleType": {{"swiftPackageManager": {{}}}} }},
                "operations": {{"inSchemaModule": {{}}}},
                "testMocks": {{"none": {{}}}}
            }}
        }}"#,
            ns
        ))
    }

    fn spm_relative_config_with_namespace(ns: &str) -> ConfigurationContext {
        make_config(&format!(
            r#"{{
            "schemaNamespace": "{}",
            "input": {{}},
            "output": {{
                "schemaTypes": {{ "path": "./gen", "moduleType": {{"swiftPackageManager": {{}}}} }},
                "operations": {{"relative": {{}}}},
                "testMocks": {{"none": {{}}}}
            }}
        }}"#,
            ns
        ))
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

    fn spm_no_conversion_config() -> ConfigurationContext {
        make_config(
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
        )
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
        GraphQLType::Scalar(Arc::new(GraphQLScalarType {
            name: GraphQLName::new("Int".to_string()),
            documentation: None,
            specified_by_url: None,
        }))
    }

    fn make_non_null_int_type() -> GraphQLType {
        GraphQLType::NonNull(Box::new(make_int_type()))
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

    fn make_field_with_default(
        name: &str,
        type_: GraphQLType,
        default: GraphQLValue,
    ) -> (String, GraphQLInputField) {
        (
            name.to_string(),
            GraphQLInputField {
                name: GraphQLName::new(name.to_string()),
                type_,
                documentation: None,
                deprecation_reason: None,
                default_value: Some(default),
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

    fn make_field_with_docs_and_deprecation(
        name: &str,
        type_: GraphQLType,
        docs: &str,
        reason: &str,
    ) -> (String, GraphQLInputField) {
        (
            name.to_string(),
            GraphQLInputField {
                name: GraphQLName::new(name.to_string()),
                type_,
                documentation: Some(docs.to_string()),
                deprecation_reason: Some(reason.to_string()),
                default_value: None,
            },
        )
    }

    fn make_input_object(
        name: &str,
        fields: Vec<(String, GraphQLInputField)>,
    ) -> Arc<GraphQLInputObjectType> {
        let field_map: IndexMap<String, GraphQLInputField> = fields.into_iter().collect();
        Arc::new(GraphQLInputObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            is_one_of: false,
            fields: field_map,
        })
    }

    fn make_input_object_with_docs(
        name: &str,
        fields: Vec<(String, GraphQLInputField)>,
        docs: &str,
    ) -> Arc<GraphQLInputObjectType> {
        let field_map: IndexMap<String, GraphQLInputField> = fields.into_iter().collect();
        Arc::new(GraphQLInputObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: Some(docs.to_string()),
            is_one_of: false,
            fields: field_map,
        })
    }

    fn make_input_object_custom_name(
        name: &str,
        custom_name: &str,
        fields: Vec<(String, GraphQLInputField)>,
    ) -> Arc<GraphQLInputObjectType> {
        let field_map: IndexMap<String, GraphQLInputField> = fields.into_iter().collect();
        let mut gql_name = GraphQLName::new(name.to_string());
        gql_name.custom_name = Some(custom_name.to_string());
        Arc::new(GraphQLInputObjectType {
            name: gql_name,
            documentation: None,
            is_one_of: false,
            fields: field_map,
        })
    }

    fn render_body(template: &InputObjectTemplate) -> String {
        let recorder = NonFatalErrorRecorder::new();
        template.render_body_template(&recorder)
    }

    // MARK: - Definition Tests

    #[test]
    fn test_render_generates_input_object_with_input_dict_variable_and_initializer() {
        let input = make_input_object("mockInput", vec![make_field("field", make_non_null_int_type())]);
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("public struct MockInput: InputObject {"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("public private(set) var __data: InputDict"),
            "actual:\n{}",
            actual
        );
        assert!(
            actual.contains("public init(_ data: InputDict) {"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Access Level Tests

    #[test]
    fn test_render_spm_with_deprecated_and_valid_fields_generates_public_access() {
        let input = make_input_object(
            "MockInput",
            vec![
                make_field_deprecated("fieldOne", make_string_type(), "Not used anymore!"),
                make_field("fieldTwo", make_string_type()),
            ],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("public struct MockInput: InputObject {"), "actual:\n{}", actual);
        assert!(actual.contains("public private(set) var __data: InputDict"), "actual:\n{}", actual);
        assert!(actual.contains("public init(\n    fieldTwo: String\n  )"), "actual:\n{}", actual);
        assert!(actual.contains("@available(*, deprecated, message: \"Argument 'fieldOne' is deprecated.\")"), "actual:\n{}", actual);
        assert!(actual.contains("@available(*, deprecated, message: \"Not used anymore!\")"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_embedded_public_with_deprecated_fields() {
        let input = make_input_object(
            "MockInput",
            vec![
                make_field_deprecated("fieldOne", make_string_type(), "Not used anymore!"),
                make_field("fieldTwo", make_string_type()),
            ],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: embedded_public_config(),
        };
        let actual = render_body(&template);
        // Parent scope in embedded = no access modifier
        assert!(actual.contains("struct MockInput: InputObject {"), "actual:\n{}", actual);
        assert!(!actual.starts_with("public struct"), "actual:\n{}", actual);
        // Member scope in embedded public = public
        assert!(actual.contains("public private(set) var __data: InputDict"), "actual:\n{}", actual);
        assert!(actual.contains("public init(\n    fieldTwo: String\n  )"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_embedded_internal_with_deprecated_fields() {
        let input = make_input_object(
            "MockInput",
            vec![
                make_field_deprecated("fieldOne", make_string_type(), "Not used anymore!"),
                make_field("fieldTwo", make_string_type()),
            ],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: embedded_internal_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("struct MockInput: InputObject {"), "actual:\n{}", actual);
        assert!(actual.contains("private(set) var __data: InputDict"), "actual:\n{}", actual);
        assert!(!actual.contains("public"), "actual:\n{}", actual);
        assert!(actual.contains("init(\n    fieldTwo: String\n  )"), "actual:\n{}", actual);
    }

    // MARK: - Casing Tests

    #[test]
    fn test_render_lowercased_input_object_name() {
        let input = make_input_object("mockInput", vec![make_field("field", make_non_null_int_type())]);
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("public struct MockInput: InputObject {"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_uppercased_input_object_name() {
        let input = make_input_object("MOCKInput", vec![make_field("field", make_non_null_int_type())]);
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("public struct MOCKInput: InputObject {"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_mixed_case_input_object_name() {
        let input = make_input_object("mOcK_Input", vec![make_field("field", make_non_null_int_type())]);
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("public struct MOcK_Input: InputObject {"), "actual:\n{}", actual);
    }

    // MARK: - Field Type Tests

    #[test]
    fn test_render_nullable_field_no_default() {
        let input = make_input_object("MockInput", vec![make_field("nullable", make_int_type())]);
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains(&format!("nullable: GraphQLNullable<{}> = nil", INT_SWIFT_TYPE)), "actual:\n{}", actual);
        assert!(actual.contains(&format!("public var nullable: GraphQLNullable<{}> {{", INT_SWIFT_TYPE)), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_nullable_field_with_default() {
        let input = make_input_object(
            "MockInput",
            vec![make_field_with_default(
                "nullableWithDefault",
                make_int_type(),
                GraphQLValue::Int(3),
            )],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains(&format!("nullableWithDefault: GraphQLNullable<{}> = nil", INT_SWIFT_TYPE)), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_non_nullable_field_no_default() {
        let input = make_input_object("MockInput", vec![make_field("nonNullable", make_non_null_int_type())]);
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains(&format!("nonNullable: {}\n  )", INT_SWIFT_TYPE)), "actual:\n{}", actual);
        assert!(actual.contains(&format!("public var nonNullable: {} {{", INT_SWIFT_TYPE)), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_non_nullable_field_with_default_generates_optional() {
        let input = make_input_object(
            "MockInput",
            vec![make_field_with_default(
                "nonNullableWithDefault",
                make_non_null_int_type(),
                GraphQLValue::Int(3),
            )],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains(&format!("nonNullableWithDefault: {}? = nil", INT_SWIFT_TYPE)), "actual:\n{}", actual);
        assert!(actual.contains("\"nonNullableWithDefault\": nonNullableWithDefault"), "actual:\n{}", actual);
        assert!(actual.contains(&format!("public var nonNullableWithDefault: {}? {{", INT_SWIFT_TYPE)), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_nullable_list_nullable_item() {
        let inner = GraphQLType::Scalar(Arc::new(GraphQLScalarType {
            name: GraphQLName::new("String".to_string()),
            documentation: None,
            specified_by_url: None,
        }));
        let list_type = GraphQLType::List(Box::new(inner));
        let input = make_input_object(
            "MockInput",
            vec![make_field("nullableListNullableItem", list_type)],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("nullableListNullableItem: GraphQLNullable<[String?]> = nil"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_nullable_list_non_nullable_item() {
        let inner = GraphQLType::NonNull(Box::new(GraphQLType::Scalar(Arc::new(GraphQLScalarType {
            name: GraphQLName::new("String".to_string()),
            documentation: None,
            specified_by_url: None,
        }))));
        let list_type = GraphQLType::List(Box::new(inner));
        let input = make_input_object(
            "MockInput",
            vec![make_field("nullableListNonNullableItem", list_type)],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("nullableListNonNullableItem: GraphQLNullable<[String]> = nil"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_non_null_list_nullable_item_no_default() {
        let inner = GraphQLType::Scalar(Arc::new(GraphQLScalarType {
            name: GraphQLName::new("String".to_string()),
            documentation: None,
            specified_by_url: None,
        }));
        let list_type = GraphQLType::NonNull(Box::new(GraphQLType::List(Box::new(inner))));
        let input = make_input_object(
            "MockInput",
            vec![make_field("nonNullableListNullableItem", list_type)],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("nonNullableListNullableItem: [String?]\n  )"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_non_null_list_nullable_item_with_default() {
        let inner = GraphQLType::Scalar(Arc::new(GraphQLScalarType {
            name: GraphQLName::new("String".to_string()),
            documentation: None,
            specified_by_url: None,
        }));
        let list_type = GraphQLType::NonNull(Box::new(GraphQLType::List(Box::new(inner))));
        let input = make_input_object(
            "MockInput",
            vec![make_field_with_default(
                "nonNullableListNullableItemWithDefault",
                list_type,
                GraphQLValue::List(vec![GraphQLValue::String("val".to_string())]),
            )],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("nonNullableListNullableItemWithDefault: [String?]? = nil"), "actual:\n{}", actual);
        assert!(actual.contains("\"nonNullableListNullableItemWithDefault\": nonNullableListNullableItemWithDefault ?? GraphQLNullable.none\n"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_non_null_list_non_null_item_no_default() {
        let inner = GraphQLType::NonNull(Box::new(GraphQLType::Scalar(Arc::new(GraphQLScalarType {
            name: GraphQLName::new("String".to_string()),
            documentation: None,
            specified_by_url: None,
        }))));
        let list_type = GraphQLType::NonNull(Box::new(GraphQLType::List(Box::new(inner))));
        let input = make_input_object(
            "MockInput",
            vec![make_field("nonNullableListNonNullableItem", list_type)],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("nonNullableListNonNullableItem: [String]\n  )"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_non_null_list_non_null_item_with_default() {
        let inner = GraphQLType::NonNull(Box::new(GraphQLType::Scalar(Arc::new(GraphQLScalarType {
            name: GraphQLName::new("String".to_string()),
            documentation: None,
            specified_by_url: None,
        }))));
        let list_type = GraphQLType::NonNull(Box::new(GraphQLType::List(Box::new(inner))));
        let input = make_input_object(
            "MockInput",
            vec![make_field_with_default(
                "nonNullableListNonNullableItemWithDefault",
                list_type,
                GraphQLValue::List(vec![GraphQLValue::String("val".to_string())]),
            )],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("nonNullableListNonNullableItemWithDefault: [String]? = nil"), "actual:\n{}", actual);
        // 2.0.0+: optional initializer parameters are null-coalesced into the InputDict
        assert!(actual.contains("\"nonNullableListNonNullableItemWithDefault\": nonNullableListNonNullableItemWithDefault ?? GraphQLNullable.none\n"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_nullable_list_nullable_enum() {
        let enum_type = GraphQLType::Enum(Arc::new(GraphQLEnumType {
            name: GraphQLName::new("EnumValue".to_string()),
            documentation: None,
            values: vec![],
        }));
        let list_type = GraphQLType::List(Box::new(enum_type));
        let input = make_input_object(
            "MockInput",
            vec![make_field("nullableListNullableItem", list_type)],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("nullableListNullableItem: GraphQLNullable<[GraphQLEnum<EnumValue>?]> = nil"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Documentation Tests

    #[test]
    fn test_render_with_documentation_include() {
        let input = make_input_object_with_docs(
            "MockInput",
            vec![make_field_with_docs("fieldOne", make_string_type(), "Field Documentation!")],
            "This is some great documentation!",
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("include", "include"),
        };
        let actual = render_body(&template);
        assert!(actual.contains("/// This is some great documentation!"), "actual:\n{}", actual);
        assert!(actual.contains("/// Field Documentation!"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_with_documentation_exclude() {
        let input = make_input_object_with_docs(
            "MockInput",
            vec![make_field_with_docs("fieldOne", make_string_type(), "Field Documentation!")],
            "This is some great documentation!",
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("exclude", "include"),
        };
        let actual = render_body(&template);
        assert!(!actual.contains("/// This is some great documentation!"), "actual:\n{}", actual);
        assert!(!actual.contains("/// Field Documentation!"), "actual:\n{}", actual);
    }

    // MARK: - Deprecation Tests

    #[test]
    fn test_render_deprecated_field_include_warnings() {
        let input = make_input_object(
            "MockInput",
            vec![make_field_deprecated("fieldOne", make_string_type(), "Not used anymore!")],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("include", "include"),
        };
        let actual = render_body(&template);
        assert!(actual.contains("@available(*, deprecated, message: \"Argument 'fieldOne' is deprecated.\")"), "actual:\n{}", actual);
        assert!(actual.contains("@available(*, deprecated, message: \"Not used anymore!\")"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_only_deprecated_fields_include_warnings_no_valid_initializer() {
        let input = make_input_object(
            "MockInput",
            vec![make_field_deprecated("fieldOne", make_string_type(), "Not used anymore!")],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("include", "include"),
        };
        let actual = render_body(&template);
        // Should have the deprecated annotation on the initializer
        assert!(actual.contains("@available(*, deprecated, message: \"Argument 'fieldOne' is deprecated.\")"), "actual:\n{}", actual);
        // Should have 2 inits: __data init + deprecated all-fields init (both public)
        // (the `InputDict` initializer carries an `@_spi` attribute from 2.0.0)
        let init_count = actual.matches("public init(").count();
        assert_eq!(init_count, 2, "Should have exactly 2 public init (data init + all-fields), actual:\n{}", actual);
    }

    #[test]
    fn test_render_deprecated_field_exclude_warnings() {
        let input = make_input_object(
            "MockInput",
            vec![make_field_deprecated("fieldOne", make_string_type(), "Not used anymore!")],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("include", "exclude"),
        };
        let actual = render_body(&template);
        assert!(!actual.contains("@available"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_deprecated_and_valid_fields_include_warnings() {
        let input = make_input_object(
            "MockInput",
            vec![
                make_field_deprecated("fieldOne", make_string_type(), "Not used anymore!"),
                make_field("fieldTwo", make_string_type()),
                make_field("fieldThree", make_string_type()),
                make_field_deprecated("fieldFour", make_string_type(), "Stop using this field!"),
            ],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("include", "include"),
        };
        let actual = render_body(&template);
        // Valid initializer with only non-deprecated fields
        assert!(actual.contains("public init(\n    fieldTwo: String,\n    fieldThree: String\n  )"), "actual:\n{}", actual);
        // Deprecated annotation listing both deprecated fields
        assert!(
            actual.contains("@available(*, deprecated, message: \"Arguments 'fieldOne, fieldFour' are deprecated.\")"),
            "actual:\n{}",
            actual
        );
        // Individual field deprecation annotations
        assert!(actual.contains("@available(*, deprecated, message: \"Not used anymore!\")"), "actual:\n{}", actual);
        assert!(actual.contains("@available(*, deprecated, message: \"Stop using this field!\")"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_deprecated_and_valid_fields_exclude_warnings_single_initializer() {
        let input = make_input_object(
            "MockInput",
            vec![
                make_field_deprecated("fieldOne", make_string_type(), "Not used anymore!"),
                make_field("fieldTwo", make_string_type()),
                make_field_deprecated("fieldThree", make_string_type(), "Stop using this field!"),
            ],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("include", "exclude"),
        };
        let actual = render_body(&template);
        // Should have only one initializer with all fields
        assert!(!actual.contains("@available"), "actual:\n{}", actual);
        assert!(actual.contains("fieldOne: String,\n    fieldTwo: String,\n    fieldThree: String"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_with_docs_and_deprecation_include() {
        let input = make_input_object_with_docs(
            "MockInput",
            vec![make_field_with_docs_and_deprecation(
                "fieldOne",
                make_string_type(),
                "Field Documentation!",
                "Not used anymore!",
            )],
            "This is some great documentation!",
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_options("include", "include"),
        };
        let actual = render_body(&template);
        assert!(actual.contains("/// This is some great documentation!"), "actual:\n{}", actual);
        assert!(actual.contains("/// Field Documentation!"), "actual:\n{}", actual);
        assert!(actual.contains("@available(*, deprecated, message: \"Not used anymore!\")"), "actual:\n{}", actual);
    }

    // MARK: - Field name casing tests

    #[test]
    fn test_render_mixed_case_field_name_uses_schema_name_in_dict() {
        let input = make_input_object("MockInput", vec![make_field("Field", make_nullable_string_type())]);
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        // The initializer parameter should use camelCase (field)
        assert!(actual.contains("field: GraphQLNullable<String> = nil"), "actual:\n{}", actual);
        // The dict key should use the schema name (Field)
        assert!(actual.contains("\"Field\": field"), "actual:\n{}", actual);
        // Property getter/setter should use schema name
        assert!(actual.contains("get { __data[\"Field\"] }"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_all_uppercase_field_name() {
        let input = make_input_object("MockInput", vec![make_field("FIELDNAME", make_nullable_string_type())]);
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("fieldname: GraphQLNullable<String> = nil"), "actual:\n{}", actual);
        assert!(actual.contains("\"FIELDNAME\": fieldname"), "actual:\n{}", actual);
    }

    // MARK: - Reserved Keyword Tests

    #[test]
    fn test_render_reserved_keyword_type_name() {
        for keyword in &["Type", "type"] {
            let input = make_input_object(keyword, vec![make_field("field", make_non_null_int_type())]);
            let template = InputObjectTemplate {
                graphql_input_object: input,
                config: spm_config(),
            };
            let actual = render_body(&template);
            let expected_name = format!(
                "{}_InputObject",
                crate::templates::rendering_helpers::string_casing::first_uppercased(keyword)
            );
            assert!(
                actual.contains(&format!("struct {}: InputObject", expected_name)),
                "keyword={}, actual:\n{}",
                keyword,
                actual
            );
        }
    }

    #[test]
    fn test_render_reserved_keyword_field_names() {
        let fields = vec![
            make_field("class", make_string_type()),
            make_field("self", make_string_type()),
        ];
        let input = make_input_object("MockInput", fields);
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_no_conversion_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("`class`: String"), "actual:\n{}", actual);
        assert!(actual.contains("\"class\": `class`"), "actual:\n{}", actual);
        assert!(actual.contains("public var `class`: String {"), "actual:\n{}", actual);
        assert!(actual.contains("`self`: String"), "actual:\n{}", actual);
    }

    // MARK: - Schema Customization Tests

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
        fields.insert("fieldOne".to_string(), GraphQLInputField {
            name: GraphQLName::new("fieldOne".to_string()),
            type_: make_string_type(),
            documentation: None,
            deprecation_reason: None,
            default_value: None,
        });
        fields.insert("myField".to_string(), custom_field);

        let mut gql_name = GraphQLName::new("MyInputObject".to_string());
        gql_name.custom_name = Some("MyCustomInputObject".to_string());
        let input = Arc::new(GraphQLInputObjectType {
            name: gql_name,
            documentation: None,
            is_one_of: false,
            fields,
        });

        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(actual.contains("// Renamed from GraphQL schema value: 'MyInputObject'"), "actual:\n{}", actual);
        assert!(actual.contains("struct MyCustomInputObject: InputObject"), "actual:\n{}", actual);
        assert!(actual.contains("myCustomField: String"), "actual:\n{}", actual);
        assert!(actual.contains("\"myField\": myCustomField"), "actual:\n{}", actual);
        assert!(actual.contains("// Renamed from GraphQL schema value: 'myField'"), "actual:\n{}", actual);
    }

    // MARK: - Namespace Tests

    #[test]
    fn test_render_with_namespace_for_enum_and_input_fields() {
        let enum_type = GraphQLType::Enum(Arc::new(GraphQLEnumType {
            name: GraphQLName::new("EnumValue".to_string()),
            documentation: None,
            values: vec![],
        }));
        let input_obj_type = GraphQLType::InputObject(Arc::new(GraphQLInputObjectType {
            name: GraphQLName::new("InnerInputObject".to_string()),
            documentation: None,
            is_one_of: false,
            fields: IndexMap::new(),
        }));
        let input = make_input_object(
            "MockInput",
            vec![
                make_field("enumField", enum_type),
                make_field("inputField", input_obj_type),
            ],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_relative_config_with_namespace("TestSchema"),
        };
        let actual = render_body(&template);
        assert!(actual.contains("GraphQLEnum<TestSchema.EnumValue>"), "actual:\n{}", actual);
        assert!(actual.contains("TestSchema.InnerInputObject"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_without_namespace_in_schema_module() {
        let enum_type = GraphQLType::Enum(Arc::new(GraphQLEnumType {
            name: GraphQLName::new("EnumValue".to_string()),
            documentation: None,
            values: vec![],
        }));
        let input = make_input_object(
            "MockInput",
            vec![make_field("enumField", enum_type)],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config_with_namespace("TestSchema"),
        };
        let actual = render_body(&template);
        // In schema module, no namespace prefix
        assert!(actual.contains("GraphQLEnum<EnumValue>"), "actual:\n{}", actual);
        assert!(!actual.contains("TestSchema.EnumValue"), "actual:\n{}", actual);
    }

    // MARK: - Schema namespace casing tests

    #[test]
    fn test_render_lowercase_schema_namespace() {
        let enum_type = GraphQLType::Enum(Arc::new(GraphQLEnumType {
            name: GraphQLName::new("EnumValue".to_string()),
            documentation: None,
            values: vec![],
        }));
        let input = make_input_object(
            "MockInput",
            vec![make_field("enumField", enum_type)],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_relative_config_with_namespace("testschema"),
        };
        let actual = render_body(&template);
        assert!(actual.contains("Testschema.EnumValue"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_uppercase_schema_namespace() {
        let enum_type = GraphQLType::Enum(Arc::new(GraphQLEnumType {
            name: GraphQLName::new("EnumValue".to_string()),
            documentation: None,
            values: vec![],
        }));
        let input = make_input_object(
            "MockInput",
            vec![make_field("enumField", enum_type)],
        );
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_relative_config_with_namespace("TESTSCHEMA"),
        };
        let actual = render_body(&template);
        assert!(actual.contains("TESTSCHEMA.EnumValue"), "actual:\n{}", actual);
    }

    // MARK: - Single field with closing brace test

    #[test]
    fn test_render_single_field_type_complete_structure() {
        let input = make_input_object("MockInput", vec![make_field("field", make_nullable_string_type())]);
        let template = InputObjectTemplate {
            graphql_input_object: input,
            config: spm_config(),
        };
        let actual = render_body(&template);
        // Check the full structure has init, dict entry, and property
        assert!(actual.contains("public init(\n    field: GraphQLNullable<String> = nil\n  )"), "actual:\n{}", actual);
        assert!(actual.contains("\"field\": field"), "actual:\n{}", actual);
        assert!(actual.contains("public var field: GraphQLNullable<String> {"), "actual:\n{}", actual);
        assert!(actual.contains("get { __data[\"field\"] }"), "actual:\n{}", actual);
        assert!(actual.contains("set { __data[\"field\"] = newValue }"), "actual:\n{}", actual);
        assert!(actual.ends_with("}\n"), "actual should end with closing brace + newline, actual:\n{}", actual);
    }
}
