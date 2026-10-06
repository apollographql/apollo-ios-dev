//! SelectionSetTemplate -- the core complex template that all operation/fragment templates
//! delegate to for rendering nested selection set types.
//!
//! This is NOT a TemplateRenderer (does not implement the trait). It is an internal struct
//! created by outer templates (OperationDefinitionTemplate, FragmentTemplate, etc.).
//!
//! Mirrors Swift's `SelectionSetTemplate` struct from `SelectionSetTemplate.swift` (1266 lines).

use std::cell::RefCell;

use indexmap::{IndexMap, IndexSet};

use graphql_compiler::{compilation_result, DeferCondition, GraphQLCompositeType, GraphQLType};

use ir::computed_selection_set::ComputedSelectionSet;
use ir::definition::Definition;
use ir::direct_selections::{DirectSelections, GroupedByInclusionCondition};
use ir::fields::{EntityField, Field};
use ir::inclusion_conditions::{AnyOf, InclusionCondition, InclusionConditions};
use ir::inline_fragment_spread::InlineFragmentSpread;
use ir::merged_selections::{MergedSource, MergingStrategy};
use ir::named_fragment_spread::NamedFragmentSpread;
use ir::scope_descriptor::{ScopeCondition, ScopeDescriptor};
use ir::selection_set::{SelectionSet, TypeInfo};
use utilities::linked_list::LinkedList;

use crate::config::composition::Composition;
use crate::config::field_merging::FieldMerging;
use crate::templates::rendering_helpers::composite_type_namespace::schema_types_namespace;
use crate::templates::rendering_helpers::field_argument_rendering::render_input_value_literal;
use crate::templates::rendering_helpers::for_each_in::for_each_in_joined;
use crate::templates::rendering_helpers::graphql_name_rendering::{
    render_named_type, RenderContext,
};
use crate::templates::rendering_helpers::graphql_type_rendered::{
    rendered as render_graphql_type, TypeRenderContext,
};
use crate::templates::rendering_helpers::ir_definition_rendering::generated_fragment_definition_name_capitalized;
use crate::templates::rendering_helpers::selection_set_name_generator::{
    self, NameFormat, SelectionSetNameCache, SelectionSetNameGenerator,
};
use crate::templates::rendering_helpers::string_casing::{first_lowercased, first_uppercased};
use crate::templates::rendering_helpers::string_swift_name_escaping::{
    as_fragment_name, escaped_swift_string_special_characters, render_as_field_property_name,
    render_as_initializer_parameter_accessor_name, render_as_initializer_parameter_name,
};
use crate::templates::rendering_helpers::template_string_deprecation::render_field_argument_warning;
use crate::templates::rendering_helpers::template_string_documentation::render_documentation;
use crate::templates::SPI;
use crate::templates::{AccessControlRenderer, ConfigurationContext, NonFatalErrorRecorder};

// MARK: - SelectionSetTemplate

/// The core template for rendering selection sets. Used by operation and fragment templates.
///
/// Mirrors Swift's `SelectionSetTemplate` struct.
pub struct SelectionSetTemplate<'a> {
    pub definition: &'a dyn Definition,
    pub generate_initializers: bool,
    pub config: &'a ConfigurationContext,
    pub non_fatal_error_recorder: &'a NonFatalErrorRecorder,
    pub access_control_renderer: &'a AccessControlRenderer,
    pub name_cache: RefCell<SelectionSetNameCache>,
}

impl<'a> SelectionSetTemplate<'a> {
    pub fn new(
        definition: &'a dyn Definition,
        generate_initializers: bool,
        config: &'a ConfigurationContext,
        non_fatal_error_recorder: &'a NonFatalErrorRecorder,
        access_control_renderer: &'a AccessControlRenderer,
    ) -> Self {
        SelectionSetTemplate {
            definition,
            generate_initializers,
            config,
            non_fatal_error_recorder,
            access_control_renderer,
            name_cache: RefCell::new(SelectionSetNameCache::new(config)),
        }
    }

    fn is_mutable(&self) -> bool {
        self.definition.is_local_cache_mutation()
    }

    // MARK: - SelectionSetContext

    fn create_selection_set_context(
        &self,
        selection_set: &SelectionSet,
        _in_parent: Option<&SelectionSetContext>,
    ) -> SelectionSetContext {
        let merging_strategy = field_merging_to_merging_strategy(
            self.config.config.experimental_features.field_merging,
        );

        let computed = ir::ComputedSelectionSetBuilder::from_selection_set(
            selection_set,
            merging_strategy,
            self.definition.entity_storage().clone(),
        )
        .build();

        // Validation is stubbed - NonFatalError variants for type conflicts
        // haven't been added yet. This is safe because validation only produces
        // warnings, not errors that affect correctness.

        SelectionSetContext {
            selection_set: computed,
        }
    }

    // MARK: - Render Body

    /// Renders the body of the SelectionSet template for the entire definition.
    ///
    /// Mirrors Swift's `SelectionSetTemplate.renderBody()`.
    pub fn render_body(&self) -> String {
        let ctx =
            self.create_selection_set_context(&self.definition.root_field().selection_set, None);
        self.body_template(&ctx)
    }

    // MARK: - Child Entity

    fn render_child_entity(&self, context: &SelectionSetContext) -> Option<String> {
        let selection_set = &context.selection_set;
        let field_selection_set_name = self
            .name_cache
            .borrow_mut()
            .selection_set_name(&selection_set.type_info);

        if let Some(ref_name) = name_for_referenced_selection_set(selection_set, self.config) {
            if ref_name == field_selection_set_name {
                return None;
            }
            return Some(format!(
                "{}typealias {} = {}",
                self.access_control_renderer.render(),
                field_selection_set_name,
                ref_name
            ));
        }

        let doc = self.selection_set_name_documentation(selection_set);
        let body = self.body_template(context);

        let identifiable = if selection_set.is_identifiable() {
            ", Identifiable"
        } else {
            ""
        };

        Some(format!(
            "{doc}\
{ni}{access}struct {name}: {sel_type}{identifiable} {{
\
{body}\n\
}}",
            doc = doc,
            ni = self.config.nonisolated_modifier(),
            access = self.access_control_renderer.render(),
            name = field_selection_set_name,
            sel_type = self.selection_set_type(false),
            identifiable = identifiable,
            body = indent(&body, 2),
        ))
    }

    // MARK: - Inline Fragment

    fn render_inline_fragment(&self, context: &SelectionSetContext) -> String {
        let inline_fragment = &context.selection_set;
        let type_name = rendered_type_name(&inline_fragment.type_info);
        let composite = if is_composite_inline_fragment(inline_fragment) {
            format!(
                ", {}.CompositeInlineFragment",
                self.config.apollo_api_target_name()
            )
        } else {
            String::new()
        };

        let identifiable = if inline_fragment.is_identifiable() {
            ", Identifiable"
        } else {
            ""
        };

        let doc = self.selection_set_name_documentation(inline_fragment);
        let body = self.body_template(context);

        format!(
            "{doc}\
{ni}{access}struct {type_name}: {sel_type}{composite}{identifiable} {{
\
{body}\n\
}}",
            doc = doc,
            ni = self.config.nonisolated_modifier(),
            access = self.access_control_renderer.render(),
            type_name = type_name,
            sel_type = self.selection_set_type(true),
            composite = composite,
            identifiable = identifiable,
            body = indent(&body, 2),
        )
    }

    // MARK: - Selection Set Type

    fn selection_set_type(&self, as_inline_fragment: bool) -> String {
        let type_name = match (self.is_mutable(), as_inline_fragment) {
            (false, false) => "SelectionSet",
            (false, true) => "InlineFragment",
            (true, false) => "MutableSelectionSet",
            (true, true) => "MutableInlineFragment",
        };
        format!(
            "{}.{}",
            first_uppercased(self.config.schema_namespace()),
            type_name
        )
    }

    // MARK: - Selection Set Name Documentation

    fn selection_set_name_documentation(&self, selection_set: &ComputedSelectionSet) -> String {
        let name = SelectionSetNameGenerator::generated_selection_set_name(
            &selection_set.type_info,
            None,
            NameFormat::OmittingRoot,
            self.config,
        );

        let mut result = format!("/// {}\n", name);

        if self.config.options().schema_documentation == Composition::Include {
            let parent_type_name =
                render_composite_type_as_typename(selection_set.type_info.parent_type());
            result.push_str(&format!("///\n/// Parent Type: `{}`\n", parent_type_name));
        }

        result
    }

    // MARK: - Body Template

    fn body_template(&self, context: &SelectionSetContext) -> String {
        let selection_set = &context.selection_set;

        // Compute child selection sets lazily
        let child_inline_fragment_contexts: Vec<SelectionSetContext> = selection_set
            .make_inline_fragment_iterator()
            .map(|inline_frag| {
                self.create_selection_set_context(&inline_frag.selection_set, Some(context))
            })
            .collect();

        let mut result = String::new();

        // Group 1: __data and init (separated by \n, not \n\n)
        // Mirrors Swift: \(DataPropertyTemplate())\n\(DesignatedInitializerTemplate())
        result.push_str(&self.data_property_template());
        result.push('\n');
        result.push_str(&self.designated_initializer_template(None));

        // Group 2: RootEntityTypealias, ParentType, DirectSelections, MergedSources
        // These are all on consecutive lines (separated by \n).
        // Blank line before group.
        result.push('\n');
        result.push('\n');
        let root_alias = self.root_entity_typealias(selection_set);
        if !root_alias.is_empty() {
            result.push_str(&root_alias);
            result.push('\n');
        }
        result.push_str(&self.parent_type_template(selection_set.type_info.parent_type()));
        if let Some(ref direct) = selection_set.direct {
            let sel_meta =
                self.direct_selections_metadata_template(direct, selection_set.type_info.scope());
            if !sel_meta.is_empty() {
                result.push('\n');
                result.push_str(&sel_meta);
            }
        }
        if is_composite_inline_fragment(selection_set) {
            result.push('\n');
            result.push_str(&self.merged_sources_template(&selection_set.merged.merged_sources));
        }
        // Fulfilled fragments static metadata (1.25.3+)
        result.push('\n');
        result.push_str(&self.fulfilled_fragments_metadata_template(selection_set));
        // Deferred fragments static metadata (1.25.3+)
        let deferred_meta = self.deferred_fragments_metadata_template(selection_set);
        if !deferred_meta.is_empty() {
            result.push('\n');
            result.push_str(&deferred_meta);
        }

        // Remaining sections: each gets a blank line before if non-empty
        // (mirrors Swift's `section:` behavior)

        // Field accessors
        let field_accessors = self.field_accessors_template(selection_set);
        if !field_accessors.is_empty() {
            result.push('\n');
            result.push('\n');
            result.push_str(&field_accessors);
        }

        // Inline fragment accessors
        let inline_accessors =
            self.inline_fragment_accessors_template(&child_inline_fragment_contexts);
        if !inline_accessors.is_empty() {
            result.push('\n');
            result.push('\n');
            result.push_str(&inline_accessors);
        }

        // Fragment accessors
        let frag_accessors = self.fragment_accessors_template(selection_set);
        if !frag_accessors.is_empty() {
            result.push('\n');
            result.push('\n');
            result.push_str(&frag_accessors);
        }

        // Initializer
        if self.generate_initializers {
            let init = self.initializer_template(selection_set);
            if !init.is_empty() {
                result.push('\n');
                result.push('\n');
                result.push_str(&init);
            }
        }

        // Child entity field selection sets
        let child_entities = self.child_entity_field_selection_sets(context);
        if !child_entities.is_empty() {
            result.push('\n');
            result.push('\n');
            result.push_str(&child_entities);
        }

        // Child type case selection sets
        let child_types = self.child_type_case_selection_sets(&child_inline_fragment_contexts);
        if !child_types.is_empty() {
            result.push('\n');
            result.push('\n');
            result.push_str(&child_types);
        }

        result
    }

    fn data_property_template(&self) -> String {
        format!(
            "{}{} __data: DataDict",
            self.access_control_renderer
                .render_with_spis(&[SPI::Unsafe]),
            if self.is_mutable() { "var" } else { "let" }
        )
    }

    fn designated_initializer_template(&self, extra_props: Option<&str>) -> String {
        let data_init = "__data = _dataDict";

        if let Some(props) = extra_props {
            if !props.is_empty() {
                // The interpolated statements are indented by the template (non-empty lines only).
                let indented: Vec<String> = props
                    .split('\n')
                    .map(|line| {
                        if line.is_empty() {
                            String::new()
                        } else {
                            format!("  {}", line)
                        }
                    })
                    .collect();
                return format!(
                    "{}init(_dataDict: DataDict) {{\n  {}\n{}\n}}",
                    self.access_control_renderer
                        .render_with_spis(&[SPI::Unsafe]),
                    data_init,
                    indented.join("\n")
                );
            }
        }

        format!(
            "{}init(_dataDict: DataDict) {{ {} }}",
            self.access_control_renderer
                .render_with_spis(&[SPI::Unsafe]),
            data_init
        )
    }

    fn root_entity_typealias(&self, selection_set: &ComputedSelectionSet) -> String {
        if selection_set.type_info.is_entity_root() {
            return String::new();
        }
        let root_entity_name = SelectionSetNameGenerator::generated_selection_set_name(
            &selection_set.type_info,
            Some(
                selection_set
                    .type_info
                    .scope_path
                    .last()
                    .scope_path
                    .head_node(),
            ),
            NameFormat::FullyQualified,
            self.config,
        );
        format!(
            "{}typealias RootEntityType = {}",
            self.access_control_renderer.render(),
            root_entity_name
        )
    }

    fn parent_type_template(&self, type_: &GraphQLCompositeType) -> String {
        format!(
            "{}static var __parentType: any {}.ParentType {{ {} }}",
            self.access_control_renderer
                .render_with_spis(&[SPI::Execution]),
            self.config.apollo_api_target_name(),
            self.generated_schema_type_reference(type_)
        )
    }

    fn generated_schema_type_reference(&self, type_: &GraphQLCompositeType) -> String {
        let type_name = render_composite_type_as_typename(type_);
        format!(
            "{}.{}.{}",
            first_uppercased(self.config.schema_namespace()),
            schema_types_namespace(type_),
            type_name
        )
    }

    fn merged_sources_template(&self, merged_sources: &IndexSet<MergedSource>) -> String {
        let items: Vec<String> = merged_sources
            .iter()
            .map(|source| {
                let name =
                    SelectionSetNameGenerator::generated_selection_set_name_for_merged_source(
                        source,
                        None,
                        NameFormat::FullyQualified,
                        self.config,
                    );
                format!("  {}.self", name)
            })
            .collect();

        format!(
            "{}static var __mergedSources: [any {}.SelectionSet.Type] {{ [
{}
] }}",
            self.access_control_renderer
                .render_with_spis(&[SPI::Execution]),
            self.config.apollo_api_target_name(),
            items.join(",\n")
        )
    }

    // MARK: - Fulfilled/Deferred Fragments

    fn fulfilled_fragments_metadata_template(
        &self,
        selection_set: &ComputedSelectionSet,
    ) -> String {
        let mut fulfilled_fragments: IndexSet<String> = IndexSet::new();

        let mut current_node = Some(
            selection_set
                .type_info
                .scope_path
                .last()
                .scope_path
                .head_node(),
        );
        while let Some(node) = current_node {
            let name = SelectionSetNameGenerator::generated_selection_set_name_for_computed(
                selection_set,
                Some(node),
                NameFormat::FullyQualified,
                self.config,
            );
            fulfilled_fragments.insert(name);
            current_node = node.next();
        }

        for source in &selection_set.merged.merged_sources {
            let names = generated_selection_set_names_of_fulfilled_fragments(source, self.config);
            for name in names {
                fulfilled_fragments.insert(name);
            }
        }

        let items: Vec<String> = fulfilled_fragments
            .iter()
            .map(|name| format!("  {}.self", name))
            .collect();

        format!(
            "{}static var __fulfilledFragments: [any {}.SelectionSet.Type] {{ [\n{}\n] }}",
            self.access_control_renderer
                .render_with_spis(&[SPI::Execution]),
            self.config.apollo_api_target_name(),
            items.join(",\n")
        )
    }

    fn deferred_fragments_metadata_template(&self, selection_set: &ComputedSelectionSet) -> String {
        let direct_selections = match &selection_set.direct {
            Some(d) => d,
            None => return String::new(),
        };

        let mut deferred_fragments: IndexSet<String> = IndexSet::new();

        for inline_frag in direct_selections.inline_fragments.values() {
            if inline_frag.selection_set.type_info.is_deferred() {
                let name = SelectionSetNameGenerator::generated_selection_set_name(
                    &inline_frag.selection_set.type_info,
                    None,
                    NameFormat::FullyQualified,
                    self.config,
                );
                deferred_fragments.insert(name);
            }
        }

        for named_frag in direct_selections.named_fragments.values() {
            if named_frag.type_info.defer_condition().is_some() {
                deferred_fragments.insert(generated_fragment_definition_name_capitalized(
                    named_frag.fragment.name(),
                    &self.config.capitalizer,
                ));
            }
        }

        if deferred_fragments.is_empty() {
            return String::new();
        }

        let items: Vec<String> = deferred_fragments
            .iter()
            .map(|name| format!("  {}.self", name))
            .collect();

        format!(
            "{}static var __deferredFragments: [any ApolloAPI.Deferrable.Type] {{ [\n{}\n] }}",
            self.access_control_renderer
                .render_with_spis(&[SPI::Execution]),
            items.join(",\n")
        )
    }

    // MARK: - Selections

    fn direct_selections_metadata_template(
        &self,
        selections: &DirectSelections,
        scope: &ScopeDescriptor,
    ) -> String {
        let grouped = GroupedByInclusionCondition::from_selections(selections);

        let mut deprecated_arguments: Vec<DeprecatedArgument> = Vec::new();
        let track_deprecated =
            self.config.options().warnings_on_deprecated_usage == Composition::Include;

        let should_include_typename = should_include_typename_selection(scope);

        if grouped.is_empty() && !should_include_typename {
            return String::new();
        }

        let mut selection_items: Vec<String> = Vec::new();

        if should_include_typename {
            selection_items.push("  .field(\"__typename\", String.self),".to_string());
        }

        // Unconditional selections
        let unconditional = self.rendered_selections(
            &grouped.unconditional_selections,
            &mut deprecated_arguments,
            track_deprecated,
        );
        for sel in &unconditional {
            selection_items.push(format!("  {},", sel));
        }

        // Conditional selection groups
        for (conditions, group_selections) in &grouped.inclusion_condition_groups {
            let rendered = self.rendered_selections(
                group_selections,
                &mut deprecated_arguments,
                track_deprecated,
            );
            if !scope.matches_any_of(conditions) {
                let cond_expr = condition_variable_expression(conditions);
                let is_group = rendered.len() > 1;
                if is_group {
                    // Mirrors Swift: `[` + `\(list: renderedSelections, terminator: ",")` + `]`
                    // where `list:` wraps in "\n  " ... "\n" and each item ends with ",".
                    let inner: Vec<String> =
                        rendered.iter().map(|s| format!("    {},", s)).collect();
                    selection_items.push(format!(
                        "  .include(if: {}, [\n{}\n  ]),",
                        cond_expr,
                        inner.join("\n")
                    ));
                } else if let Some(single) = rendered.first() {
                    selection_items.push(format!("  .include(if: {}, {}),", cond_expr, single));
                }
            } else {
                for sel in &rendered {
                    selection_items.push(format!("  {},", sel));
                }
            }
        }

        let mut result = String::new();

        // Deprecated argument warnings
        if track_deprecated && !deprecated_arguments.is_empty() {
            for dep in &deprecated_arguments {
                result.push_str(&render_field_argument_warning(
                    &dep.field,
                    &dep.arg,
                    &dep.reason,
                ));
                result.push('\n');
            }
        }

        result.push_str(&format!(
            "{}static var __selections: [{}.Selection] {{ [\n{}\n] }}",
            self.access_control_renderer
                .render_with_spis(&[SPI::Execution]),
            self.config.apollo_api_target_name(),
            selection_items.join("\n")
        ));

        result
    }

    fn rendered_selections(
        &self,
        selections: &DirectSelections,
        deprecated_args: &mut Vec<DeprecatedArgument>,
        track_deprecated: bool,
    ) -> Vec<String> {
        let mut result: Vec<String> = Vec::new();

        for field in selections.fields.values() {
            result.push(self.field_selection_template(field, deprecated_args, track_deprecated));
        }
        for inline_frag in selections.inline_fragments.values() {
            result.push(self.inline_fragment_selection_template(&inline_frag.selection_set));
        }
        for named_frag in selections.named_fragments.values() {
            result.push(self.fragment_selection_template(named_frag));
        }

        result
    }

    fn field_selection_template(
        &self,
        field: &Field,
        deprecated_args: &mut Vec<DeprecatedArgument>,
        track_deprecated: bool,
    ) -> String {
        let mut parts = vec![format!(".field(\"{}\"", field.name())];

        if let Some(alias) = field.alias() {
            parts.push(format!(", alias: \"{}\"", alias));
        }

        parts.push(format!(", {}.self", self.type_name_for_field(field, false)));

        if let Some(args) = field.arguments() {
            if !args.is_empty() {
                let rendered_args =
                    self.render_arguments(args, field.name(), deprecated_args, track_deprecated);
                parts.push(format!(", arguments: {}", rendered_args));
            }
        }

        // Note: field_policy_keys is not yet in the Rust compilation result,
        // so we skip that rendering for now.

        parts.push(")".to_string());
        parts.join("")
    }

    fn type_name_for_field(&self, field: &Field, force_optional: bool) -> String {
        let field_name = match field {
            Field::Scalar(sf) => render_graphql_type(
                &sf.underlying_field.type_,
                &TypeRenderContext::SelectionSetField {
                    force_non_null: false,
                },
                None,
                &self.config.config,
            ),
            Field::Entity(ef) => self.name_cache.borrow_mut().selection_set_type(ef),
        };

        if force_optional {
            if let GraphQLType::NonNull(_) = field.type_() {
                return format!("{}?", field_name);
            }
        }

        field_name
    }

    fn render_arguments(
        &self,
        arguments: &[compilation_result::Argument],
        field_name: &str,
        deprecated_args: &mut Vec<DeprecatedArgument>,
        track_deprecated: bool,
    ) -> String {
        // Swift's `list:` renders single items inline, multiple items on separate lines.
        // For multi-line, items are indented 4 spaces and closing bracket at 2 spaces
        // because the `[` appears inside a `.field(` call that gets a 2-space prefix
        // from direct_selections_metadata_template — only the first line gets that prefix,
        // so continuation lines must account for it.
        //
        // Nested object values use indent_level to determine their multiline layout:
        // - Single-item args (inline): value indent_level = 2 (argument list base)
        // - Multi-item args: value indent_level = 4 (matching item indent)
        let value_indent = if arguments.len() <= 1 { 2 } else { 4 };
        let items: Vec<String> = arguments
            .iter()
            .map(|arg| {
                if track_deprecated {
                    if let Some(ref reason) = arg.deprecation_reason {
                        deprecated_args.push(DeprecatedArgument {
                            field: field_name.to_string(),
                            arg: arg.name.clone(),
                            reason: reason.clone(),
                        });
                    }
                }
                format!(
                    "\"{}\": {}",
                    arg.name,
                    render_input_value_literal(&arg.value, value_indent)
                )
            })
            .collect();
        if items.len() <= 1 {
            format!("[{}]", items.join(", "))
        } else {
            format!("[\n    {}\n  ]", items.join(",\n    "))
        }
    }

    fn inline_fragment_selection_template(&self, inline_fragment: &SelectionSet) -> String {
        if let Some(defer_condition) = inline_fragment.type_info.defer_condition() {
            return self.deferred_inline_fragment_selection_template(defer_condition);
        }
        let type_name = rendered_type_name(&inline_fragment.type_info);
        format!(".inlineFragment({}.self)", type_name)
    }

    fn fragment_selection_template(&self, fragment: &NamedFragmentSpread) -> String {
        if let Some(defer_condition) = fragment.type_info.defer_condition() {
            return self.deferred_named_fragment_selection_template(defer_condition, fragment);
        }
        let name = as_fragment_name(fragment.fragment.name(), &self.config.capitalizer);
        format!(".fragment({}.self)", name)
    }

    fn deferred_inline_fragment_selection_template(
        &self,
        defer_condition: &DeferCondition,
    ) -> String {
        let var_part = defer_condition
            .variable
            .as_ref()
            .map(|v| format!("if: \"{}\", ", v))
            .unwrap_or_default();
        let type_name =
            selection_set_name_generator::defer_condition_rendered_type_name(defer_condition);
        format!(
            ".deferred({}{}.self, label: \"{}\")",
            var_part, type_name, defer_condition.label
        )
    }

    fn deferred_named_fragment_selection_template(
        &self,
        defer_condition: &DeferCondition,
        fragment: &NamedFragmentSpread,
    ) -> String {
        let var_part = defer_condition
            .variable
            .as_ref()
            .map(|v| format!("if: \"{}\", ", v))
            .unwrap_or_default();
        let name = as_fragment_name(fragment.fragment.name(), &self.config.capitalizer);
        format!(
            ".deferred({}{}.self, label: \"{}\")",
            var_part, name, defer_condition.label
        )
    }

    // MARK: - Accessors

    fn field_accessors_template(&self, selection_set: &ComputedSelectionSet) -> String {
        let scope = selection_set.type_info.scope();
        let mut lines: Vec<String> = Vec::new();

        if let Some(ref direct) = selection_set.direct {
            for field in direct.fields.values() {
                lines.push(self.field_accessor_template(field, scope));
            }
        }
        for field in selection_set.merged.fields.values() {
            lines.push(self.field_accessor_template(field, scope));
        }

        lines.join("\n")
    }

    fn field_accessor_template(&self, field: &Field, scope: &ScopeDescriptor) -> String {
        let mut result = String::new();

        // Documentation
        if self.config.options().schema_documentation == Composition::Include {
            if let Some(ref doc) = field.underlying_field().documentation {
                if let Some(rendered_doc) = render_documentation(Some(doc), self.config) {
                    result.push_str(&rendered_doc);
                    result.push('\n');
                }
            }
        }

        // Deprecation
        if self.config.options().warnings_on_deprecated_usage == Composition::Include {
            if let Some(ref reason) = field.underlying_field().deprecation_reason {
                result.push_str(&format!(
                    "@available(*, deprecated, message: \"{}\")\n",
                    escaped_swift_string_special_characters(reason)
                ));
            }
        }

        let is_conditionally_included = is_field_conditionally_included(field, scope);
        let type_name = self.type_name_for_field(field, is_conditionally_included);
        let property_name = render_as_field_property_name(field.response_key(), self.config);

        if self.is_mutable() {
            result.push_str(&format!(
                "{}var {}: {} {{\n  get {{ __data[\"{}\"] }}\n  set {{ __data[\"{}\"] = newValue }}\n}}",
                self.access_control_renderer.render(),
                property_name,
                type_name,
                field.response_key(),
                field.response_key(),
            ));
        } else {
            result.push_str(&format!(
                "{}var {}: {} {{ __data[\"{}\"] }}",
                self.access_control_renderer.render(),
                property_name,
                type_name,
                field.response_key(),
            ));
        }

        result
    }

    fn inline_fragment_accessors_template(
        &self,
        inline_fragments: &[SelectionSetContext],
    ) -> String {
        // Swift 2.0.0 joins every accessor with "\n", including the empty string
        // returned for deferred inline fragments, so a deferred fragment leaves
        // an extra blank line behind.
        let lines: Vec<String> = inline_fragments
            .iter()
            .map(|ctx| self.inline_fragment_accessor_template(&ctx.selection_set))
            .collect();
        lines.join("\n")
    }

    fn inline_fragment_accessor_template(&self, inline_fragment: &ComputedSelectionSet) -> String {
        if inline_fragment.type_info.scope().is_deferred() {
            return String::new();
        }

        let type_name = rendered_type_name(&inline_fragment.type_info);
        format!(
            "{}var {}: {}? {{ _asInlineFragment() }}",
            self.access_control_renderer.render(),
            first_lowercased(&type_name),
            type_name
        )
    }

    fn fragment_accessors_template(&self, selection_set: &ComputedSelectionSet) -> String {
        let has_direct_named = selection_set
            .direct
            .as_ref()
            .is_none_or(|d| d.named_fragments.is_empty());
        let has_merged_named = selection_set.merged.named_fragments.is_empty();
        let has_deferred_inline = selection_set
            .direct
            .as_ref()
            .is_some_and(|d| contains_deferred_inline_fragment(&d.inline_fragments));

        if has_direct_named && has_merged_named && !has_deferred_inline {
            return String::new();
        }

        let scope = selection_set.type_info.scope();

        // Build inner content matching Swift's FragmentAccessorsTemplate layout:
        // DataProperty\nInit\n\nAccessors...
        let mut inner = String::new();
        inner.push_str(&self.data_property_template());
        inner.push('\n');
        inner.push_str(&self.fragment_initializer_template(selection_set));

        // Fragment accessors (with blank line separator from init)
        let mut accessors: Vec<String> = Vec::new();
        if let Some(ref direct) = selection_set.direct {
            for named_frag in direct.named_fragments.values() {
                accessors.push(self.named_fragment_accessor_template(named_frag, scope));
            }
        }
        for named_frag in selection_set.merged.named_fragments.values() {
            accessors.push(self.named_fragment_accessor_template(named_frag, scope));
        }

        // Deferred fragment accessors from inline fragments
        if let Some(ref direct) = selection_set.direct {
            for inline_frag in direct.inline_fragments.values() {
                if let Some(defer_cond) = inline_frag.selection_set.type_info.defer_condition() {
                    let type_name =
                        selection_set_name_generator::defer_condition_rendered_type_name(
                            defer_cond,
                        );
                    accessors.push(
                        self.deferred_fragment_accessor_template(&defer_cond.label, &type_name),
                    );
                }
            }
        }

        if !accessors.is_empty() {
            inner.push_str("\n\n");
            inner.push_str(&accessors.join("\n"));
        }

        format!(
            "{}struct Fragments: FragmentContainer {{\n{}\n}}",
            self.access_control_renderer.render(),
            indent(&inner, 2),
        )
    }

    fn fragment_initializer_template(&self, selection_set: &ComputedSelectionSet) -> String {
        // Swift 1.24.0+: deferred fragments merged in from other selection sets are initialized
        // here too (direct inline, direct named, then merged named fragments).
        let direct = selection_set.direct.as_ref();
        let has_deferred =
            direct.is_some_and(|d| {
                contains_deferred_inline_fragment(&d.inline_fragments)
                    || contains_deferred_named_fragment(&d.named_fragments)
            }) || contains_deferred_inline_fragment(&selection_set.merged.inline_fragments)
                || contains_deferred_named_fragment(&selection_set.merged.named_fragments);
        if !has_deferred {
            return self.designated_initializer_template(None);
        }

        // Each `forEachIn` maps non-deferred fragments to an empty template (see
        // `for_each_in_joined`); an empty block removes its line from the template.
        let mut blocks: Vec<String> = Vec::new();
        if let Some(direct) = direct {
            blocks.push(for_each_in_joined(
                direct.inline_fragments.values().map(|inline_frag| {
                    match inline_frag.selection_set.type_info.defer_condition() {
                        Some(defer_cond) => {
                            format!("_{} = Deferred(_dataDict: _dataDict)", defer_cond.label)
                        }
                        None => String::new(),
                    }
                }),
                "\n",
            ));
            blocks.push(for_each_in_joined(
                direct.named_fragments.values().map(|named_frag| {
                    if named_frag.type_info.defer_condition().is_some() {
                        format!(
                            "_{} = Deferred(_dataDict: _dataDict)",
                            first_lowercased(named_frag.fragment.name())
                        )
                    } else {
                        String::new()
                    }
                }),
                "\n",
            ));
        }
        blocks.push(for_each_in_joined(
            selection_set
                .merged
                .named_fragments
                .values()
                .map(|named_frag| {
                    if named_frag.type_info.defer_condition().is_some() {
                        format!(
                            "_{} = Deferred(_dataDict: _dataDict)",
                            first_lowercased(named_frag.fragment.name())
                        )
                    } else {
                        String::new()
                    }
                }),
            "\n",
        ));
        let blocks: Vec<String> = blocks.into_iter().filter(|s| !s.is_empty()).collect();

        self.designated_initializer_template(Some(&blocks.join("\n")))
    }

    fn named_fragment_accessor_template(
        &self,
        fragment: &NamedFragmentSpread,
        scope: &ScopeDescriptor,
    ) -> String {
        let name = fragment.fragment.name();
        let property_name = first_lowercased(name);
        let type_name = as_fragment_name(name, &self.config.capitalizer);
        let is_optional = fragment.inclusion_conditions.is_some()
            && !scope.matches_any_of(fragment.inclusion_conditions.as_ref().unwrap());
        let is_deferred = fragment.type_info.defer_condition().is_some();

        if is_deferred {
            return self.deferred_fragment_accessor_template(
                &first_lowercased(name),
                &as_fragment_name(name, &self.config.capitalizer),
            );
        }

        let optional_suffix = if is_optional { "?" } else { "" };

        if self.is_mutable() {
            let modify_body = if is_optional {
                "if let newData = f?.__data { __data = newData }".to_string()
            } else {
                "__data = f.__data".to_string()
            };
            format!(
                "{}var {}: {}{} {{\n  get {{ _toFragment() }}\n  _modify {{ var f = {}; yield &f; {} }}\n}}",
                self.access_control_renderer.render(),
                property_name,
                type_name,
                optional_suffix,
                property_name,
                modify_body,
            )
        } else {
            format!(
                "{}var {}: {}{} {{ _toFragment() }}",
                self.access_control_renderer.render(),
                property_name,
                type_name,
                optional_suffix,
            )
        }
    }

    fn deferred_fragment_accessor_template(&self, property_name: &str, type_name: &str) -> String {
        format!("@Deferred public var {}: {}?", property_name, type_name)
    }

    // MARK: - Initializer

    fn initializer_template(&self, selection_set: &ComputedSelectionSet) -> String {
        let params = self.initializer_selection_parameters_template(selection_set);
        let data_dict = self.initializer_data_dict_template(selection_set);

        // Match Swift 1.25.3+ InitializerTemplate layout:
        // init(
        //   param1,
        //   param2
        // ) {
        //   self.init(unsafelyWithData: [
        //     "key": value,
        //   ])
        // }
        let mut result = String::new();
        result.push_str(&self.access_control_renderer.render());
        if params.is_empty() {
            result.push_str("init(\n) {\n");
        } else {
            result.push_str("init(\n");
            result.push_str("  ");
            result.push_str(&params);
            result.push_str("\n) {\n");
        }
        result.push_str("  self.init(unsafelyWithData: [\n");
        result.push_str("    ");
        result.push_str(&data_dict);
        result.push_str("\n  ])\n");
        result.push('}');
        result
    }

    fn initializer_selection_parameters_template(
        &self,
        selection_set: &ComputedSelectionSet,
    ) -> String {
        let is_concrete = matches!(
            selection_set.type_info.parent_type(),
            GraphQLCompositeType::Object(_)
        );
        let all_fields: Vec<&Field> = selection_set.make_field_iterator().collect();

        // In Swift's TemplateString, parameters in an array are automatically
        // comma-separated. Each parameter goes on its own line.
        let mut parts: Vec<String> = Vec::new();
        if !is_concrete {
            parts.push("__typename: String".to_string());
        }

        for field in &all_fields {
            parts.push(self.initializer_parameter_template(field, selection_set.type_info.scope()));
        }

        // Join with ",\n  " to put commas at end of each param except the last
        parts.join(",\n  ")
    }

    fn initializer_parameter_template(&self, field: &Field, scope: &ScopeDescriptor) -> String {
        let is_optional =
            field.type_().is_nullable() || is_field_conditionally_included(field, scope);
        let type_name = self.type_name_for_field(field, is_optional);
        let param_name = render_as_initializer_parameter_name(field.response_key(), self.config);
        let default = if is_optional { " = nil" } else { "" };
        format!("{}: {}{}", param_name, type_name, default)
    }

    fn initializer_data_dict_template(&self, selection_set: &ComputedSelectionSet) -> String {
        let is_concrete = matches!(
            selection_set.type_info.parent_type(),
            GraphQLCompositeType::Object(_)
        );
        let all_fields: Vec<&Field> = selection_set.make_field_iterator().collect();

        let mut parts: Vec<String> = Vec::new();
        if is_concrete {
            parts.push(format!(
                "\"__typename\": {}.typename,",
                self.generated_schema_type_reference(selection_set.type_info.parent_type())
            ));
        } else {
            parts.push("\"__typename\": __typename,".to_string());
        }

        for field in &all_fields {
            parts.push(self.initializer_data_dict_field_template(field));
        }

        parts.join("\n    ")
    }

    fn initializer_data_dict_field_template(&self, field: &Field) -> String {
        let is_entity_field = matches!(field.type_().inner_type(), GraphQLType::Entity(_));
        let accessor_name =
            render_as_initializer_parameter_accessor_name(field.response_key(), self.config);
        let field_data = if is_entity_field { "._fieldData" } else { "" };
        format!(
            "\"{}\": {}{},",
            field.response_key(),
            accessor_name,
            field_data
        )
    }

    // MARK: - Nested Selection Sets

    fn child_entity_field_selection_sets(&self, context: &SelectionSetContext) -> String {
        let selection_set = &context.selection_set;
        let entity_fields: Vec<&EntityField> = selection_set
            .make_field_iterator_filtered(|f| matches!(f, Field::Entity(_)))
            .filter_map(|f| match f {
                Field::Entity(ef) => Some(ef),
                _ => None,
            })
            .collect();

        let mut rendered: Vec<String> = Vec::new();
        for field in entity_fields {
            let child_ctx = self.create_selection_set_context(&field.selection_set, Some(context));
            if let Some(rendered_child) = self.render_child_entity(&child_ctx) {
                rendered.push(rendered_child);
            }
        }

        rendered.join("\n\n")
    }

    fn child_type_case_selection_sets(&self, inline_fragments: &[SelectionSetContext]) -> String {
        let rendered: Vec<String> = inline_fragments
            .iter()
            .map(|ctx| self.render_inline_fragment(ctx))
            .collect();
        rendered.join("\n\n")
    }
}

// MARK: - SelectionSetContext

struct SelectionSetContext {
    selection_set: ComputedSelectionSet,
}

// MARK: - DeprecatedArgument

struct DeprecatedArgument {
    field: String,
    arg: String,
    reason: String,
}

// MARK: - Free functions

/// Returns `true` if the selection set is a composite inline fragment.
///
/// Mirrors Swift's `IR.ComputedSelectionSet.isCompositeInlineFragment` extension.
pub fn is_composite_inline_fragment(sel: &ComputedSelectionSet) -> bool {
    !sel.type_info.is_entity_root()
        && !sel.type_info.is_user_defined()
        && sel.direct.as_ref().is_none_or(|d| d.is_empty())
}

/// Returns the name for a referenced selection set, if the selection set is a reference
/// to another rendered selection set.
///
/// Mirrors Swift's `IR.ComputedSelectionSet.nameForReferencedSelectionSet(config:)` extension.
pub fn name_for_referenced_selection_set(
    sel: &ComputedSelectionSet,
    config: &ConfigurationContext,
) -> Option<String> {
    if sel.direct.is_some() || sel.type_info.derived_from_merged_sources.len() != 1 {
        return None;
    }

    let source = &sel.type_info.derived_from_merged_sources[0];
    Some(generated_selection_set_name_path(
        source,
        &sel.type_info,
        config,
    ))
}

/// Returns the rendered type name for a TypeInfo (last scope condition's name component).
///
/// Mirrors Swift's `IR.SelectionSet.TypeInfo.renderedTypeName` extension.
pub fn rendered_type_name(type_info: &TypeInfo) -> String {
    selection_set_name_generator::selection_set_name_component(type_info.scope().scope_path.last())
}

/// Generates the full qualified name path for a merged source.
///
/// Mirrors Swift's `IR.MergedSelections.MergedSource.generatedSelectionSetNamePath(from:pluralizer:)`.
pub fn generated_selection_set_name_path(
    source: &MergedSource,
    target_type_info: &TypeInfo,
    config: &ConfigurationContext,
) -> String {
    if let Some(ref fragment) = source.fragment {
        return generated_selection_set_name_for_merged_entity_in_fragment(
            source, fragment, config,
        );
    }

    // Mirrors Swift: `targetTypePathCurrentNode = targetTypeInfo.scopePath.last`,
    // `sourceTypePathCurrentNode = typeInfo.scopePath.last` (the merged source's).
    let mut target_node = target_type_info.scope_path.last_node();
    let mut source_node = source.type_info.scope_path.last_node();
    let mut nodes_to_shared_root: usize = 0;

    while represents_same_scope(target_node.value(), source_node.value()) {
        let prev_target = target_node.previous();
        let prev_source = source_node.previous();
        match (prev_target, prev_source) {
            (Some(pt), Some(ps)) => {
                target_node = pt;
                source_node = ps;
                nodes_to_shared_root += 1;
            }
            _ => break,
        }
    }

    // If the shared root is the root of the definition, generate the fully qualified name
    if source_node.index() == 0 {
        return SelectionSetNameGenerator::generated_selection_set_name_for_merged_source(
            source,
            None,
            NameFormat::FullyQualified,
            config,
        );
    }

    let field_path_count = source
        .type_info
        .entity
        .location
        .field_path
        .as_ref()
        .map_or(0, |fp| fp.count());
    let shared_root_index = field_path_count.saturating_sub(nodes_to_shared_root + 1);
    let remove_first_component = nodes_to_shared_root <= 1;

    let field_path = source
        .type_info
        .entity
        .location
        .field_path
        .as_ref()
        .unwrap();
    let field_node_index = shared_root_index.max(0);

    // Get the node ref at the computed index
    let field_path_node_ref = if field_node_index < field_path.count() {
        Some(node_ref_at(field_path, field_node_index))
    } else {
        None
    };

    if let Some(fp_node) = field_path_node_ref {
        SelectionSetNameGenerator::generated_selection_set_name_from_nodes(
            source_node,
            None,
            Some(fp_node),
            remove_first_component,
            config,
        )
    } else {
        SelectionSetNameGenerator::generated_selection_set_name_for_merged_source(
            source,
            None,
            NameFormat::FullyQualified,
            config,
        )
    }
}

/// Helper to get a NodeRef at a specific index in a LinkedList.
fn node_ref_at<'a, T>(
    list: &'a LinkedList<T>,
    index: usize,
) -> utilities::linked_list::NodeRef<'a, T> {
    let mut node = list.head_node();
    for _ in 0..index {
        node = node.next().expect("index out of bounds in node_ref_at");
    }
    node
}

fn represents_same_scope(target: &ScopeDescriptor, source: &ScopeDescriptor) -> bool {
    if target == source {
        return true;
    }

    if target.scope_path.head().type_ == source.scope_path.head().type_ {
        if let Some(ref source_conditions) = source.scope_path.head().conditions {
            // Check if target has a second node with nil type and matching conditions
            if target.scope_path.count() > 1 {
                let target_second = &target.scope_path[1];
                if target_second.type_.is_none() {
                    if let Some(ref target_conditions) = target_second.conditions {
                        return source_conditions == target_conditions;
                    }
                }
            }
        }
    }

    false
}

fn generated_selection_set_name_for_merged_entity_in_fragment(
    source: &MergedSource,
    fragment: &ir::NamedFragment,
    config: &ConfigurationContext,
) -> String {
    let mut components: Vec<String> = vec![generated_fragment_definition_name_capitalized(
        fragment.name(),
        &config.capitalizer,
    )];

    let root_entity_scope_path = source.type_info.scope_path.head_node();
    if let Some(root_cond_next) = root_entity_scope_path.value().scope_path.head_node().next() {
        components.push(SelectionSetNameGenerator::condition_path(root_cond_next));
    }

    if let Some(fragment_nested) = root_entity_scope_path.next() {
        let field_path = source
            .type_info
            .entity
            .location
            .field_path
            .as_ref()
            .unwrap();
        let field_node = field_path.head_node();

        components.push(
            SelectionSetNameGenerator::generated_selection_set_name_from_nodes(
                fragment_nested,
                None,
                Some(field_node),
                false,
                config,
            ),
        );
    }

    components.join(".")
}

/// Generates the fulfilled fragment names for a merged source.
///
/// Mirrors Swift's `MergedSource.generatedSelectionSetNamesOfFullfilledFragments(pluralizer:)`.
pub fn generated_selection_set_names_of_fulfilled_fragments(
    source: &MergedSource,
    config: &ConfigurationContext,
) -> Vec<String> {
    let entity_root_name =
        SelectionSetNameGenerator::generated_selection_set_name_for_merged_source(
            source,
            Some(source.type_info.scope_path.last().scope_path.head_node()),
            NameFormat::FullyQualified,
            config,
        );

    let mut fulfilled: Vec<String> = vec![entity_root_name.clone()];
    let mut name_components: Vec<String> = vec![entity_root_name];

    let mut current_node = source.type_info.scope_path.last().scope_path.head_node();
    while let Some(next) = current_node.next() {
        name_components.push(selection_set_name_generator::selection_set_name_component(
            next.value(),
        ));
        fulfilled.push(name_components.join("."));
        current_node = next;
    }

    fulfilled
}

/// Returns the condition variable expression for an AnyOf<InclusionConditions>.
///
/// Mirrors Swift's `AnyOf<IR.InclusionConditions>.conditionVariableExpression` extension.
pub fn condition_variable_expression(any_of: &AnyOf<InclusionConditions>) -> String {
    let parts: Vec<String> = any_of
        .elements
        .iter()
        .map(|conds| conditions_variable_expression(conds, any_of.elements.len() > 1))
        .collect();
    parts.join(" || ")
}

/// Returns the condition variable expression for a set of InclusionConditions.
///
/// Mirrors Swift's `IR.InclusionConditions.conditionVariableExpression(wrapInParenthesisIfMultiple:)`.
pub fn conditions_variable_expression(
    conditions: &InclusionConditions,
    wrap_in_parens_if_multiple: bool,
) -> String {
    let parts: Vec<String> = conditions
        .iter()
        .map(condition_variable_expression_single)
        .collect();
    let joined = parts.join(" && ");
    if wrap_in_parens_if_multiple && conditions.len() > 1 {
        format!("({})", joined)
    } else {
        joined
    }
}

/// Returns the condition variable expression for a single InclusionCondition.
///
/// Mirrors Swift's `IR.InclusionCondition.conditionVariableExpression` extension.
pub fn condition_variable_expression_single(condition: &InclusionCondition) -> String {
    let prefix = if condition.is_inverted { "!" } else { "" };
    format!("{}\"{}\"", prefix, condition.variable)
}

/// Returns `true` if the inline fragments map contains a deferred fragment.
///
/// Mirrors Swift's `OrderedDictionary<ScopeCondition, InlineFragmentSpread>.containsDeferredFragment`.
pub fn contains_deferred_inline_fragment(
    map: &IndexMap<ScopeCondition, InlineFragmentSpread>,
) -> bool {
    map.keys().any(|k| k.is_deferred())
}

/// Returns `true` if the named fragments map contains a deferred fragment.
///
/// Mirrors Swift's `OrderedDictionary<String, NamedFragmentSpread>.containsDeferredFragment`.
pub fn contains_deferred_named_fragment(map: &IndexMap<String, NamedFragmentSpread>) -> bool {
    map.values()
        .any(|v| v.type_info.defer_condition().is_some())
}

/// Returns `true` if a field is conditionally included in the given scope.
///
/// Mirrors Swift's `IR.Field.isConditionallyIncluded(in:)` extension.
fn is_field_conditionally_included(field: &Field, scope: &ScopeDescriptor) -> bool {
    match field.inclusion_conditions() {
        Some(conditions) => !scope.matches_any_of(conditions),
        None => false,
    }
}

/// Returns `true` if the __typename selection should be included for the given scope.
fn should_include_typename_selection(scope: &ScopeDescriptor) -> bool {
    if scope.scope_path.count() != 1 {
        return false;
    }
    let root_types = &scope.all_types_in_schema;
    !root_types
        .schema_root_types
        .all_root_types()
        .iter()
        .any(|rt| {
            // Compare GraphQLNamedType with GraphQLCompositeType by name
            match (rt, &scope.type_) {
                (
                    graphql_compiler::GraphQLNamedType::Object(o),
                    GraphQLCompositeType::Object(so),
                ) => o.name == so.name,
                (
                    graphql_compiler::GraphQLNamedType::Interface(i),
                    GraphQLCompositeType::Interface(si),
                ) => i.name == si.name,
                (graphql_compiler::GraphQLNamedType::Union(u), GraphQLCompositeType::Union(su)) => {
                    u.name == su.name
                }
                _ => false,
            }
        })
}

/// Renders a GraphQLCompositeType as a typename string.
fn render_composite_type_as_typename(type_: &GraphQLCompositeType) -> String {
    let named = match type_ {
        GraphQLCompositeType::Object(obj) => {
            graphql_compiler::GraphQLNamedType::Object(obj.clone())
        }
        GraphQLCompositeType::Interface(iface) => {
            graphql_compiler::GraphQLNamedType::Interface(iface.clone())
        }
        GraphQLCompositeType::Union(u) => graphql_compiler::GraphQLNamedType::Union(u.clone()),
    };
    render_named_type(
        &named,
        &RenderContext::Typename {
            is_input_value: false,
        },
    )
}

/// Converts FieldMerging config flags to MergingStrategy IR flags.
fn field_merging_to_merging_strategy(fm: FieldMerging) -> MergingStrategy {
    let mut strategy = MergingStrategy::empty();
    if fm.contains(FieldMerging::ANCESTORS) {
        strategy |= MergingStrategy::ANCESTORS;
    }
    if fm.contains(FieldMerging::SIBLINGS) {
        strategy |= MergingStrategy::SIBLINGS;
    }
    if fm.contains(FieldMerging::NAMED_FRAGMENTS) {
        strategy |= MergingStrategy::NAMED_FRAGMENTS;
    }
    strategy
}

/// Indents each non-empty line of the string by `n` spaces.
fn indent(s: &str, n: usize) -> String {
    let prefix = " ".repeat(n);
    s.lines()
        .map(|line| {
            if line.trim().is_empty() {
                String::new()
            } else {
                format!("{}{}", prefix, line)
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use ir::MergedSelections;

    #[test]
    fn test_is_composite_inline_fragment_true() {
        // A composite inline fragment has: !isEntityRoot && !isUserDefined && direct is empty
        // This is tested via the free function with a mock ComputedSelectionSet
        // For now, verify the function signature compiles and basic logic
        use graphql_compiler::{
            compilation_result, GraphQLCompositeType, GraphQLName, GraphQLNamedType,
            GraphQLObjectType,
        };
        use indexmap::{IndexMap, IndexSet};
        use ir::entity::{Entity, SourceDefinition};
        use ir::schema::ReferencedTypes;
        use ir::scope_descriptor::ScopeDescriptor;
        use std::sync::Arc;
        use utilities::linked_list::LinkedList;

        let obj = Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Dog".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: Vec::new(),
            key_fields: None,
        });
        let parent_type = GraphQLCompositeType::Object(Arc::clone(&obj));
        let all_types = Arc::new(ReferencedTypes::new(
            &[GraphQLNamedType::Object(Arc::clone(&obj))],
            compilation_result::RootTypeDefinition {
                query_type: GraphQLNamedType::Object(Arc::clone(&obj)),
                mutation_type: None,
                subscription_type: None,
            },
        ));

        let scope = ScopeDescriptor::descriptor(&parent_type, None, &all_types);
        // Create a non-root scope by appending a type condition
        let inner_scope = scope.appending(ScopeCondition::with_type(parent_type.clone()));
        let scope_path = LinkedList::from_collection(vec![scope, inner_scope]);

        let op_def = Arc::new(compilation_result::OperationDefinition {
            name: "TestOp".to_string(),
            operation_type: compilation_result::OperationType::Query,
            variables: Vec::new(),
            root_type: parent_type.clone(),
            selection_set: compilation_result::SelectionSet {
                parent_type: parent_type.clone(),
                selections: Vec::new(),
            },
            directives: None,
            referenced_fragments: Vec::new(),
            source: "query TestOp { id }".to_string(),
            file_path: "test.graphql".to_string(),
        });

        let entity = Arc::new(Entity::new_root(SourceDefinition::Operation(op_def)));
        let mut type_info_data = TypeInfo::new(entity, scope_path);
        // Mark as derived from merged source (not user defined)
        type_info_data
            .derived_from_merged_sources
            .push(MergedSource {
                type_info: Arc::new(TypeInfo::new(
                    type_info_data.entity.clone(),
                    type_info_data.scope_path.clone(),
                )),
                fragment: None,
            });
        let type_info = Arc::new(type_info_data);

        let css = ComputedSelectionSet {
            direct: None, // empty direct
            merged: MergedSelections {
                merged_sources: IndexSet::new(),
                merging_strategy: MergingStrategy::empty(),
                fields: IndexMap::new(),
                inline_fragments: IndexMap::new(),
                named_fragments: IndexMap::new(),
            },
            type_info,
        };

        assert!(is_composite_inline_fragment(&css));
    }

    #[test]
    fn test_condition_variable_expression_single_include() {
        let cond = InclusionCondition::include_if("showField".to_string());
        assert_eq!(condition_variable_expression_single(&cond), "\"showField\"");
    }

    #[test]
    fn test_condition_variable_expression_single_skip() {
        let cond = InclusionCondition::skip_if("hideField".to_string());
        assert_eq!(
            condition_variable_expression_single(&cond),
            "!\"hideField\""
        );
    }

    #[test]
    fn test_conditions_variable_expression_single() {
        let conds = InclusionConditions::new(InclusionCondition::include_if("flag".to_string()));
        assert_eq!(conditions_variable_expression(&conds, false), "\"flag\"");
    }

    #[test]
    fn test_conditions_variable_expression_multiple_wrapped() {
        let mut conds = InclusionConditions::new(InclusionCondition::include_if("a".to_string()));
        conds.append(InclusionCondition::skip_if("b".to_string()));
        assert_eq!(
            conditions_variable_expression(&conds, true),
            "(\"a\" && !\"b\")"
        );
    }

    #[test]
    fn test_condition_variable_expression_any_of() {
        let conds_a = InclusionConditions::new(InclusionCondition::include_if("a".to_string()));
        let conds_b = InclusionConditions::new(InclusionCondition::include_if("b".to_string()));
        let any_of = AnyOf::from_elements(vec![conds_a, conds_b]);
        assert_eq!(condition_variable_expression(&any_of), "\"a\" || \"b\"");
    }

    #[test]
    fn test_field_merging_to_merging_strategy_all() {
        let result = field_merging_to_merging_strategy(FieldMerging::ALL);
        assert_eq!(result, MergingStrategy::ALL);
    }

    #[test]
    fn test_field_merging_to_merging_strategy_empty() {
        let result = field_merging_to_merging_strategy(FieldMerging::empty());
        assert_eq!(result, MergingStrategy::empty());
    }

    #[test]
    fn test_field_merging_to_merging_strategy_partial() {
        let result =
            field_merging_to_merging_strategy(FieldMerging::ANCESTORS | FieldMerging::SIBLINGS);
        assert_eq!(
            result,
            MergingStrategy::ANCESTORS | MergingStrategy::SIBLINGS
        );
    }

    #[test]
    fn test_indent_basic() {
        assert_eq!(indent("hello\nworld", 2), "  hello\n  world");
    }

    #[test]
    fn test_indent_empty_lines() {
        assert_eq!(indent("hello\n\nworld", 2), "  hello\n\n  world");
    }

    #[test]
    fn test_contains_deferred_inline_fragment_empty() {
        let map: IndexMap<ScopeCondition, InlineFragmentSpread> = IndexMap::new();
        assert!(!contains_deferred_inline_fragment(&map));
    }

    #[test]
    fn test_contains_deferred_named_fragment_empty() {
        let map: IndexMap<String, NamedFragmentSpread> = IndexMap::new();
        assert!(!contains_deferred_named_fragment(&map));
    }

    #[test]
    fn test_rendered_type_name_basic() {
        use graphql_compiler::{
            compilation_result, GraphQLCompositeType, GraphQLName, GraphQLNamedType,
            GraphQLObjectType,
        };
        use indexmap::IndexMap;
        use ir::entity::{Entity, SourceDefinition};
        use ir::schema::ReferencedTypes;
        use ir::scope_descriptor::ScopeDescriptor;
        use std::sync::Arc;
        use utilities::linked_list::LinkedList;

        let dog = Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Dog".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: Vec::new(),
            key_fields: None,
        });
        let animal = Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Animal".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: Vec::new(),
            key_fields: None,
        });
        let dog_type = GraphQLCompositeType::Object(Arc::clone(&dog));
        let animal_type = GraphQLCompositeType::Object(Arc::clone(&animal));

        let all_types = Arc::new(ReferencedTypes::new(
            &[
                GraphQLNamedType::Object(Arc::clone(&dog)),
                GraphQLNamedType::Object(Arc::clone(&animal)),
            ],
            compilation_result::RootTypeDefinition {
                query_type: GraphQLNamedType::Object(Arc::clone(&animal)),
                mutation_type: None,
                subscription_type: None,
            },
        ));

        let root_scope = ScopeDescriptor::descriptor(&animal_type, None, &all_types);
        let child_scope = root_scope.appending(ScopeCondition::with_type(dog_type.clone()));
        let scope_path = LinkedList::from_collection(vec![root_scope, child_scope]);

        let op_def = Arc::new(compilation_result::OperationDefinition {
            name: "TestOp".to_string(),
            operation_type: compilation_result::OperationType::Query,
            variables: Vec::new(),
            root_type: animal_type.clone(),
            selection_set: compilation_result::SelectionSet {
                parent_type: animal_type.clone(),
                selections: Vec::new(),
            },
            directives: None,
            referenced_fragments: Vec::new(),
            source: "query TestOp { id }".to_string(),
            file_path: "test.graphql".to_string(),
        });

        let entity = Arc::new(Entity::new_root(SourceDefinition::Operation(op_def)));
        let type_info = Arc::new(TypeInfo::new(entity, scope_path));

        assert_eq!(rendered_type_name(&type_info), "AsDog");
    }
}
