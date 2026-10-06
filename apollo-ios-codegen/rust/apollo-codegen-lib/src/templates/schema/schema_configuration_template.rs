//! Schema configuration template for Apollo iOS code generation.
//!
//! Mirrors Swift's `SchemaConfigurationTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/SchemaConfigurationTemplate.swift`.

use crate::templates::{
    ConfigurationContext, HeaderCommentTemplate, NonFatalErrorRecorder, SchemaFileType, Scope,
    TemplateRenderer, TemplateTarget,
};

/// Renders the Cache Key Resolution extension for a generated schema.
///
/// Mirrors Swift's `SchemaConfigurationTemplate` struct.
pub struct SchemaConfigurationTemplate {
    pub config: ConfigurationContext,
}

impl TemplateRenderer for SchemaConfigurationTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::SchemaFile(SchemaFileType::SchemaConfiguration)
    }

    fn render_header_template(
        &self,
        _non_fatal_error_recorder: &NonFatalErrorRecorder,
    ) -> Option<String> {
        Some(HeaderCommentTemplate::editable_file_header(
            "provide custom configuration for a generated GraphQL schema.",
        ))
    }

    fn render_body_template(&self, _non_fatal_error_recorder: &NonFatalErrorRecorder) -> String {
        let parent_access = self.access_control_renderer(Scope::Parent).render();
        let member_access = self.access_control_renderer(Scope::Member).render();

        format!(
            "{ni}{pa}enum SchemaConfiguration: {api}.SchemaConfiguration {{\n\
             \x20\x20{ma}static func cacheKeyInfo(for type: {api}.Object, object: {api}.ObjectData) -> CacheKeyInfo? {{\n\
             \x20\x20\x20\x20// Implement this function to configure cache key resolution for your schema types.\n\
             \x20\x20\x20\x20return nil\n\
             \x20\x20}}\n\
             }}\n",
            ni = self.config.nonisolated_modifier(),
            pa = parent_access,
            api = self.config.apollo_api_target_name(),
            ma = member_access,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;

    fn make_config(json: &str) -> ApolloCodegenConfiguration {
        serde_json::from_str(json).unwrap()
    }

    fn spm_config() -> ApolloCodegenConfiguration {
        make_config(
            r#"{
            "schemaNamespace": "testSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        )
    }

    fn make_template(config: ApolloCodegenConfiguration) -> SchemaConfigurationTemplate {
        SchemaConfigurationTemplate {
            config: ConfigurationContext::new(config, None),
        }
    }

    // MARK: - Header Tests

    #[test]
    fn test_render_header_editable_with_reason() {
        let template = make_template(spm_config());

        let (rendered, _) = {
            let result = template.render();
            (result.body, result.errors)
        };

        // Verify the full header matches Swift's expected output
        assert!(rendered.contains("// @generated"));
        assert!(rendered.contains("This file was automatically generated and can be edited to"));
        assert!(
            rendered.contains("// provide custom configuration for a generated GraphQL schema.")
        );
        assert!(rendered.contains("// Any changes to this file will not be overwritten by future"));
        assert!(rendered.contains("// code generation execution."));
    }

    // MARK: - Body Tests

    #[test]
    fn test_render_spm_body() {
        let template = make_template(spm_config());

        let (rendered, _) = {
            let result = template.render();
            (result.body, result.errors)
        };

        // SPM generates public access
        assert!(
            rendered.contains("public enum SchemaConfiguration: ApolloAPI.SchemaConfiguration {")
        );
        assert!(rendered.contains("public static func cacheKeyInfo(for type: ApolloAPI.Object, object: ApolloAPI.ObjectData) -> CacheKeyInfo?"));
        assert!(rendered.contains(
            "// Implement this function to configure cache key resolution for your schema types."
        ));
        assert!(rendered.contains("return nil"));
    }

    // MARK: - Access Level Tests

    #[test]
    fn test_render_embedded_public_access() {
        let config = make_config(
            r#"{
            "schemaNamespace": "testSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"embeddedInTarget": {"name": "TestTarget", "accessModifier": "public"}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        );
        let template = make_template(config);

        let (rendered, _) = {
            let result = template.render();
            (result.body, result.errors)
        };

        // Embedded public: parent has no access modifier, member is public
        assert!(rendered.contains("enum SchemaConfiguration: ApolloAPI.SchemaConfiguration {"));
        assert!(rendered.contains("public static func cacheKeyInfo(for type: ApolloAPI.Object, object: ApolloAPI.ObjectData) -> CacheKeyInfo?"));
        // Should NOT have "public enum" (parent is empty for embedded)
        assert!(!rendered.contains("public enum SchemaConfiguration"));
    }

    #[test]
    fn test_render_embedded_internal_access() {
        let config = make_config(
            r#"{
            "schemaNamespace": "testSchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"embeddedInTarget": {"name": "TestTarget", "accessModifier": "internal"}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        );
        let template = make_template(config);

        let (rendered, _) = {
            let result = template.render();
            (result.body, result.errors)
        };

        // Embedded internal: no access modifiers at all
        assert!(rendered.contains("enum SchemaConfiguration: ApolloAPI.SchemaConfiguration {"));
        assert!(rendered.contains("static func cacheKeyInfo(for type: ApolloAPI.Object, object: ApolloAPI.ObjectData) -> CacheKeyInfo?"));
        assert!(!rendered.contains("public "));
    }
}
