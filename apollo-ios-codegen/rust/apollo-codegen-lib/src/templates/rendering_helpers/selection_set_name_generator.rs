//! Selection set name generation and caching for code generation.
//!
//! Mirrors the SelectionSetNameGenerator and SelectionSetNameCache from Swift's
//! `SelectionSetTemplate.swift` (lines 800-1176).

use ir::entity::{FieldComponent, SourceDefinition};
use ir::merged_selections::MergedSource;
use ir::scope_descriptor::ScopeCondition;
use ir::selection_set::TypeInfo;
use ir::ComputedSelectionSet;

use crate::capitalizer::Capitalizer;
use crate::templates::rendering_helpers::ir_definition_rendering::{
    generated_definition_name_capitalized, generated_fragment_definition_name_capitalized,
};
use crate::templates::rendering_helpers::string_casing::first_uppercased;
use crate::templates::rendering_helpers::string_swift_name_escaping::as_selection_set_name;
use crate::templates::ConfigurationContext;

use utilities::linked_list::NodeRef;

// MARK: - SelectionSetNameCache

/// Computes selection set names for TypeInfo instances.
///
/// Mirrors Swift's `SelectionSetNameCache` class from `SelectionSetTemplate.swift`.
/// Note: Swift uses pointer-identity caching because TypeInfo is a class (reference type)
/// whose lifetime is guaranteed by the IR graph. In Rust, TypeInfo is behind Arc and
/// temporary ComputedSelectionSets can be freed during recursive rendering, causing
/// pointer reuse and stale cache hits. We always recompute instead — the computation
/// is cheap (uppercasing + optional singularization of a field name).
pub struct SelectionSetNameCache {
    config: *const ConfigurationContext,
}

impl SelectionSetNameCache {
    pub fn new(config: &ConfigurationContext) -> Self {
        SelectionSetNameCache {
            config: config as *const ConfigurationContext,
        }
    }

    /// Returns the selection set name for the given type info, computing and caching if needed.
    ///
    /// Mirrors Swift's `SelectionSetNameCache.selectionSetName(for:)`.
    pub fn selection_set_name(&mut self, type_info: &TypeInfo) -> String {
        // Note: Swift uses pointer identity here because TypeInfo is a class (reference type)
        // whose lifetime is guaranteed by the IR graph. In Rust, TypeInfo is behind Arc and
        // temporary ComputedSelectionSets can be freed during recursive rendering, causing
        // pointer reuse. We skip caching and always compute — the computation is cheap
        // (just uppercasing + optional singularization of a field name).
        compute_generated_selection_set_name(type_info, self.context())
    }

    /// Returns the rendered type for an entity field, wrapping the name in the field's
    /// GraphQL type structure (optional/list wrapping).
    ///
    /// Mirrors Swift's `SelectionSetNameCache.selectionSetType(for:)`.
    pub fn selection_set_type(&mut self, field: &ir::EntityField) -> String {
        let name = self.selection_set_name(&field.selection_set.type_info);
        use crate::templates::rendering_helpers::graphql_type_rendered::{
            rendered, TypeRenderContext,
        };
        rendered(
            &field.underlying_field.type_,
            &TypeRenderContext::SelectionSetField {
                force_non_null: false,
            },
            Some(&name),
            self.config_ref(),
        )
    }

    fn context(&self) -> &ConfigurationContext {
        // SAFETY: The pointer is valid for the lifetime of template rendering.
        unsafe { &*self.config }
    }

    fn config_ref(&self) -> &crate::config::ApolloCodegenConfiguration {
        // SAFETY: The pointer is valid for the lifetime of template rendering.
        unsafe { &(*self.config).config }
    }
}

// MARK: - Name Computation

/// Computes the generated selection set name for a TypeInfo.
///
/// Mirrors Swift's `SelectionSetNameCache.computeGeneratedSelectionSetName(for:)`.
pub fn compute_generated_selection_set_name(
    type_info: &TypeInfo,
    config: &ConfigurationContext,
) -> String {
    let location = &type_info.entity.location;
    if let Some(ref field_path) = location.field_path {
        formatted_selection_set_name_for_field_component(field_path.last(), config)
    } else {
        formatted_selection_set_name_for_source(&location.source, &config.capitalizer)
    }
}

// MARK: - NameFormat

/// The format for a generated selection set name.
///
/// Mirrors Swift's `SelectionSetNameGenerator.Format` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NameFormat {
    /// Fully qualifies the name including the enclosing operation or fragment name.
    FullyQualified,
    /// Omits the root entity selection set name.
    OmittingRoot,
}

// MARK: - SelectionSetNameGenerator

/// Generates selection set names by walking scope paths and field paths.
///
/// Mirrors Swift's `SelectionSetNameGenerator` struct from `SelectionSetTemplate.swift`.
pub struct SelectionSetNameGenerator;

impl SelectionSetNameGenerator {
    /// Generates a selection set name for a ComputedSelectionSet.
    pub fn generated_selection_set_name_for_computed(
        selection_set: &ComputedSelectionSet,
        to_node: Option<NodeRef<'_, ScopeCondition>>,
        format: NameFormat,
        config: &ConfigurationContext,
    ) -> String {
        Self::generated_selection_set_name(&selection_set.type_info, to_node, format, config)
    }

    /// Generates a selection set name for a MergedSource.
    pub fn generated_selection_set_name_for_merged_source(
        source: &MergedSource,
        to_node: Option<NodeRef<'_, ScopeCondition>>,
        format: NameFormat,
        config: &ConfigurationContext,
    ) -> String {
        Self::generated_selection_set_name(&source.type_info, to_node, format, config)
    }

    /// Generates a selection set name for a TypeInfo.
    ///
    /// Mirrors Swift's `SelectionSetNameGenerator.generatedSelectionSetName(for:to:format:pluralizer:)`.
    pub fn generated_selection_set_name(
        type_info: &TypeInfo,
        to_node: Option<NodeRef<'_, ScopeCondition>>,
        format: NameFormat,
        config: &ConfigurationContext,
    ) -> String {
        let mut components: Vec<String> = Vec::new();

        if format == NameFormat::FullyQualified {
            let source_name = match &type_info.entity.location.source {
                SourceDefinition::Operation(op) => {
                    let op_type = match op.operation_type {
                        graphql_compiler::compilation_result::OperationType::Query => "query",
                        graphql_compiler::compilation_result::OperationType::Mutation => "mutation",
                        graphql_compiler::compilation_result::OperationType::Subscription => {
                            "subscription"
                        }
                    };
                    format!(
                        "{}.Data",
                        generated_definition_name_capitalized(
                            &op.name,
                            op_type,
                            op.is_local_cache_mutation(),
                            &config.capitalizer,
                        )
                    )
                }
                SourceDefinition::NamedFragment(frag) => {
                    generated_fragment_definition_name_capitalized(&frag.name, &config.capitalizer)
                }
            };
            components.push(source_name);
        }

        let field_path_head = type_info
            .entity
            .location
            .field_path
            .as_ref()
            .map(|fp| fp.head_node());

        let entity_field_path = Self::generated_selection_set_name_from_nodes(
            type_info.scope_path.head_node(),
            to_node,
            field_path_head,
            false,
            config,
        );
        if !entity_field_path.is_empty() {
            components.push(entity_field_path);
        }

        components.join(".")
    }

    /// Generates a selection set name by walking scope path and field path nodes.
    ///
    /// Mirrors Swift's `SelectionSetNameGenerator.generatedSelectionSetName(from:to:withFieldPath:removingFirst:pluralizer:)`.
    pub fn generated_selection_set_name_from_nodes(
        type_path_node: NodeRef<'_, ir::ScopeDescriptor>,
        ending_node: Option<NodeRef<'_, ScopeCondition>>,
        field_path_node: Option<NodeRef<'_, FieldComponent>>,
        removing_first: bool,
        config: &ConfigurationContext,
    ) -> String {
        // Set up starting nodes
        let mut current_type_path_node: Option<NodeRef<'_, ir::ScopeDescriptor>> =
            Some(type_path_node);
        let mut current_condition_node: Option<NodeRef<'_, ScopeCondition>> =
            Some(type_path_node.value().scope_path.head_node());
        // Because the Location's field path starts on the first field (not the location's source),
        // if the typePath is starting from the root entity (ie. is the list's head node),
        // we do not start using the field path until the second entity node.
        let mut current_field_path_node: Option<NodeRef<'_, FieldComponent>> =
            if type_path_node.index() == 0 {
                None
            } else {
                field_path_node
            };

        let mut components: Vec<String> = Vec::new();

        // iterate entity scopes
        loop {
            // For the root node of the entity, we use the name of the field in the entity's field path.
            if let Some(field_node) = current_field_path_node {
                let field_name =
                    formatted_selection_set_name_for_field_component(field_node.value(), config);
                components.push(field_name);
            }

            // If the ending node is the root of this entity, then we are done.
            if let Some(end) = ending_node {
                if let Some(cond) = current_condition_node {
                    if cond == end {
                        break;
                    }
                }
            }

            // If the current entity has conditions in its scope path, we add those.
            if let Some(tp_node) = current_type_path_node {
                current_condition_node = tp_node.value().scope_path.head_node().next();
                while let Some(cond_node) = current_condition_node {
                    components.push(selection_set_name_component(cond_node.value()));

                    if let Some(end) = ending_node {
                        if cond_node == end {
                            // Break out of both loops
                            current_type_path_node = None;
                            break;
                        }
                    }
                    current_condition_node = cond_node.next();
                }
            }

            if current_type_path_node.is_none() {
                break;
            }

            // Advance to next entity
            current_type_path_node =
                current_type_path_node.and_then(|n: NodeRef<'_, ir::ScopeDescriptor>| n.next());
            current_condition_node = current_type_path_node
                .map(|n: NodeRef<'_, ir::ScopeDescriptor>| n.value().scope_path.head_node());
            current_field_path_node = current_field_path_node
                .and_then(|n: NodeRef<'_, FieldComponent>| n.next())
                .or(field_path_node);

            if current_type_path_node.is_none() {
                break;
            }
        }

        if removing_first && !components.is_empty() {
            components.remove(0);
        }

        components.join(".")
    }

    /// Generates a condition path string for the given scope conditions.
    ///
    /// Mirrors Swift's `SelectionSetNameGenerator.ConditionPath.path(for:)`.
    pub fn condition_path(conditions: NodeRef<'_, ScopeCondition>) -> String {
        let mut parts = Vec::new();
        let mut current: Option<NodeRef<'_, ScopeCondition>> = Some(conditions);
        while let Some(node) = current {
            parts.push(selection_set_name_component(node.value()));
            current = node.next();
        }
        parts.join(".")
    }
}

// MARK: - Free functions for IR type formatting

/// Returns the selection set name component for a scope condition.
///
/// Mirrors Swift's `IR.ScopeCondition.selectionSetNameComponent` extension
/// from `SelectionSetTemplate.swift` (lines 1178-1193).
pub fn selection_set_name_component(condition: &ScopeCondition) -> String {
    if let Some(ref defer_cond) = condition.defer_condition {
        return defer_condition_rendered_type_name(defer_cond);
    }

    let mut result = String::new();
    if let Some(ref type_) = condition.type_ {
        let type_name = render_composite_type_name(type_);
        result.push_str(&format!("As{}", type_name));
    }
    if let Some(ref conditions) = condition.conditions {
        result.push_str(&format!(
            "If{}",
            inclusion_conditions_type_name_components(conditions)
        ));
    }
    result
}

/// Returns the rendered type name for a defer condition label.
///
/// Mirrors Swift's `CompilationResult.DeferCondition.renderedTypeName` extension
/// from `SelectionSetTemplate.swift` (lines 1251-1254).
pub fn defer_condition_rendered_type_name(condition: &graphql_compiler::DeferCondition) -> String {
    use crate::templates::rendering_helpers::string_swift_name_escaping::convert_to_camel_case;
    let camel = convert_to_camel_case(&condition.label);
    let uppercased = first_uppercased(&camel);
    as_selection_set_name(&uppercased)
}

/// Renders a composite type name as a typename string.
///
/// Mirrors `type.render(as: .typename())` in Swift.
fn render_composite_type_name(type_: &graphql_compiler::GraphQLCompositeType) -> String {
    use crate::templates::rendering_helpers::graphql_name_rendering::{
        render_named_type, RenderContext,
    };
    let named = match type_ {
        graphql_compiler::GraphQLCompositeType::Object(obj) => {
            graphql_compiler::GraphQLNamedType::Object(obj.clone())
        }
        graphql_compiler::GraphQLCompositeType::Interface(iface) => {
            graphql_compiler::GraphQLNamedType::Interface(iface.clone())
        }
        graphql_compiler::GraphQLCompositeType::Union(u) => {
            graphql_compiler::GraphQLNamedType::Union(u.clone())
        }
    };
    render_named_type(
        &named,
        &RenderContext::Typename {
            is_input_value: false,
        },
    )
}

/// Formats a FieldComponent as a selection set name (uppercased, singularized if list).
///
/// Mirrors Swift's `IR.Entity.Location.FieldComponent.formattedSelectionSetName(with:)`.
pub fn formatted_selection_set_name_for_field_component(
    field: &FieldComponent,
    config: &ConfigurationContext,
) -> String {
    let mut field_name = first_uppercased(&field.name);
    if field.type_.is_list_type() {
        field_name = config.pluralizer.singularize(&field_name);
    }
    as_selection_set_name(&field_name)
}

/// Formats a SourceDefinition as a selection set name.
///
/// Mirrors Swift's `IR.Entity.Location.SourceDefinition.formattedSelectionSetName()`.
fn formatted_selection_set_name_for_source(
    source: &SourceDefinition,
    capitalizer: &Capitalizer,
) -> String {
    match source {
        SourceDefinition::Operation(_) => "Data".to_string(),
        SourceDefinition::NamedFragment(frag) => {
            generated_fragment_definition_name_capitalized(&frag.name, capitalizer)
        }
    }
}

/// Renders the type name components for inclusion conditions.
///
/// Mirrors Swift's `IR.InclusionConditions.typeNameComponents` extension.
fn inclusion_conditions_type_name_components(conditions: &ir::InclusionConditions) -> String {
    let parts: Vec<String> = conditions
        .iter()
        .map(inclusion_condition_type_name_component)
        .collect();
    parts.join("And")
}

/// Renders a single inclusion condition as a type name component.
///
/// Mirrors Swift's `IR.InclusionCondition.typeNameComponent` extension.
fn inclusion_condition_type_name_component(condition: &ir::InclusionCondition) -> String {
    let prefix = if condition.is_inverted { "Not" } else { "" };
    format!("{}{}", prefix, first_uppercased(&condition.variable))
}

#[cfg(test)]
mod tests {
    use super::*;
    use graphql_compiler::DeferCondition;
    use utilities::linked_list::LinkedList;

    #[test]
    fn test_defer_condition_rendered_type_name_simple() {
        let cond = DeferCondition {
            label: "my_deferred".to_string(),
            variable: None,
        };
        assert_eq!(defer_condition_rendered_type_name(&cond), "MyDeferred");
    }

    #[test]
    fn test_defer_condition_rendered_type_name_reserved() {
        // "Self" is in TYPE_NAMES_TO_SUFFIX
        let cond = DeferCondition {
            label: "self".to_string(),
            variable: None,
        };
        assert_eq!(
            defer_condition_rendered_type_name(&cond),
            "Self_SelectionSet"
        );
    }

    #[test]
    fn test_selection_set_name_component_type_only() {
        use graphql_compiler::{GraphQLCompositeType, GraphQLName, GraphQLObjectType};
        use indexmap::IndexMap;
        use std::sync::Arc;

        let obj = Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Dog".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: Vec::new(),
            key_fields: None,
        });
        let cond = ScopeCondition::with_type(GraphQLCompositeType::Object(obj));
        assert_eq!(selection_set_name_component(&cond), "AsDog");
    }

    #[test]
    fn test_selection_set_name_component_conditions_only() {
        use ir::inclusion_conditions::{InclusionCondition, InclusionConditions};

        let cond = ScopeCondition::with_conditions(InclusionConditions::new(
            InclusionCondition::include_if("showDetails".to_string()),
        ));
        assert_eq!(selection_set_name_component(&cond), "IfShowDetails");
    }

    #[test]
    fn test_selection_set_name_component_inverted_condition() {
        use ir::inclusion_conditions::{InclusionCondition, InclusionConditions};

        let cond = ScopeCondition::with_conditions(InclusionConditions::new(
            InclusionCondition::skip_if("hideField".to_string()),
        ));
        assert_eq!(selection_set_name_component(&cond), "IfNotHideField");
    }

    #[test]
    fn test_selection_set_name_component_deferred() {
        let cond = ScopeCondition::new(
            None,
            None,
            Some(DeferCondition {
                label: "details_section".to_string(),
                variable: None,
            }),
        );
        assert_eq!(selection_set_name_component(&cond), "DetailsSection");
    }

    #[test]
    fn test_selection_set_name_component_type_and_conditions() {
        use graphql_compiler::{GraphQLCompositeType, GraphQLName, GraphQLObjectType};
        use indexmap::IndexMap;
        use ir::inclusion_conditions::{InclusionCondition, InclusionConditions};
        use std::sync::Arc;

        let obj = Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Dog".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: Vec::new(),
            key_fields: None,
        });
        let cond = ScopeCondition::new(
            Some(GraphQLCompositeType::Object(obj)),
            Some(InclusionConditions::new(InclusionCondition::include_if(
                "showDog".to_string(),
            ))),
            None,
        );
        assert_eq!(selection_set_name_component(&cond), "AsDogIfShowDog");
    }

    #[test]
    fn test_name_cache_returns_cached_value() {
        use graphql_compiler::{
            compilation_result, GraphQLCompositeType, GraphQLName, GraphQLNamedType,
            GraphQLObjectType,
        };
        use indexmap::IndexMap;
        use ir::entity::{Entity, SourceDefinition};
        use ir::schema::ReferencedTypes;
        use ir::scope_descriptor::ScopeDescriptor;
        use std::sync::Arc;

        let obj = Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Query".to_string()),
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
        let scope_path = LinkedList::new(scope);

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
        let type_info = Arc::new(TypeInfo::new(entity, scope_path));

        let config: crate::config::ApolloCodegenConfiguration = serde_json::from_str(
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
        .unwrap();
        let config_ctx = ConfigurationContext::new(config, None);

        let mut cache = SelectionSetNameCache::new(&config_ctx);
        let name1 = cache.selection_set_name(&type_info);
        let name2 = cache.selection_set_name(&type_info);
        assert_eq!(name1, name2);
        assert_eq!(name1, "Data");
    }
}
