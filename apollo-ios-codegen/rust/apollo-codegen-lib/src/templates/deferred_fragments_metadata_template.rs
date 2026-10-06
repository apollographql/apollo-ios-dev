//! Deferred fragments metadata template for code generation.
//!
//! Renders metadata for deferred fragments in an operation, including
//! DeferredFragmentIdentifiers and the responseFormat property.
//!
//! NOT a TemplateRenderer -- called internally by OperationDefinitionTemplate.
//!
//! Mirrors Swift's `DeferredFragmentsMetadataTemplate.swift` from
//! `Sources/ApolloCodegenLib/Templates/DeferredFragmentsMetadataTemplate.swift`.

use indexmap::IndexSet;

use graphql_compiler::DeferCondition;

use crate::templates::rendering_helpers::selection_set_name_generator::SelectionSetNameGenerator;
use crate::templates::rendering_helpers::string_swift_name_escaping::as_fragment_name;
use crate::templates::ConfigurationContext;

use ir::direct_selections::DirectSelections;
use ir::fields::Field;

/// Template for rendering deferred fragment metadata for an operation.
///
/// This is not a TemplateRenderer; it is called by OperationDefinitionTemplate
/// when the operation contains deferred fragments.
pub struct DeferredFragmentsMetadataTemplate<'a> {
    pub operation: &'a ir::Operation,
    pub config: &'a ConfigurationContext,
    pub render_access_control: String,
}

/// Internal struct representing a deferred fragment path with type information.
#[derive(Debug)]
struct DeferredPathTypeInfo {
    path: Vec<String>,
    defer_condition: DeferCondition,
    type_name: String,
}

impl DeferredPathTypeInfo {
    /// Returns a hash value combining path and defer_condition (not type_name).
    /// Used for deduplication of DeferredFragmentIdentifiers.
    fn path_defer_condition_key(&self) -> (Vec<String>, String) {
        (self.path.clone(), self.defer_condition.label.clone())
    }
}

impl<'a> DeferredFragmentsMetadataTemplate<'a> {
    /// Renders the deferred fragments metadata block placed inside the operation
    /// class.
    ///
    /// Mirrors Swift 2.0.0 `DeferredFragmentsMetadataTemplate.render()`: a MARK,
    /// the `ResponseFormat` typealias, the `DeferredFragmentIdentifiers` enum and
    /// the `responseFormat` property. Returns an empty string when the operation
    /// has no deferred fragments.
    pub fn render(&self) -> String {
        let path_type_info = self.collect_deferred_paths(
            self.operation
                .root_field
                .selection_set
                .selections
                .as_deref(),
            &[],
        );

        if path_type_info.is_empty() {
            return String::new();
        }

        format!(
            "// MARK: - Deferred Fragment Metadata\n\n\
             public typealias ResponseFormat = IncrementalDeferredResponseFormat\n\
             {}\n\
             {}",
            self.render_deferred_fragment_identifiers(&path_type_info),
            self.render_deferred_fragments_property(&path_type_info),
        )
    }

    /// Renders the DeferredFragmentIdentifiers enum.
    fn render_deferred_fragment_identifiers(&self, infos: &[DeferredPathTypeInfo]) -> String {
        let mut result = String::new();
        result.push_str("enum DeferredFragmentIdentifiers {\n");

        // Deduplicate by (path, label) key
        let mut seen: IndexSet<(Vec<String>, String)> = IndexSet::new();
        for info in infos {
            let key = info.path_defer_condition_key();
            if !seen.insert(key) {
                continue;
            }

            let path_elements: Vec<String> =
                info.path.iter().map(|p| format!("\"{}\"", p)).collect();

            result.push_str(&format!(
                "  static let {} = DeferredFragmentIdentifier(label: \"{}\", fieldPath: [{}])\n",
                info.defer_condition.label,
                info.defer_condition.label,
                path_elements.join(", "),
            ));
        }

        result.push_str("}\n");
        result
    }

    /// Renders the `responseFormat` property (Swift 2.0.0
    /// `DeferredFragmentsPropertyTemplate`).
    fn render_deferred_fragments_property(&self, infos: &[DeferredPathTypeInfo]) -> String {
        let mut result = String::new();
        result.push_str(
            "public static let responseFormat: ResponseFormat = IncrementalDeferredResponseFormat(\n  deferredFragments: [\n",
        );
        for info in infos {
            result.push_str(&format!(
                "    DeferredFragmentIdentifiers.{}: {}.self,\n",
                info.defer_condition.label, info.type_name,
            ));
        }
        result.push_str("  ]\n)");
        result
    }

    /// Recursively collects deferred paths from direct selections.
    ///
    /// Mirrors Swift's `DeferredFragmentsPathTypeInfo(from:path:)`.
    fn collect_deferred_paths(
        &self,
        direct_selections: Option<&DirectSelections>,
        path: &[String],
    ) -> Vec<DeferredPathTypeInfo> {
        let direct_selections = match direct_selections {
            Some(ds) if !ds.is_empty() => ds,
            _ => return Vec::new(),
        };

        let mut infos: Vec<DeferredPathTypeInfo> = Vec::new();

        // Process entity fields -- recurse into their selection sets
        for field in direct_selections.fields.values() {
            if let Field::Entity(entity_field) = field {
                let field_name = entity_field
                    .underlying_field
                    .alias
                    .as_deref()
                    .unwrap_or(&entity_field.underlying_field.name);
                let mut field_path = path.to_vec();
                field_path.push(field_name.to_string());
                infos.extend(self.collect_deferred_paths(
                    entity_field.selection_set.selections.as_deref(),
                    &field_path,
                ));
            }
        }

        // Process inline fragments
        for fragment in direct_selections.inline_fragments.values() {
            if let Some(defer_condition) = fragment.type_info().defer_condition() {
                let selection_set_name = SelectionSetNameGenerator::generated_selection_set_name(
                    fragment.type_info(),
                    None,
                    crate::templates::rendering_helpers::selection_set_name_generator::NameFormat::OmittingRoot,
                    self.config,
                );

                infos.push(DeferredPathTypeInfo {
                    path: path.to_vec(),
                    defer_condition: defer_condition.clone(),
                    type_name: format!("Data.{}", selection_set_name),
                });
            }

            infos.extend(
                self.collect_deferred_paths(fragment.selection_set.selections.as_deref(), path),
            );
        }

        // Process named fragments
        for fragment in direct_selections.named_fragments.values() {
            if let Some(defer_condition) = fragment.type_info.defer_condition() {
                let frag_name =
                    as_fragment_name(&fragment.fragment.definition.name, &self.config.capitalizer);
                infos.push(DeferredPathTypeInfo {
                    path: path.to_vec(),
                    defer_condition: defer_condition.clone(),
                    type_name: frag_name,
                });
            }

            infos.extend(
                self.collect_deferred_paths(
                    fragment
                        .fragment
                        .root_field
                        .selection_set
                        .selections
                        .as_deref(),
                    path,
                ),
            );
        }

        infos
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_deferred_path_type_info_key() {
        let info = DeferredPathTypeInfo {
            path: vec!["query".to_string(), "animal".to_string()],
            defer_condition: DeferCondition {
                label: "deferredLabel".to_string(),
                variable: None,
            },
            type_name: "Data.AsAnimal".to_string(),
        };
        let key = info.path_defer_condition_key();
        assert_eq!(key.0, vec!["query".to_string(), "animal".to_string()]);
        assert_eq!(key.1, "deferredLabel");
    }
}
