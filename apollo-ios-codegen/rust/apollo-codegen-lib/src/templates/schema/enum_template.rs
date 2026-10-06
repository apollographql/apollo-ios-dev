//! Enum type template for Apollo iOS code generation.
//!
//! Mirrors Swift's `EnumTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/EnumTemplate.swift`.

use std::sync::Arc;

use graphql_compiler::schema::{GraphQLEnumType, GraphQLEnumValue, GraphQLNamedType};

use crate::config::composition::Composition;
use crate::config::conversion_strategies::EnumCases;
use crate::templates::rendering_helpers::graphql_name_rendering::{
    render_enum_value, render_named_type, EnumRenderContext, RenderContext,
};
use crate::templates::rendering_helpers::string_swift_name_escaping::escaped_swift_string_special_characters;
use crate::templates::rendering_helpers::template_string_documentation::render_documentation;
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, SchemaFileType, Scope, TemplateRenderer,
    TemplateTarget,
};

/// Provides the format to convert a GraphQL Enum into Swift code.
///
/// Mirrors Swift's `EnumTemplate` struct.
pub struct EnumTemplate {
    pub graphql_enum: Arc<GraphQLEnumType>,
    pub config: ConfigurationContext,
}

impl TemplateRenderer for EnumTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::SchemaFile(SchemaFileType::Enum)
    }

    fn render_body_template(&self, _non_fatal_error_recorder: &NonFatalErrorRecorder) -> String {
        let mut parts: Vec<String> = Vec::new();

        // Documentation
        if let Some(doc) =
            render_documentation(self.graphql_enum.documentation.as_deref(), &self.config)
        {
            parts.push(doc);
        }

        // Type name documentation (for custom names)
        if let Some(type_doc) = self.graphql_enum.name.type_name_documentation() {
            parts.push(type_doc);
        }

        let access_control = self.access_control_renderer(Scope::Parent).render();
        let typename = render_named_type(
            &GraphQLNamedType::Enum(Arc::clone(&self.graphql_enum)),
            &RenderContext::Typename {
                is_input_value: false,
            },
        );

        // Render enum cases
        let cases: Vec<String> = self
            .graphql_enum
            .values
            .iter()
            .filter_map(|value| self.enum_case(value))
            .collect();

        let cases_str = cases.join("\n");

        parts.push(format!(
            "{}{}enum {}: String, EnumType {{\n{}\n}}\n",
            self.config.nonisolated_modifier(),
            access_control,
            typename,
            cases_str,
        ));

        parts.join("\n")
    }
}

impl EnumTemplate {
    fn enum_case(&self, value: &GraphQLEnumValue) -> Option<String> {
        // Skip deprecated cases if configured to exclude
        if self.config.options().deprecated_enum_cases == Composition::Exclude
            && value.is_deprecated()
        {
            return None;
        }

        let mut case_parts: Vec<String> = Vec::new();

        let should_render_documentation = value.documentation.is_some()
            && self.config.options().schema_documentation == Composition::Include;

        // Documentation for the enum value
        if should_render_documentation {
            if let Some(doc) = &value.documentation {
                let doc_lines: Vec<String> = doc
                    .lines()
                    .map(|line| {
                        if line.trim().is_empty() {
                            "///".to_string()
                        } else {
                            format!("/// {}", line)
                        }
                    })
                    .collect();
                case_parts.push(format!("  {}", doc_lines.join("\n  ")));
            }
        }

        // Deprecation reason
        if let Some(reason) = &value.deprecation_reason {
            if should_render_documentation {
                case_parts.push("  ///".to_string());
            }
            let escaped = escaped_swift_string_special_characters(reason);
            case_parts.push(format!("  /// **Deprecated**: {}", escaped));
        }

        // Type name documentation (for custom names on values)
        if let Some(type_doc) = value.name.type_name_documentation() {
            case_parts.push(format!("  {}", type_doc));
        }

        // Case definition
        case_parts.push(self.case_definition(value));

        Some(case_parts.join("\n"))
    }

    fn case_definition(&self, value: &GraphQLEnumValue) -> String {
        let case_name = render_enum_value(value, EnumRenderContext::EnumCase, &self.config);

        if self.config.options().conversion_strategies.enum_cases != EnumCases::None {
            let raw_value = render_enum_value(value, EnumRenderContext::EnumRawValue, &self.config);
            format!("  case {} = \"{}\"", case_name, raw_value)
        } else {
            format!("  case {}", case_name)
        }
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

    /// Default config: embedded in target, default conversion strategies (camelCase enum cases)
    /// 2.1.0+: `markTypesNonisolated` defaults to true, so every enum declaration is prefixed.
    const NONISOLATED: &str = "nonisolated ";

    fn with_nonisolated(expected: &str) -> String {
        let out: Vec<String> = expected
            .split('\n')
            .map(|line| {
                if (line.starts_with("enum ") || line.starts_with("public enum "))
                    && !line.starts_with(NONISOLATED)
                {
                    format!("{}{}", NONISOLATED, line)
                } else {
                    line.to_string()
                }
            })
            .collect();
        out.join("\n")
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

    fn config_with_options(
        deprecated: &str,
        docs: &str,
        warnings: &str,
        enum_cases: &str,
    ) -> ConfigurationContext {
        make_config(&format!(
            r#"{{
            "schemaNamespace": "TestSchema",
            "input": {{}},
            "output": {{
                "schemaTypes": {{ "path": "./gen", "moduleType": {{"embeddedInTarget": {{"name": "TestTarget"}}}} }},
                "operations": {{"inSchemaModule": {{}}}},
                "testMocks": {{"none": {{}}}}
            }},
            "options": {{
                "deprecatedEnumCases": "{}",
                "schemaDocumentation": "{}",
                "warningsOnDeprecatedUsage": "{}",
                "conversionStrategies": {{ "enumCases": "{}" }}
            }}
        }}"#,
            deprecated, docs, warnings, enum_cases
        ))
    }

    fn make_enum_value(
        name: &str,
        deprecation_reason: Option<&str>,
        documentation: Option<&str>,
        custom_name: Option<&str>,
    ) -> GraphQLEnumValue {
        let mut gql_name = GraphQLName::new(name.to_string());
        if let Some(cn) = custom_name {
            gql_name.custom_name = Some(cn.to_string());
        }
        GraphQLEnumValue {
            name: gql_name,
            documentation: documentation.map(|s| s.to_string()),
            deprecation_reason: deprecation_reason.map(|s| s.to_string()),
        }
    }

    fn make_enum(
        name: &str,
        custom_name: Option<&str>,
        values: Vec<GraphQLEnumValue>,
        documentation: Option<&str>,
    ) -> Arc<GraphQLEnumType> {
        let mut gql_name = GraphQLName::new(name.to_string());
        if let Some(cn) = custom_name {
            gql_name.custom_name = Some(cn.to_string());
        }
        Arc::new(GraphQLEnumType {
            name: gql_name,
            documentation: documentation.map(|s| s.to_string()),
            values,
        })
    }

    fn render_body(template: &EnumTemplate) -> String {
        let recorder = NonFatalErrorRecorder::new();
        template.render_body_template(&recorder)
    }

    // MARK: - Access Level Tests

    #[test]
    fn test_render_spm_public_access() {
        let enum_type = make_enum(
            "TestEnum",
            None,
            vec![
                make_enum_value("ONE", None, None, None),
                make_enum_value("TWO", None, None, None),
            ],
            None,
        );
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: spm_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("public enum TestEnum: String, EnumType {"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_other_public_access() {
        let enum_type = make_enum(
            "TestEnum",
            None,
            vec![
                make_enum_value("ONE", None, None, None),
                make_enum_value("TWO", None, None, None),
            ],
            None,
        );
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: other_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("public enum TestEnum: String, EnumType {"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_embedded_internal_no_access_prefix() {
        let enum_type = make_enum(
            "TestEnum",
            None,
            vec![
                make_enum_value("ONE", None, None, None),
                make_enum_value("TWO", None, None, None),
            ],
            None,
        );
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: embedded_internal_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("enum TestEnum: String, EnumType {"),
            "actual:\n{}",
            actual
        );
        assert!(!actual.contains("public enum"), "actual:\n{}", actual);
    }

    #[test]
    fn test_render_embedded_public_no_access_prefix_on_parent() {
        // Embedded public: Parent scope returns empty string (no prefix)
        let enum_type = make_enum(
            "TestEnum",
            None,
            vec![
                make_enum_value("ONE", None, None, None),
                make_enum_value("TWO", None, None, None),
            ],
            None,
        );
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: embedded_public_config(),
        };
        let actual = render_body(&template);
        // Parent scope with embedded = no access modifier
        assert!(
            actual.contains("enum TestEnum: String, EnumType {"),
            "actual:\n{}",
            actual
        );
    }

    // MARK: - Casing Tests

    #[test]
    fn test_render_enum_name_first_uppercased() {
        let enum_type = make_enum(
            "anEnum",
            None,
            vec![
                make_enum_value("ONE", None, None, None),
                make_enum_value("TWO", None, None, None),
            ],
            None,
        );
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: default_config(),
        };
        let actual = render_body(&template);
        assert!(
            actual.contains("enum AnEnum: String, EnumType {"),
            "actual:\n{}",
            actual
        );
    }

    #[test]
    fn test_render_camel_case_conversion() {
        let values = vec![
            make_enum_value("lowercase", None, None, None),
            make_enum_value("UPPERCASE", None, None, None),
            make_enum_value("Capitalized", None, None, None),
            make_enum_value("snake_case", None, None, None),
            make_enum_value("UPPER_SNAKE_CASE", None, None, None),
            make_enum_value("_1", None, None, None),
            make_enum_value("_one_two_three_", None, None, None),
            make_enum_value("camelCased", None, None, None),
            make_enum_value("UpperCamelCase", None, None, None),
            make_enum_value("BEFORE2023", None, None, None),
            make_enum_value("associatedtype", None, None, None),
            make_enum_value("Protocol", None, None, None),
        ];
        let enum_type = make_enum("casedEnum", None, values, None);
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: config_with_options("include", "include", "include", "camelCase"),
        };
        let actual = render_body(&template);
        let expected = "\
enum CasedEnum: String, EnumType {
  case lowercase = \"lowercase\"
  case uppercase = \"UPPERCASE\"
  case capitalized = \"Capitalized\"
  case snakeCase = \"snake_case\"
  case upperSnakeCase = \"UPPER_SNAKE_CASE\"
  case _1 = \"_1\"
  case _oneTwoThree_ = \"_one_two_three_\"
  case camelCased = \"camelCased\"
  case upperCamelCase = \"UpperCamelCase\"
  case before2023 = \"BEFORE2023\"
  case `associatedtype` = \"associatedtype\"
  case `protocol` = \"Protocol\"
}
";
        assert_eq!(actual, with_nonisolated(expected));
    }

    #[test]
    fn test_render_no_conversion_strategy() {
        let values = vec![
            make_enum_value("lowercase", None, None, None),
            make_enum_value("UPPERCASE", None, None, None),
            make_enum_value("Capitalized", None, None, None),
            make_enum_value("snake_case", None, None, None),
            make_enum_value("UPPER_SNAKE_CASE", None, None, None),
            make_enum_value("_1", None, None, None),
            make_enum_value("_one_two_three_", None, None, None),
            make_enum_value("camelCased", None, None, None),
            make_enum_value("UpperCamelCase", None, None, None),
            make_enum_value("BEFORE2023", None, None, None),
            make_enum_value("associatedtype", None, None, None),
            make_enum_value("Protocol", None, None, None),
        ];
        let enum_type = make_enum("casedEnum", None, values, None);
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: config_with_options("include", "include", "include", "none"),
        };
        let actual = render_body(&template);
        let expected = "\
enum CasedEnum: String, EnumType {
  case lowercase
  case UPPERCASE
  case Capitalized
  case snake_case
  case UPPER_SNAKE_CASE
  case _1
  case _one_two_three_
  case camelCased
  case UpperCamelCase
  case BEFORE2023
  case `associatedtype`
  case `Protocol`
}
";
        assert_eq!(actual, with_nonisolated(expected));
    }

    // MARK: - Deprecation Tests

    #[test]
    fn test_render_deprecated_include_warnings_exclude() {
        let values = vec![
            make_enum_value("ONE", None, None, None),
            make_enum_value("TWO", Some("Deprecated for tests"), None, None),
            make_enum_value("THREE", None, None, None),
        ];
        let enum_type = make_enum("TestEnum", None, values, None);
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: config_with_options("include", "include", "exclude", "camelCase"),
        };
        let actual = render_body(&template);
        let expected = "\
enum TestEnum: String, EnumType {
  case one = \"ONE\"
  /// **Deprecated**: Deprecated for tests
  case two = \"TWO\"
  case three = \"THREE\"
}
";
        assert_eq!(actual, with_nonisolated(expected));
    }

    #[test]
    fn test_render_deprecated_include_warnings_include() {
        let values = vec![
            make_enum_value("ONE", None, None, None),
            make_enum_value("TWO", Some("Deprecated for tests"), None, None),
            make_enum_value("THREE", None, None, None),
        ];
        let enum_type = make_enum("TestEnum", None, values, None);
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: config_with_options("include", "include", "include", "camelCase"),
        };
        let actual = render_body(&template);
        let expected = "\
enum TestEnum: String, EnumType {
  case one = \"ONE\"
  /// **Deprecated**: Deprecated for tests
  case two = \"TWO\"
  case three = \"THREE\"
}
";
        assert_eq!(actual, with_nonisolated(expected));
    }

    #[test]
    fn test_render_deprecated_exclude_skips_cases() {
        let values = vec![
            make_enum_value("ONE", Some("Deprecated for tests"), None, None),
            make_enum_value("TWO", None, None, None),
            make_enum_value("THREE", Some("Deprecated for tests"), None, None),
        ];
        let enum_type = make_enum("TestEnum", None, values, None);
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: config_with_options("exclude", "include", "include", "camelCase"),
        };
        let actual = render_body(&template);
        let expected = "\
enum TestEnum: String, EnumType {
  case two = \"TWO\"
}
";
        assert_eq!(actual, with_nonisolated(expected));
    }

    #[test]
    fn test_render_deprecated_exclude_warnings_exclude() {
        let values = vec![
            make_enum_value("ONE", Some("Deprecated for tests"), None, None),
            make_enum_value("TWO", None, None, None),
            make_enum_value("THREE", Some("Deprecated for tests"), None, None),
        ];
        let enum_type = make_enum("TestEnum", None, values, None);
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: config_with_options("exclude", "include", "exclude", "camelCase"),
        };
        let actual = render_body(&template);
        let expected = "\
enum TestEnum: String, EnumType {
  case two = \"TWO\"
}
";
        assert_eq!(actual, with_nonisolated(expected));
    }

    // MARK: - Documentation Tests

    #[test]
    fn test_render_documentation_include_with_deprecation() {
        let values = vec![
            make_enum_value("ONE", Some("Deprecated for tests"), Some("Doc: One"), None),
            make_enum_value("TWO", None, Some("Doc: Two"), None),
            make_enum_value("THREE", Some("Deprecated for tests"), None, None),
        ];
        let enum_type = make_enum(
            "TestEnum",
            None,
            values,
            Some("This is some great documentation!"),
        );
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: config_with_options("include", "include", "include", "camelCase"),
        };
        let actual = render_body(&template);
        let expected = "\
/// This is some great documentation!
enum TestEnum: String, EnumType {
  /// Doc: One
  ///
  /// **Deprecated**: Deprecated for tests
  case one = \"ONE\"
  /// Doc: Two
  case two = \"TWO\"
  /// **Deprecated**: Deprecated for tests
  case three = \"THREE\"
}
";
        assert_eq!(actual, with_nonisolated(expected));
    }

    #[test]
    fn test_render_documentation_include_warnings_exclude_with_deprecation() {
        let values = vec![
            make_enum_value("ONE", Some("Deprecated for tests"), Some("Doc: One"), None),
            make_enum_value("TWO", None, Some("Doc: Two"), None),
            make_enum_value("THREE", Some("Deprecated for tests"), None, None),
        ];
        let enum_type = make_enum(
            "TestEnum",
            None,
            values,
            Some("This is some great documentation!"),
        );
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: config_with_options("include", "include", "exclude", "camelCase"),
        };
        let actual = render_body(&template);
        let expected = "\
/// This is some great documentation!
enum TestEnum: String, EnumType {
  /// Doc: One
  ///
  /// **Deprecated**: Deprecated for tests
  case one = \"ONE\"
  /// Doc: Two
  case two = \"TWO\"
  /// **Deprecated**: Deprecated for tests
  case three = \"THREE\"
}
";
        assert_eq!(actual, with_nonisolated(expected));
    }

    #[test]
    fn test_render_documentation_exclude_with_deprecation() {
        let values = vec![
            make_enum_value("ONE", Some("Deprecated for tests"), Some("Doc: One"), None),
            make_enum_value("TWO", None, Some("Doc: Two"), None),
            make_enum_value("THREE", Some("Deprecated for tests"), None, None),
        ];
        let enum_type = make_enum(
            "TestEnum",
            None,
            values,
            Some("This is some great documentation!"),
        );
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: config_with_options("include", "exclude", "exclude", "camelCase"),
        };
        let actual = render_body(&template);
        let expected = "\
enum TestEnum: String, EnumType {
  /// **Deprecated**: Deprecated for tests
  case one = \"ONE\"
  case two = \"TWO\"
  /// **Deprecated**: Deprecated for tests
  case three = \"THREE\"
}
";
        assert_eq!(actual, with_nonisolated(expected));
    }

    // MARK: - Reserved Keyword Tests

    #[test]
    fn test_render_reserved_keyword_has_suffixed_type() {
        for keyword in &["Type", "type"] {
            let values = vec![
                make_enum_value("ONE", None, None, None),
                make_enum_value("TWO", None, None, None),
            ];
            let enum_type = make_enum(keyword, None, values, None);
            let template = EnumTemplate {
                graphql_enum: enum_type,
                config: default_config(),
            };
            let actual = render_body(&template);
            let expected_name = format!(
                "{}_Enum",
                crate::templates::rendering_helpers::string_casing::first_uppercased(keyword)
            );
            assert!(
                actual.contains(&format!("enum {}: String, EnumType {{", expected_name)),
                "keyword={}, actual:\n{}",
                keyword,
                actual
            );
        }
    }

    // MARK: - Schema Customization Tests

    #[test]
    fn test_render_with_custom_names() {
        let values = vec![
            make_enum_value("caseOne", None, None, None),
            make_enum_value("myCase", None, None, Some("myCustomCase")),
        ];
        let enum_type = make_enum("MyEnum", Some("MyCustomEnum"), values, None);
        let template = EnumTemplate {
            graphql_enum: enum_type,
            config: default_config(),
        };
        let actual = render_body(&template);
        let expected = "\
// Renamed from GraphQL schema value: 'MyEnum'
enum MyCustomEnum: String, EnumType {
  case caseOne = \"caseOne\"
  // Renamed from GraphQL schema value: 'myCase'
  case myCustomCase = \"myCase\"
}
";
        assert_eq!(actual, with_nonisolated(expected));
    }
}
