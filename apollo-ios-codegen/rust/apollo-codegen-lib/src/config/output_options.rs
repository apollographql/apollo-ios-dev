use serde::de::{self, MapAccess, Visitor};
use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

use crate::capitalization_rule::CapitalizationRule;
use crate::inflection_rule::InflectionRule;

use super::composition::Composition;
use super::conversion_strategies::ConversionStrategies;
use super::deprecated::APQConfig;
use super::operation_document_format::OperationDocumentFormat;
use super::schema_customization::SchemaCustomization;
use super::selection_set_initializers::SelectionSetInitializers;

/// Rules and options to customize the generated code.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.OutputOptions` struct.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutputOptions {
    /// Any non-default rules for capitalization you wish to include.
    ///
    /// Rules are applied to the names of generated field accessors, initializer parameters,
    /// enum cases, input object fields, and test mock fields. Schema and selection set *type*
    /// names are not affected.
    pub additional_capitalization_rules: Vec<CapitalizationRule>,
    /// Any non-default rules for pluralization or singularization you wish to include.
    pub additional_inflection_rules: Vec<InflectionRule>,
    /// How deprecated enum cases from the schema should be handled.
    pub deprecated_enum_cases: Composition,
    /// Whether schema documentation is added to the generated files.
    pub schema_documentation: Composition,
    /// Which generated selection sets should include generated initializers.
    pub selection_set_initializers: SelectionSetInitializers,
    /// How to generate the operation documents for your generated operations.
    pub operation_document_format: OperationDocumentFormat,
    /// Customization options to be applied to the schema during code generation.
    pub schema_customization: SchemaCustomization,
    /// Whether to reduce the number of schema types that are generated to only those that are
    /// referenced in an operation. When `true`, object types that merely implement a referenced
    /// interface are not generated unless they declare `@typePolicy` themselves.
    pub reduce_generated_schema_types: bool,
    /// Generate import statements that are compatible with including `Apollo` via Cocoapods.
    pub cocoapods_compatible_import_statements: bool,
    /// Annotate generated Swift code with the Swift `available` attribute and `deprecated`
    /// argument for parts of the GraphQL schema annotated with the built-in `@deprecated`
    /// directive.
    pub warnings_on_deprecated_usage: Composition,
    /// Rules for how to convert the names of values from the schema in generated code.
    pub conversion_strategies: ConversionStrategies,
    /// Whether unused previously generated files will be automatically deleted.
    pub prune_generated_files: bool,
    /// Whether generated GraphQL operation and local cache mutation class types will be
    /// marked as `final`.
    pub mark_operation_definitions_as_final: bool,
    /// Whether generated schema type file names will have a suffix appended to their
    /// file name to help avoid naming conflicts with other files in the project.
    pub append_schema_type_filename_suffix: bool,
    /// When true, generated types are marked `nonisolated` for Swift 6.2+ compatibility.
    /// Defaults to true (matching Swift 2.1.0 compiled with Swift 6.2+).
    pub mark_types_nonisolated: bool,
}

impl Default for OutputOptions {
    fn default() -> Self {
        Self {
            additional_capitalization_rules: vec![],
            additional_inflection_rules: vec![],
            deprecated_enum_cases: Composition::Include,
            schema_documentation: Composition::Include,
            selection_set_initializers: SelectionSetInitializers::empty(),
            operation_document_format: OperationDocumentFormat::DEFINITION,
            schema_customization: SchemaCustomization::default(),
            reduce_generated_schema_types: false,
            cocoapods_compatible_import_statements: false,
            warnings_on_deprecated_usage: Composition::Include,
            conversion_strategies: ConversionStrategies::default(),
            prune_generated_files: true,
            mark_operation_definitions_as_final: false,
            append_schema_type_filename_suffix: false,
            mark_types_nonisolated: true,
        }
    }
}

// Valid keys for OutputOptions (current + legacy).
const VALID_OUTPUT_OPTIONS_KEYS: &[&str] = &[
    "additionalCapitalizationRules",
    "additionalInflectionRules",
    "queryStringLiteralFormat",
    "deprecatedEnumCases",
    "schemaDocumentation",
    "selectionSetInitializers",
    "apqs",
    "operationDocumentFormat",
    "schemaCustomization",
    "reduceGeneratedSchemaTypes",
    "cocoapodsCompatibleImportStatements",
    "warningsOnDeprecatedUsage",
    "conversionStrategies",
    "pruneGeneratedFiles",
    "markOperationDefinitionsAsFinal",
    "appendSchemaTypeFilenameSuffix",
    "markTypesNonisolated",
];

impl<'de> Deserialize<'de> for OutputOptions {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct OutputOptionsVisitor;

        impl<'de> Visitor<'de> for OutputOptionsVisitor {
            type Value = OutputOptions;

            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("an OutputOptions object")
            }

            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
                let defaults = OutputOptions::default();

                let mut additional_capitalization_rules: Option<Vec<CapitalizationRule>> = None;
                let mut additional_inflection_rules: Option<Vec<InflectionRule>> = None;
                let mut deprecated_enum_cases: Option<Composition> = None;
                let mut schema_documentation: Option<Composition> = None;
                let mut selection_set_initializers: Option<SelectionSetInitializers> = None;
                let mut operation_document_format: Option<OperationDocumentFormat> = None;
                let mut apqs: Option<APQConfig> = None;
                let mut schema_customization: Option<SchemaCustomization> = None;
                let mut reduce_generated_schema_types: Option<bool> = None;
                let mut cocoapods_compatible_import_statements: Option<bool> = None;
                let mut warnings_on_deprecated_usage: Option<Composition> = None;
                let mut conversion_strategies: Option<ConversionStrategies> = None;
                let mut prune_generated_files: Option<bool> = None;
                let mut mark_operation_definitions_as_final: Option<bool> = None;
                let mut append_schema_type_filename_suffix: Option<bool> = None;
                let mut mark_types_nonisolated: Option<bool> = None;

                while let Some(key) = map.next_key::<String>()? {
                    if !VALID_OUTPUT_OPTIONS_KEYS.contains(&key.as_str()) {
                        return Err(de::Error::custom(format!("Unrecognized key found: {key}")));
                    }

                    match key.as_str() {
                        "additionalCapitalizationRules" => {
                            additional_capitalization_rules = Some(map.next_value()?);
                        }
                        "additionalInflectionRules" => {
                            additional_inflection_rules = Some(map.next_value()?);
                        }
                        "queryStringLiteralFormat" => {
                            // Legacy key: accepted but value is unused.
                            let _: serde_json::Value = map.next_value()?;
                        }
                        "deprecatedEnumCases" => {
                            deprecated_enum_cases = Some(map.next_value()?);
                        }
                        "schemaDocumentation" => {
                            schema_documentation = Some(map.next_value()?);
                        }
                        "selectionSetInitializers" => {
                            selection_set_initializers = Some(map.next_value()?);
                        }
                        "apqs" => {
                            apqs = Some(map.next_value()?);
                        }
                        "operationDocumentFormat" => {
                            operation_document_format = Some(map.next_value()?);
                        }
                        "schemaCustomization" => {
                            schema_customization = Some(map.next_value()?);
                        }
                        "reduceGeneratedSchemaTypes" => {
                            reduce_generated_schema_types = Some(map.next_value()?);
                        }
                        "cocoapodsCompatibleImportStatements" => {
                            cocoapods_compatible_import_statements = Some(map.next_value()?);
                        }
                        "warningsOnDeprecatedUsage" => {
                            warnings_on_deprecated_usage = Some(map.next_value()?);
                        }
                        "conversionStrategies" => {
                            conversion_strategies = Some(map.next_value()?);
                        }
                        "pruneGeneratedFiles" => {
                            prune_generated_files = Some(map.next_value()?);
                        }
                        "markOperationDefinitionsAsFinal" => {
                            mark_operation_definitions_as_final = Some(map.next_value()?);
                        }
                        "appendSchemaTypeFilenameSuffix" => {
                            append_schema_type_filename_suffix = Some(map.next_value()?);
                        }
                        "markTypesNonisolated" => {
                            mark_types_nonisolated = Some(map.next_value()?);
                        }
                        _ => unreachable!(), // Already checked above
                    }
                }

                // operationDocumentFormat: try current key first, then legacy `apqs` migration
                let operation_document_format = operation_document_format.unwrap_or_else(|| {
                    apqs.map(OperationDocumentFormat::from)
                        .unwrap_or(defaults.operation_document_format)
                });

                Ok(OutputOptions {
                    additional_capitalization_rules: additional_capitalization_rules
                        .unwrap_or(defaults.additional_capitalization_rules),
                    additional_inflection_rules: additional_inflection_rules
                        .unwrap_or(defaults.additional_inflection_rules),
                    deprecated_enum_cases: deprecated_enum_cases
                        .unwrap_or(defaults.deprecated_enum_cases),
                    schema_documentation: schema_documentation
                        .unwrap_or(defaults.schema_documentation),
                    selection_set_initializers: selection_set_initializers
                        .unwrap_or(defaults.selection_set_initializers),
                    operation_document_format,
                    schema_customization: schema_customization
                        .unwrap_or(defaults.schema_customization),
                    reduce_generated_schema_types: reduce_generated_schema_types
                        .unwrap_or(defaults.reduce_generated_schema_types),
                    cocoapods_compatible_import_statements: cocoapods_compatible_import_statements
                        .unwrap_or(defaults.cocoapods_compatible_import_statements),
                    warnings_on_deprecated_usage: warnings_on_deprecated_usage
                        .unwrap_or(defaults.warnings_on_deprecated_usage),
                    conversion_strategies: conversion_strategies
                        .unwrap_or(defaults.conversion_strategies),
                    prune_generated_files: prune_generated_files
                        .unwrap_or(defaults.prune_generated_files),
                    mark_operation_definitions_as_final: mark_operation_definitions_as_final
                        .unwrap_or(defaults.mark_operation_definitions_as_final),
                    append_schema_type_filename_suffix: append_schema_type_filename_suffix
                        .unwrap_or(defaults.append_schema_type_filename_suffix),
                    mark_types_nonisolated: mark_types_nonisolated
                        .unwrap_or(defaults.mark_types_nonisolated),
                })
            }
        }

        deserializer.deserialize_map(OutputOptionsVisitor)
    }
}

impl Serialize for OutputOptions {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut map = serializer.serialize_map(Some(14))?;
        map.serialize_entry(
            "additionalCapitalizationRules",
            &self.additional_capitalization_rules,
        )?;
        map.serialize_entry(
            "additionalInflectionRules",
            &self.additional_inflection_rules,
        )?;
        map.serialize_entry("deprecatedEnumCases", &self.deprecated_enum_cases)?;
        map.serialize_entry("schemaDocumentation", &self.schema_documentation)?;
        map.serialize_entry("selectionSetInitializers", &self.selection_set_initializers)?;
        map.serialize_entry("operationDocumentFormat", &self.operation_document_format)?;
        map.serialize_entry("schemaCustomization", &self.schema_customization)?;
        map.serialize_entry(
            "reduceGeneratedSchemaTypes",
            &self.reduce_generated_schema_types,
        )?;
        map.serialize_entry(
            "cocoapodsCompatibleImportStatements",
            &self.cocoapods_compatible_import_statements,
        )?;
        map.serialize_entry(
            "warningsOnDeprecatedUsage",
            &self.warnings_on_deprecated_usage,
        )?;
        map.serialize_entry("conversionStrategies", &self.conversion_strategies)?;
        map.serialize_entry("pruneGeneratedFiles", &self.prune_generated_files)?;
        map.serialize_entry(
            "markOperationDefinitionsAsFinal",
            &self.mark_operation_definitions_as_final,
        )?;
        map.serialize_entry(
            "appendSchemaTypeFilenameSuffix",
            &self.append_schema_type_filename_suffix,
        )?;
        map.serialize_entry("markTypesNonisolated", &self.mark_types_nonisolated)?;
        map.end()
    }
}
