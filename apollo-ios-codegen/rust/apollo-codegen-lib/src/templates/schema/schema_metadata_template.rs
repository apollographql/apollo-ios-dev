//! Schema metadata template for Apollo iOS code generation.
//!
//! Mirrors Swift's `SchemaMetadataTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/SchemaMetadataTemplate.swift`.

use std::sync::Arc;

use graphql_compiler::schema::GraphQLNamedType;

use crate::templates::rendering_helpers::graphql_name_rendering::{
    render_named_type, RenderContext,
};
use crate::templates::rendering_helpers::string_casing::first_uppercased;
use crate::templates::rendering_helpers::template_string_documentation::render_documentation;
use crate::templates::SPI;
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, SchemaFileType, Scope, TemplateRenderer,
    TemplateTarget,
};

/// Provides the format to define a schema in Swift code. The schema represents
/// metadata used by the GraphQL executor at runtime to convert response data
/// into corresponding Swift types.
///
/// Mirrors Swift's `SchemaMetadataTemplate` struct.
pub struct SchemaMetadataTemplate {
    pub schema: Arc<ir::Schema>,
    pub config: ConfigurationContext,
    schema_namespace: String,
}

impl SchemaMetadataTemplate {
    pub fn new(schema: Arc<ir::Schema>, config: ConfigurationContext) -> Self {
        let schema_namespace = first_uppercased(config.schema_namespace());
        Self {
            schema,
            config,
            schema_namespace,
        }
    }

    /// Renders the protocol definitions for SelectionSet, InlineFragment, etc.
    ///
    /// When `prefix` is `Some`, protocols are prefixed (for detached/external use).
    /// When `prefix` is `None`, protocols are rendered without prefix (inline in module).
    ///
    /// Mirrors Swift's `protocolDefinition(prefix:schemaNamespace:)`.
    fn protocol_definition(&self, prefix: Option<&str>) -> String {
        let access_level = self.access_control_renderer(Scope::Member).render();
        let prefix_str = prefix.unwrap_or("");

        format!(
            "{ni}{access_level}protocol {prefix_str}SelectionSet: {api}.SelectionSet & {api}.RootSelectionSet\n\
             where Schema == {ns}.SchemaMetadata {{}}\n\
             \n\
             {ni}{access_level}protocol {prefix_str}InlineFragment: {api}.SelectionSet & {api}.InlineFragment\n\
             where Schema == {ns}.SchemaMetadata {{}}\n\
             \n\
             {ni}{access_level}protocol {prefix_str}MutableSelectionSet: {api}.MutableRootSelectionSet\n\
             where Schema == {ns}.SchemaMetadata {{}}\n\
             \n\
             {ni}{access_level}protocol {prefix_str}MutableInlineFragment: {api}.MutableSelectionSet & {api}.InlineFragment\n\
             where Schema == {ns}.SchemaMetadata {{}}",
            ni = self.config.nonisolated_modifier(),
            access_level = access_level,
            prefix_str = prefix_str,
            api = self.config.apollo_api_target_name(),
            ns = self.schema_namespace,
        )
    }

    /// Renders the objectType dictionary and lookup function.
    ///
    /// Mirrors Swift's `objectTypeFunction` computed property (Swift 1.25.4+ renders a dictionary lookup).
    fn object_type_function(&self) -> String {
        let access_level = self
            .access_control_renderer(Scope::Member)
            .render_with_spis(&[SPI::Execution]);

        let dict_entries: Vec<String> = self
            .schema
            .referenced_types
            .objects
            .iter()
            .map(|obj| {
                let typename = render_named_type(
                    &GraphQLNamedType::Object(Arc::clone(obj)),
                    &RenderContext::Typename {
                        is_input_value: false,
                    },
                );
                format!(
                    "    \"{}\": {}.Objects.{}",
                    obj.name.schema_name, self.schema_namespace, typename
                )
            })
            .collect();

        let dict_str = dict_entries.join(",\n");

        format!(
            "  private static let objectTypeMap: [String: {api}.Object] = [\n\
             {dict}\n\
             \x20\x20]\n\
             \n\
             \x20\x20{access}static func objectType(forTypename typename: String) -> {api}.Object? {{\n\
             \x20\x20\x20\x20objectTypeMap[typename]\n\
             \x20\x20}}",
            api = self.config.apollo_api_target_name(),
            dict = dict_str,
            access = access_level,
        )
    }
}

impl TemplateRenderer for SchemaMetadataTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::SchemaFile(SchemaFileType::SchemaMetadata)
    }

    fn render_body_template(&self, _non_fatal_error_recorder: &NonFatalErrorRecorder) -> String {
        let parent_access = self.access_control_renderer(Scope::Parent).render();
        let member_access = self.access_control_renderer(Scope::Member).render();

        let mut parts: Vec<String> = Vec::new();

        // Protocol definitions or typealiases depending on module type
        if !self.config.output().schema_types.is_in_module() {
            // Embedded in target: render typealiases (protocols go in detached section)
            let typealiases = format!(
                "{pa}typealias SelectionSet = {ns}_SelectionSet\n\
                 \n\
                 {pa}typealias InlineFragment = {ns}_InlineFragment\n\
                 \n\
                 {pa}typealias MutableSelectionSet = {ns}_MutableSelectionSet\n\
                 \n\
                 {pa}typealias MutableInlineFragment = {ns}_MutableInlineFragment",
                pa = parent_access,
                ns = self.schema_namespace,
            );
            parts.push(typealiases);
        } else {
            // SPM / Other: render protocol definitions inline
            parts.push(self.protocol_definition(None));
        }

        // Documentation
        if let Some(doc) = render_documentation(self.schema.documentation.as_deref(), &self.config)
        {
            parts.push(doc);
        }

        // SchemaMetadata enum
        let object_type_fn = self.object_type_function();
        let schema_metadata = format!(
            "{ni}{pa}enum SchemaMetadata: {api}.SchemaMetadata {{\n\
             \x20\x20{ma}static let configuration: any {api}.SchemaConfiguration.Type = SchemaConfiguration.self\n\
             \n\
             {obj_fn}\n\
             }}",
            ni = self.config.nonisolated_modifier(),
            pa = parent_access,
            api = self.config.apollo_api_target_name(),
            ma = member_access,
            obj_fn = object_type_fn,
        );
        parts.push(schema_metadata);

        // Type namespace enums
        let ni = self.config.nonisolated_modifier();
        let type_enums = format!(
            "{ni}{pa}enum Objects {{}}\n\
             {ni}{pa}enum Interfaces {{}}\n\
             {ni}{pa}enum Unions {{}}",
            ni = ni,
            pa = parent_access,
        );
        parts.push(type_enums);

        // Join with blank lines and add trailing newline
        parts.join("\n\n") + "\n"
    }

    fn render_detached_template(
        &self,
        _non_fatal_error_recorder: &NonFatalErrorRecorder,
    ) -> Option<String> {
        // Only render detached protocols when NOT in a module (embedded in target)
        if self.config.output().schema_types.is_in_module() {
            return None;
        }

        let prefix = format!("{}_", self.schema_namespace);
        Some(self.protocol_definition(Some(&prefix)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;
    use crate::templates::NonFatalErrorRecorder;
    use graphql_compiler::graphql_name::GraphQLName;
    use graphql_compiler::schema::GraphQLObjectType;
    use graphql_compiler::{GraphQLNamedType, RootTypeDefinition};
    use indexmap::IndexMap;
    use ir::ReferencedTypes;

    fn make_config(json: &str) -> ApolloCodegenConfiguration {
        serde_json::from_str(json).unwrap()
    }

    fn spm_config() -> ApolloCodegenConfiguration {
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

    fn spm_config_with_namespace(namespace: &str) -> ApolloCodegenConfiguration {
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
            namespace
        ))
    }

    fn embedded_public_config() -> ApolloCodegenConfiguration {
        make_config(
            r#"{
            "schemaNamespace": "aName",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"embeddedInTarget": {"name": "CustomTarget", "accessModifier": "public"}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        )
    }

    fn embedded_internal_config() -> ApolloCodegenConfiguration {
        make_config(
            r#"{
            "schemaNamespace": "aName",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"embeddedInTarget": {"name": "CustomTarget", "accessModifier": "internal"}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        )
    }

    fn other_config() -> ApolloCodegenConfiguration {
        make_config(
            r#"{
            "schemaNamespace": "aName",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"other": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        )
    }

    fn make_root_types() -> RootTypeDefinition {
        RootTypeDefinition {
            query_type: GraphQLNamedType::Object(Arc::new(GraphQLObjectType {
                name: GraphQLName::new("Query".to_string()),
                documentation: None,
                fields: IndexMap::new(),
                interfaces: vec![],
                key_fields: None,
            })),
            mutation_type: None,
            subscription_type: None,
        }
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

    fn make_schema(
        objects: Vec<Arc<GraphQLObjectType>>,
        documentation: Option<String>,
    ) -> Arc<ir::Schema> {
        let mut types: Vec<GraphQLNamedType> = Vec::new();
        for obj in &objects {
            types.push(GraphQLNamedType::Object(Arc::clone(obj)));
        }
        let rt = ReferencedTypes::new(&types, make_root_types());
        Arc::new(ir::Schema::new(Arc::new(rt), documentation))
    }

    fn make_template(
        schema: Arc<ir::Schema>,
        config: ApolloCodegenConfiguration,
    ) -> SchemaMetadataTemplate {
        SchemaMetadataTemplate::new(schema, ConfigurationContext::new(config, None))
    }

    fn render_body(template: &SchemaMetadataTemplate) -> String {
        let recorder = NonFatalErrorRecorder::new();
        template.render_body_template(&recorder)
    }

    fn render_detached(template: &SchemaMetadataTemplate) -> Option<String> {
        let recorder = NonFatalErrorRecorder::new();
        template.render_detached_template(&recorder)
    }

    // MARK: - Typealias & Protocol Tests

    #[test]
    fn test_render_embedded_internal_typealiases_and_detached_protocols() {
        let schema = make_schema(vec![], None);
        let template = make_template(schema, embedded_internal_config());

        let body = render_body(&template);
        let detached = render_detached(&template);

        // Body should have typealiases (no access modifier for internal embedded)
        assert!(body.contains("typealias SelectionSet = AName_SelectionSet"));
        assert!(body.contains("typealias InlineFragment = AName_InlineFragment"));
        assert!(body.contains("typealias MutableSelectionSet = AName_MutableSelectionSet"));
        assert!(body.contains("typealias MutableInlineFragment = AName_MutableInlineFragment"));

        // Detached should have protocol definitions
        let detached = detached.expect("detached should exist for embedded");
        assert!(detached.contains(
            "protocol AName_SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet"
        ));
        assert!(detached.contains("where Schema == AName.SchemaMetadata {}"));
        assert!(detached.contains(
            "protocol AName_InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment"
        ));
        assert!(detached
            .contains("protocol AName_MutableSelectionSet: ApolloAPI.MutableRootSelectionSet"));
        assert!(detached.contains("protocol AName_MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment"));
        // Internal access: no "public" prefix
        assert!(!detached.contains("public "));
    }

    #[test]
    fn test_render_embedded_public_typealiases_and_detached_protocols() {
        let schema = make_schema(vec![], None);
        let template = make_template(schema, embedded_public_config());

        let body = render_body(&template);
        let detached = render_detached(&template);

        // Body should have typealiases (no parent access for embedded)
        assert!(body.contains("typealias SelectionSet = AName_SelectionSet"));

        // Detached should have public protocol definitions
        let detached = detached.expect("detached should exist for embedded");
        assert!(detached.contains("public protocol AName_SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet"));
        assert!(detached.contains("public protocol AName_InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment"));
        assert!(detached.contains(
            "public protocol AName_MutableSelectionSet: ApolloAPI.MutableRootSelectionSet"
        ));
        assert!(detached.contains("public protocol AName_MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment"));
    }

    #[test]
    fn test_render_spm_inline_protocols_no_detached() {
        let schema = make_schema(vec![], None);
        let template = make_template(schema, spm_config_with_namespace("aName"));

        let body = render_body(&template);
        let detached = render_detached(&template);

        // Body should have inline protocol definitions with public access
        assert!(body.contains(
            "public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet"
        ));
        assert!(body.contains("where Schema == AName.SchemaMetadata {}"));
        assert!(body.contains(
            "public protocol InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment"
        ));
        assert!(
            body.contains("public protocol MutableSelectionSet: ApolloAPI.MutableRootSelectionSet")
        );
        assert!(body.contains("public protocol MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment"));

        // No typealiases
        assert!(!body.contains("typealias"));

        // No detached
        assert!(detached.is_none());
    }

    #[test]
    fn test_render_other_module_inline_protocols_no_detached() {
        let schema = make_schema(vec![], None);
        let template = make_template(schema, other_config());

        let body = render_body(&template);
        let detached = render_detached(&template);

        // Body should have inline protocol definitions with public access
        assert!(body.contains(
            "public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet"
        ));
        assert!(body.contains("where Schema == AName.SchemaMetadata {}"));

        // No detached
        assert!(detached.is_none());
    }

    // MARK: - Schema Enum Tests

    #[test]
    fn test_render_embedded_internal_schema_metadata_enum() {
        let schema = make_schema(vec![], None);
        let template = make_template(schema, embedded_internal_config());

        let body = render_body(&template);

        // No access modifier for internal embedded parent
        assert!(body.contains("enum SchemaMetadata: ApolloAPI.SchemaMetadata {"));
        assert!(body.contains("static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self"));
    }

    #[test]
    fn test_render_embedded_public_schema_metadata_enum() {
        let schema = make_schema(vec![], None);
        let template = make_template(schema, embedded_public_config());

        let body = render_body(&template);

        // No parent access (embedded), but member access is public
        assert!(body.contains("enum SchemaMetadata: ApolloAPI.SchemaMetadata {"));
        assert!(body.contains("public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self"));
    }

    #[test]
    fn test_render_spm_schema_metadata_enum() {
        let schema = make_schema(vec![], None);
        let template = make_template(schema, spm_config());

        let body = render_body(&template);

        // Public access for SPM
        assert!(body.contains("public enum SchemaMetadata: ApolloAPI.SchemaMetadata {"));
        assert!(body.contains("public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self"));
    }

    #[test]
    fn test_render_other_schema_metadata_enum() {
        let schema = make_schema(vec![], None);
        let template = make_template(schema, other_config());

        let body = render_body(&template);

        assert!(body.contains("public enum SchemaMetadata: ApolloAPI.SchemaMetadata {"));
        assert!(body.contains("public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self"));
    }

    // MARK: - Object Type Function Tests

    /// Whether `objectType(forTypename:)` looks the object up in a `[String: Object]`
    /// dictionary (upstream 1.25.4-1.25.7 and 2.1.0+) instead of a `switch` statement.
    const OBJECT_TYPE_LOOKUP_IS_DICTIONARY: bool = true;

    /// Asserts the lookup entry rendered for an object with the given schema name and Swift name.
    fn assert_object_type_entry(body: &str, schema_name: &str, swift_name: &str) {
        let expected = if OBJECT_TYPE_LOOKUP_IS_DICTIONARY {
            format!("\"{}\": ObjectSchema.Objects.{}", schema_name, swift_name)
        } else {
            format!(
                "case \"{}\": return ObjectSchema.Objects.{}",
                schema_name, swift_name
            )
        };
        assert!(body.contains(&expected), "body:\n{}", body);
    }

    #[test]
    fn test_render_with_referenced_objects_correctly_cased() {
        let schema = make_schema(
            vec![
                make_object("objA"),
                make_object("objB"),
                make_object("objC"),
            ],
            None,
        );
        let template = make_template(schema, spm_config_with_namespace("objectSchema"));

        let body = render_body(&template);

        if OBJECT_TYPE_LOOKUP_IS_DICTIONARY {
            assert!(
                body.contains("objectTypeMap: [String: ApolloAPI.Object]"),
                "body:\n{}",
                body
            );
            assert!(body.contains("objectTypeMap[typename]"), "body:\n{}", body);
            assert!(!body.contains("switch typename {"), "body:\n{}", body);
        } else {
            assert!(body.contains("switch typename {"), "body:\n{}", body);
            assert!(body.contains("default: return nil"), "body:\n{}", body);
            assert!(!body.contains("objectTypeMap"), "body:\n{}", body);
        }
        assert_object_type_entry(&body, "objA", "ObjA");
        assert_object_type_entry(&body, "objB", "ObjB");
        assert_object_type_entry(&body, "objC", "ObjC");
        assert!(body
            .contains("static func objectType(forTypename typename: String) -> ApolloAPI.Object?"));
    }

    #[test]
    fn test_render_with_referenced_other_types_only_includes_objects() {
        // Only GraphQLObjectType should appear in the lookup entries
        let obj = make_object("ObjectA");
        let schema = make_schema(vec![obj], None);
        let template = make_template(schema, spm_config_with_namespace("ObjectSchema"));

        let body = render_body(&template);

        assert_object_type_entry(&body, "ObjectA", "ObjectA");
        // Should NOT contain non-object types (interfaces, unions, etc. are not in the lookup)
        assert!(!body.contains("InterfaceB"));
        assert!(!body.contains("UnionC"));
    }

    #[test]
    fn test_render_object_type_function_has_execution_spi() {
        let schema = make_schema(
            vec![
                make_object("objA"),
                make_object("objB"),
                make_object("objC"),
            ],
            None,
        );
        let template = make_template(schema, spm_config_with_namespace("objectSchema"));

        let body = render_body(&template);

        // 2.0.0+: objectType(forTypename:) is exposed through the Execution SPI
        assert!(
            body.contains("@_spi(Execution) public static func objectType(forTypename typename: String) -> ApolloAPI.Object?"),
            "body:\n{}",
            body
        );
    }

    // MARK: - Type Namespace Enum Tests

    #[test]
    fn test_render_embedded_internal_type_namespace_enums() {
        let schema = make_schema(vec![make_object("ObjectA")], None);
        let template = make_template(schema, embedded_internal_config());

        let body = render_body(&template);

        assert!(body.contains("enum Objects {}"));
        assert!(body.contains("enum Interfaces {}"));
        assert!(body.contains("enum Unions {}"));
        // No "public" prefix for internal
        assert!(!body.contains("public enum Objects"));
    }

    #[test]
    fn test_render_embedded_public_type_namespace_enums() {
        let schema = make_schema(vec![make_object("ObjectA")], None);
        let template = make_template(schema, embedded_public_config());

        let body = render_body(&template);

        // Embedded parent access is empty, so no "public" on parent enums
        assert!(body.contains("enum Objects {}"));
        assert!(body.contains("enum Interfaces {}"));
        assert!(body.contains("enum Unions {}"));
    }

    #[test]
    fn test_render_spm_type_namespace_enums() {
        let schema = make_schema(vec![make_object("ObjectA")], None);
        let template = make_template(schema, spm_config());

        let body = render_body(&template);

        assert!(body.contains("public enum Objects {}"));
        assert!(body.contains("public enum Interfaces {}"));
        assert!(body.contains("public enum Unions {}"));
    }

    #[test]
    fn test_render_other_type_namespace_enums() {
        let schema = make_schema(vec![make_object("ObjectA")], None);
        let template = make_template(schema, other_config());

        let body = render_body(&template);

        assert!(body.contains("public enum Objects {}"));
        assert!(body.contains("public enum Interfaces {}"));
        assert!(body.contains("public enum Unions {}"));
    }

    // MARK: - Documentation Tests

    #[test]
    fn test_render_with_documentation_include() {
        let schema = make_schema(
            vec![],
            Some("This is some great documentation!".to_string()),
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
            "options": { "schemaDocumentation": "include" }
        }"#,
        );
        let template = make_template(schema, config);

        let body = render_body(&template);

        assert!(body.contains("/// This is some great documentation!"));
        assert!(body.contains("enum SchemaMetadata: ApolloAPI.SchemaMetadata {"));
    }

    #[test]
    fn test_render_with_documentation_exclude() {
        let schema = make_schema(
            vec![],
            Some("This is some great documentation!".to_string()),
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
            "options": { "schemaDocumentation": "exclude" }
        }"#,
        );
        let template = make_template(schema, config);

        let body = render_body(&template);

        assert!(!body.contains("/// This is some great documentation!"));
        assert!(body.contains("enum SchemaMetadata: ApolloAPI.SchemaMetadata {"));
    }
}
