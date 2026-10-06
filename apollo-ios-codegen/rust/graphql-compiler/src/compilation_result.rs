use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use indexmap::IndexSet;
use serde::Serialize;

use crate::graphql_type::GraphQLType;
use crate::graphql_value::GraphQLValue;
use crate::schema::{GraphQLCompositeType, GraphQLNamedType};

// MARK: - Constants

/// Directive name constants matching Swift's `CompilationResult.Constants`.
pub(crate) mod directive_names {
    pub const IMPORT: &str = "import";
    pub const LOCAL_CACHE_MUTATION: &str = "apollo_client_ios_localCacheMutation";
    pub const DEFER: &str = "defer";
}

// MARK: - CompilationResult

/// The output of the frontend compiler.
/// Mirrors `CompilationResult` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct CompilationResult {
    pub schema_root_types: RootTypeDefinition,
    pub referenced_types: Vec<GraphQLNamedType>,
    pub operations: Vec<OperationDefinition>,
    pub fragments: Vec<FragmentDefinition>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub schema_documentation: Option<String>,
}

// MARK: - RootTypeDefinition

/// Root type definitions for a GraphQL schema.
/// Mirrors `CompilationResult.RootTypeDefinition` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct RootTypeDefinition {
    pub query_type: GraphQLNamedType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mutation_type: Option<GraphQLNamedType>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subscription_type: Option<GraphQLNamedType>,
}

impl RootTypeDefinition {
    /// Returns all non-None root types.
    /// Mirrors Swift's `allRootTypes` computed property.
    pub fn all_root_types(&self) -> Vec<&GraphQLNamedType> {
        let mut types = vec![&self.query_type];
        if let Some(ref mt) = self.mutation_type {
            types.push(mt);
        }
        if let Some(ref st) = self.subscription_type {
            types.push(st);
        }
        types
    }
}

// MARK: - OperationType

/// The type of a GraphQL operation.
/// Mirrors `CompilationResult.OperationType` from `CompilationResult.swift`.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
pub enum OperationType {
    Query,
    Mutation,
    Subscription,
}

impl fmt::Display for OperationType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            OperationType::Query => write!(f, "query"),
            OperationType::Mutation => write!(f, "mutation"),
            OperationType::Subscription => write!(f, "subscription"),
        }
    }
}

// MARK: - OperationDefinition

/// A compiled GraphQL operation definition.
/// Mirrors `CompilationResult.OperationDefinition` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct OperationDefinition {
    pub name: String,
    pub operation_type: OperationType,
    pub variables: Vec<VariableDefinition>,
    pub root_type: GraphQLCompositeType,
    pub selection_set: SelectionSet,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub directives: Option<Vec<Directive>>,
    pub referenced_fragments: Vec<Arc<FragmentDefinition>>,
    pub source: String,
    pub file_path: String,
}

impl OperationDefinition {
    /// Returns `true` if this operation is a local cache mutation.
    /// Computed from directives checking for "apollo_client_ios_localCacheMutation".
    pub fn is_local_cache_mutation(&self) -> bool {
        self.directives.as_ref().is_some_and(|dirs| {
            dirs.iter()
                .any(|d| d.name == directive_names::LOCAL_CACHE_MUTATION)
        })
    }

    /// Returns the sorted set of module import names.
    /// Computed from @import directives on this operation and its referenced fragments.
    pub fn module_imports(&self) -> IndexSet<String> {
        get_import_module_names(&self.directives, &self.referenced_fragments)
    }
}

impl Hash for OperationDefinition {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
    }
}

impl PartialEq for OperationDefinition {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl Eq for OperationDefinition {}

impl fmt::Display for OperationDefinition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} on {}", self.name, self.root_type)
    }
}

// MARK: - VariableDefinition

/// A variable definition within a GraphQL operation.
/// Mirrors `CompilationResult.VariableDefinition` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct VariableDefinition {
    pub name: String,
    #[serde(rename = "type")]
    pub type_: GraphQLType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub default_value: Option<GraphQLValue>,
}

// MARK: - FragmentDefinition

/// A compiled GraphQL fragment definition.
/// Mirrors `CompilationResult.FragmentDefinition` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct FragmentDefinition {
    pub name: String,
    #[serde(rename = "type")]
    pub type_: GraphQLCompositeType,
    pub selection_set: SelectionSet,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub directives: Option<Vec<Directive>>,
    pub referenced_fragments: Vec<Arc<FragmentDefinition>>,
    pub source: String,
    pub file_path: String,
}

impl FragmentDefinition {
    /// Returns `true` if this fragment is a local cache mutation.
    pub fn is_local_cache_mutation(&self) -> bool {
        self.directives.as_ref().is_some_and(|dirs| {
            dirs.iter()
                .any(|d| d.name == directive_names::LOCAL_CACHE_MUTATION)
        })
    }

    /// Returns the sorted set of module import names.
    pub fn module_imports(&self) -> IndexSet<String> {
        get_import_module_names(&self.directives, &self.referenced_fragments)
    }
}

impl Hash for FragmentDefinition {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
    }
}

impl PartialEq for FragmentDefinition {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl Eq for FragmentDefinition {}

impl fmt::Display for FragmentDefinition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} on {}", self.name, self.type_)
    }
}

// MARK: - SelectionSet

/// A selection set within a GraphQL operation or fragment.
/// Mirrors `CompilationResult.SelectionSet` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct SelectionSet {
    pub parent_type: GraphQLCompositeType,
    pub selections: Vec<Selection>,
}

impl Hash for SelectionSet {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.parent_type.hash(state);
        self.selections.hash(state);
    }
}

impl PartialEq for SelectionSet {
    fn eq(&self, other: &Self) -> bool {
        self.parent_type == other.parent_type && self.selections == other.selections
    }
}

impl Eq for SelectionSet {}

// MARK: - Selection

/// A single selection in a selection set.
/// Mirrors `CompilationResult.Selection` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub enum Selection {
    Field(Field),
    InlineFragment(InlineFragment),
    FragmentSpread(FragmentSpread),
}

impl Hash for Selection {
    fn hash<H: Hasher>(&self, state: &mut H) {
        std::mem::discriminant(self).hash(state);
        match self {
            Selection::Field(f) => f.hash(state),
            Selection::InlineFragment(i) => i.hash(state),
            Selection::FragmentSpread(s) => s.hash(state),
        }
    }
}

impl PartialEq for Selection {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Selection::Field(a), Selection::Field(b)) => a == b,
            (Selection::InlineFragment(a), Selection::InlineFragment(b)) => a == b,
            (Selection::FragmentSpread(a), Selection::FragmentSpread(b)) => a == b,
            _ => false,
        }
    }
}

impl Eq for Selection {}

// MARK: - Field

/// A field selection in a GraphQL operation.
/// Mirrors `CompilationResult.Field` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct Field {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub alias: Option<String>,
    #[serde(rename = "type")]
    pub type_: GraphQLType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub arguments: Option<Vec<Argument>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub inclusion_conditions: Option<Vec<InclusionCondition>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub directives: Option<Vec<Directive>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub selection_set: Option<SelectionSet>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deprecation_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation: Option<String>,
}

impl Field {
    /// Returns the response key for this field (alias if present, otherwise name).
    /// Mirrors Swift's `responseKey` computed property.
    pub fn response_key(&self) -> &str {
        self.alias.as_deref().unwrap_or(&self.name)
    }

    /// Returns `true` if this field is deprecated.
    pub fn is_deprecated(&self) -> bool {
        self.deprecation_reason.is_some()
    }
}

impl Hash for Field {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
        self.alias.hash(state);
        self.type_.hash(state);
        self.arguments.hash(state);
        self.directives.hash(state);
        self.selection_set.hash(state);
    }
}

impl PartialEq for Field {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
            && self.alias == other.alias
            && self.type_ == other.type_
            && self.arguments == other.arguments
            && self.directives == other.directives
            && self.selection_set == other.selection_set
    }
}

impl Eq for Field {}

// MARK: - InlineFragment

/// An inline fragment selection.
/// Mirrors `CompilationResult.InlineFragment` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct InlineFragment {
    pub selection_set: SelectionSet,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub inclusion_conditions: Option<Vec<InclusionCondition>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub directives: Option<Vec<Directive>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub defer_condition: Option<DeferCondition>,
}

impl Hash for InlineFragment {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.selection_set.hash(state);
        self.inclusion_conditions.hash(state);
    }
}

impl PartialEq for InlineFragment {
    fn eq(&self, other: &Self) -> bool {
        self.selection_set == other.selection_set
            && self.inclusion_conditions == other.inclusion_conditions
    }
}

impl Eq for InlineFragment {}

// MARK: - FragmentSpread

/// A named fragment spread selection.
/// Mirrors `CompilationResult.FragmentSpread` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct FragmentSpread {
    pub fragment: Arc<FragmentDefinition>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub inclusion_conditions: Option<Vec<InclusionCondition>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub directives: Option<Vec<Directive>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub defer_condition: Option<DeferCondition>,
}

impl FragmentSpread {
    /// Returns the parent type of the fragment.
    pub fn parent_type(&self) -> &GraphQLCompositeType {
        &self.fragment.type_
    }
}

impl Hash for FragmentSpread {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.fragment.hash(state);
        self.inclusion_conditions.hash(state);
        self.directives.hash(state);
    }
}

impl PartialEq for FragmentSpread {
    fn eq(&self, other: &Self) -> bool {
        self.fragment == other.fragment
            && self.inclusion_conditions == other.inclusion_conditions
            && self.directives == other.directives
    }
}

impl Eq for FragmentSpread {}

// MARK: - Argument

/// An argument passed to a field or directive.
/// Mirrors `CompilationResult.Argument` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct Argument {
    pub name: String,
    #[serde(rename = "type")]
    pub type_: GraphQLType,
    pub value: GraphQLValue,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deprecation_reason: Option<String>,
}

impl Hash for Argument {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
        self.type_.hash(state);
        self.value.hash(state);
    }
}

impl PartialEq for Argument {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name && self.type_ == other.type_ && self.value == other.value
    }
}

impl Eq for Argument {}

// MARK: - Directive

/// A directive applied to a selection.
/// Mirrors `CompilationResult.Directive` from `CompilationResult.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct Directive {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub arguments: Option<Vec<Argument>>,
}

impl Hash for Directive {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.name.hash(state);
        self.arguments.hash(state);
    }
}

impl PartialEq for Directive {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name && self.arguments == other.arguments
    }
}

impl Eq for Directive {}

impl fmt::Display for Directive {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "@{}", self.name)?;
        if let Some(args) = &self.arguments {
            let args_str: Vec<String> = args
                .iter()
                .map(|a| format!("{}: {:?}", a.name, a.value))
                .collect();
            write!(f, "({})", args_str.join(","))?;
        }
        Ok(())
    }
}

// MARK: - InclusionCondition

/// A condition that determines whether a selection is included.
/// Mirrors `CompilationResult.InclusionCondition` from `CompilationResult.swift`.
///
/// Has exactly 3 variants:
/// - `Included`: always included
/// - `Skipped`: always skipped
/// - `Variable { name, is_inverted }`: conditionally included based on a variable
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
pub enum InclusionCondition {
    Included,
    Skipped,
    Variable { name: String, is_inverted: bool },
}

impl InclusionCondition {
    /// Creates an include condition: `@include(if: $variable)`.
    pub fn include_if(variable: String) -> Self {
        InclusionCondition::Variable {
            name: variable,
            is_inverted: false,
        }
    }

    /// Creates a skip condition: `@skip(if: $variable)`.
    pub fn skip_if(variable: String) -> Self {
        InclusionCondition::Variable {
            name: variable,
            is_inverted: true,
        }
    }
}

// MARK: - DeferCondition

/// A condition for a deferred fragment.
/// Mirrors `CompilationResult.DeferCondition` from `CompilationResult.swift`.
///
/// `label: String`, `variable: Option<String>`.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
pub struct DeferCondition {
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variable: Option<String>,
}

impl fmt::Display for DeferCondition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Defer \"{}\"", self.label)?;
        if let Some(ref var) = self.variable {
            write!(f, " - if \"{}\"", var)?;
        }
        Ok(())
    }
}

// MARK: - ImportDirective

/// Extracts module name from an @import directive.
/// Mirrors `CompilationResult.ImportDirective` from `CompilationResult.swift`.
///
/// This is crate-private, matching Swift's `fileprivate` access.
#[derive(Clone, Debug)]
pub(crate) struct ImportDirective {
    pub module_name: String,
}

impl ImportDirective {
    /// Attempts to extract an ImportDirective from a Directive.
    /// Returns None if the directive is not an @import directive or
    /// doesn't have a valid module argument.
    pub fn from_directive(directive: &Directive) -> Option<Self> {
        if directive.name != directive_names::IMPORT {
            return None;
        }
        let module_arg = directive
            .arguments
            .as_ref()?
            .iter()
            .find(|a| a.name == "module")?;
        match &module_arg.value {
            GraphQLValue::String(module_value) => Some(ImportDirective {
                module_name: module_value.clone(),
            }),
            _ => None,
        }
    }
}

// MARK: - DeferCondition extraction (Deferrable)

/// Extracts a DeferCondition from a list of directives.
/// Mirrors Swift's `Deferrable.getDeferCondition(from:)` protocol extension.
///
/// Panics on a `@defer` whose `label` is missing or not a static string (Swift traps on the
/// same input); the codegen pipeline uses [`try_get_defer_condition`] and reports it.
pub fn get_defer_condition(directives: &Option<Vec<Directive>>) -> Option<DeferCondition> {
    try_get_defer_condition(directives).unwrap_or_else(|e| panic!("{}", e))
}

/// Fallible [`get_defer_condition`]: a malformed `@defer` becomes an error message with
/// graphql-js wording.
pub fn try_get_defer_condition(
    directives: &Option<Vec<Directive>>,
) -> Result<Option<DeferCondition>, String> {
    let Some(dirs) = directives.as_ref() else {
        return Ok(None);
    };
    let Some(defer_directive) = dirs.iter().find(|d| d.name == directive_names::DEFER) else {
        return Ok(None);
    };

    // Extract label argument (required)
    let label = defer_directive
        .arguments
        .as_ref()
        .and_then(|args| args.iter().find(|a| a.name == "label"))
        .and_then(|arg| match &arg.value {
            GraphQLValue::String(s) => Some(s.clone()),
            _ => None,
        })
        .ok_or_else(|| {
            "Directive \"defer\"'s label argument must be a static string.".to_string()
        })?;

    // Extract `if` argument (optional)
    let if_arg = defer_directive
        .arguments
        .as_ref()
        .and_then(|args| args.iter().find(|a| a.name == "if"));

    match if_arg {
        None => Ok(Some(DeferCondition {
            label,
            variable: None,
        })),
        Some(arg) => match &arg.value {
            GraphQLValue::Boolean(true) => Ok(Some(DeferCondition {
                label,
                variable: None,
            })),
            GraphQLValue::Boolean(false) => Ok(None),
            GraphQLValue::String(v) | GraphQLValue::Variable(v) => Ok(Some(DeferCondition {
                label,
                variable: Some(v.clone()),
            })),
            other => Err(format!(
                "Boolean cannot represent a non boolean value: {:?}",
                other
            )),
        },
    }
}

// MARK: - Helper: getImportModuleNames

/// Computes the sorted set of module import names from directives and
/// referenced fragments. Mirrors Swift's `getImportModuleNames` private
/// method on OperationDefinition and FragmentDefinition.
fn get_import_module_names(
    directives: &Option<Vec<Directive>>,
    referenced_fragments: &[Arc<FragmentDefinition>],
) -> IndexSet<String> {
    let referenced_imports: Vec<String> = referenced_fragments
        .iter()
        .flat_map(|f| f.module_imports())
        .collect();

    let directive_imports: Vec<String> = directives
        .as_ref()
        .map(|dirs| {
            dirs.iter()
                .filter_map(|d| ImportDirective::from_directive(d).map(|i| i.module_name))
                .collect()
        })
        .unwrap_or_default();

    let mut imports: Vec<String> = referenced_imports
        .into_iter()
        .chain(directive_imports)
        .collect();
    imports.sort();

    let mut ordered = IndexSet::new();
    for import in imports {
        ordered.insert(import);
    }
    ordered
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::graphql_name::GraphQLName;
    use crate::schema::{GraphQLObjectType, GraphQLScalarType};
    use indexmap::IndexMap;

    fn make_scalar(name: &str) -> Arc<GraphQLScalarType> {
        Arc::new(GraphQLScalarType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            specified_by_url: None,
        })
    }

    fn make_string_type() -> GraphQLType {
        GraphQLType::Scalar(make_scalar("String"))
    }

    fn make_composite_object(name: &str) -> GraphQLCompositeType {
        GraphQLCompositeType::Object(Arc::new(GraphQLObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        }))
    }

    #[test]
    fn test_operation_type_variants() {
        assert_eq!(format!("{}", OperationType::Query), "query");
        assert_eq!(format!("{}", OperationType::Mutation), "mutation");
        assert_eq!(format!("{}", OperationType::Subscription), "subscription");
    }

    #[test]
    fn test_variable_definition_stores_fields() {
        let var = VariableDefinition {
            name: "userId".to_string(),
            type_: make_string_type(),
            default_value: None,
        };
        assert_eq!(var.name, "userId");
        assert!(var.default_value.is_none());
    }

    #[test]
    fn test_selection_set_stores_parent_type_and_selections() {
        let ss = SelectionSet {
            parent_type: make_composite_object("Query"),
            selections: vec![],
        };
        assert_eq!(ss.parent_type.name().schema_name, "Query");
        assert!(ss.selections.is_empty());
    }

    #[test]
    fn test_selection_enum_variants() {
        let field = Selection::Field(Field {
            name: "id".to_string(),
            alias: None,
            type_: make_string_type(),
            arguments: None,
            inclusion_conditions: None,
            directives: None,
            selection_set: None,
            deprecation_reason: None,
            documentation: None,
        });
        assert!(matches!(field, Selection::Field(_)));

        let inline = Selection::InlineFragment(InlineFragment {
            selection_set: SelectionSet {
                parent_type: make_composite_object("User"),
                selections: vec![],
            },
            inclusion_conditions: None,
            directives: None,
            defer_condition: None,
        });
        assert!(matches!(inline, Selection::InlineFragment(_)));

        let fragment_def = Arc::new(FragmentDefinition {
            name: "UserFields".to_string(),
            type_: make_composite_object("User"),
            selection_set: SelectionSet {
                parent_type: make_composite_object("User"),
                selections: vec![],
            },
            directives: None,
            referenced_fragments: vec![],
            source: String::new(),
            file_path: String::new(),
        });
        let spread = Selection::FragmentSpread(FragmentSpread {
            fragment: fragment_def,
            inclusion_conditions: None,
            directives: None,
            defer_condition: None,
        });
        assert!(matches!(spread, Selection::FragmentSpread(_)));
    }

    #[test]
    fn test_field_response_key_returns_alias_if_present() {
        let field = Field {
            name: "firstName".to_string(),
            alias: Some("name".to_string()),
            type_: make_string_type(),
            arguments: None,
            inclusion_conditions: None,
            directives: None,
            selection_set: None,
            deprecation_reason: None,
            documentation: None,
        };
        assert_eq!(field.response_key(), "name");
    }

    #[test]
    fn test_field_response_key_returns_name_if_no_alias() {
        let field = Field {
            name: "firstName".to_string(),
            alias: None,
            type_: make_string_type(),
            arguments: None,
            inclusion_conditions: None,
            directives: None,
            selection_set: None,
            deprecation_reason: None,
            documentation: None,
        };
        assert_eq!(field.response_key(), "firstName");
    }

    #[test]
    fn test_field_stores_all_fields() {
        let field = Field {
            name: "email".to_string(),
            alias: Some("userEmail".to_string()),
            type_: make_string_type(),
            arguments: Some(vec![Argument {
                name: "format".to_string(),
                type_: make_string_type(),
                value: GraphQLValue::String("lowercase".to_string()),
                deprecation_reason: None,
            }]),
            inclusion_conditions: Some(vec![InclusionCondition::Included]),
            directives: Some(vec![]),
            selection_set: None,
            deprecation_reason: Some("Use emailAddress".to_string()),
            documentation: Some("Email field".to_string()),
        };
        assert_eq!(field.name, "email");
        assert_eq!(field.alias.as_deref(), Some("userEmail"));
        assert!(field.arguments.is_some());
        assert!(field.inclusion_conditions.is_some());
        assert!(field.is_deprecated());
        assert!(field.documentation.is_some());
    }

    #[test]
    fn test_inline_fragment_stores_fields() {
        let inline = InlineFragment {
            selection_set: SelectionSet {
                parent_type: make_composite_object("User"),
                selections: vec![],
            },
            inclusion_conditions: Some(vec![InclusionCondition::include_if(
                "showUser".to_string(),
            )]),
            directives: None,
            defer_condition: Some(DeferCondition {
                label: "userDetails".to_string(),
                variable: None,
            }),
        };
        assert!(inline.inclusion_conditions.is_some());
        assert!(inline.defer_condition.is_some());
    }

    #[test]
    fn test_fragment_spread_stores_fields() {
        let fragment_def = Arc::new(FragmentDefinition {
            name: "UserFields".to_string(),
            type_: make_composite_object("User"),
            selection_set: SelectionSet {
                parent_type: make_composite_object("User"),
                selections: vec![],
            },
            directives: None,
            referenced_fragments: vec![],
            source: String::new(),
            file_path: String::new(),
        });

        let spread = FragmentSpread {
            fragment: Arc::clone(&fragment_def),
            inclusion_conditions: Some(vec![InclusionCondition::Skipped]),
            directives: None,
            defer_condition: Some(DeferCondition {
                label: "deferred".to_string(),
                variable: Some("shouldDefer".to_string()),
            }),
        };
        assert_eq!(spread.fragment.name, "UserFields");
        assert!(spread.inclusion_conditions.is_some());
        assert!(spread.defer_condition.is_some());
    }

    #[test]
    fn test_argument_stores_fields() {
        let arg = Argument {
            name: "id".to_string(),
            type_: make_string_type(),
            value: GraphQLValue::String("123".to_string()),
            deprecation_reason: Some("Use newId".to_string()),
        };
        assert_eq!(arg.name, "id");
        assert!(arg.deprecation_reason.is_some());
    }

    #[test]
    fn test_directive_stores_fields() {
        let dir = Directive {
            name: "skip".to_string(),
            arguments: Some(vec![Argument {
                name: "if".to_string(),
                type_: GraphQLType::Scalar(make_scalar("Boolean")),
                value: GraphQLValue::Boolean(true),
                deprecation_reason: None,
            }]),
        };
        assert_eq!(dir.name, "skip");
        assert_eq!(dir.arguments.as_ref().unwrap().len(), 1);
    }

    #[test]
    fn test_inclusion_condition_included() {
        let cond = InclusionCondition::Included;
        assert_eq!(cond, InclusionCondition::Included);
    }

    #[test]
    fn test_inclusion_condition_skipped() {
        let cond = InclusionCondition::Skipped;
        assert_eq!(cond, InclusionCondition::Skipped);
    }

    #[test]
    fn test_inclusion_condition_variable() {
        let cond = InclusionCondition::Variable {
            name: "showDetails".to_string(),
            is_inverted: false,
        };
        if let InclusionCondition::Variable { name, is_inverted } = &cond {
            assert_eq!(name, "showDetails");
            assert!(!is_inverted);
        } else {
            panic!("Expected Variable variant");
        }

        let skip_cond = InclusionCondition::skip_if("hideDetails".to_string());
        if let InclusionCondition::Variable { name, is_inverted } = &skip_cond {
            assert_eq!(name, "hideDetails");
            assert!(is_inverted);
        } else {
            panic!("Expected Variable variant");
        }
    }

    #[test]
    fn test_defer_condition_stores_label_and_variable() {
        let cond = DeferCondition {
            label: "userDetails".to_string(),
            variable: Some("shouldDefer".to_string()),
        };
        assert_eq!(cond.label, "userDetails");
        assert_eq!(cond.variable.as_deref(), Some("shouldDefer"));

        let simple = DeferCondition {
            label: "basic".to_string(),
            variable: None,
        };
        assert_eq!(simple.label, "basic");
        assert!(simple.variable.is_none());
    }

    #[test]
    fn test_import_directive_extracts_module_name() {
        let dir = Directive {
            name: "import".to_string(),
            arguments: Some(vec![Argument {
                name: "module".to_string(),
                type_: make_string_type(),
                value: GraphQLValue::String("MyModule".to_string()),
                deprecation_reason: None,
            }]),
        };
        let import = ImportDirective::from_directive(&dir).unwrap();
        assert_eq!(import.module_name, "MyModule");
    }

    #[test]
    fn test_import_directive_returns_none_for_non_import() {
        let dir = Directive {
            name: "skip".to_string(),
            arguments: None,
        };
        assert!(ImportDirective::from_directive(&dir).is_none());
    }

    #[test]
    fn test_operation_definition_is_local_cache_mutation() {
        let op = OperationDefinition {
            name: "GetUser".to_string(),
            operation_type: OperationType::Query,
            variables: vec![],
            root_type: make_composite_object("Query"),
            selection_set: SelectionSet {
                parent_type: make_composite_object("Query"),
                selections: vec![],
            },
            directives: Some(vec![Directive {
                name: "apollo_client_ios_localCacheMutation".to_string(),
                arguments: None,
            }]),
            referenced_fragments: vec![],
            source: String::new(),
            file_path: String::new(),
        };
        assert!(op.is_local_cache_mutation());

        let normal_op = OperationDefinition {
            name: "GetUser".to_string(),
            operation_type: OperationType::Query,
            variables: vec![],
            root_type: make_composite_object("Query"),
            selection_set: SelectionSet {
                parent_type: make_composite_object("Query"),
                selections: vec![],
            },
            directives: None,
            referenced_fragments: vec![],
            source: String::new(),
            file_path: String::new(),
        };
        assert!(!normal_op.is_local_cache_mutation());
    }

    #[test]
    fn test_operation_definition_module_imports() {
        let import_dir = Directive {
            name: "import".to_string(),
            arguments: Some(vec![Argument {
                name: "module".to_string(),
                type_: make_string_type(),
                value: GraphQLValue::String("NetworkModule".to_string()),
                deprecation_reason: None,
            }]),
        };

        let op = OperationDefinition {
            name: "GetUser".to_string(),
            operation_type: OperationType::Query,
            variables: vec![],
            root_type: make_composite_object("Query"),
            selection_set: SelectionSet {
                parent_type: make_composite_object("Query"),
                selections: vec![],
            },
            directives: Some(vec![import_dir]),
            referenced_fragments: vec![],
            source: String::new(),
            file_path: String::new(),
        };

        let imports = op.module_imports();
        assert!(imports.contains("NetworkModule"));
    }

    #[test]
    fn test_fragment_definition_is_local_cache_mutation() {
        let frag = FragmentDefinition {
            name: "UserFields".to_string(),
            type_: make_composite_object("User"),
            selection_set: SelectionSet {
                parent_type: make_composite_object("User"),
                selections: vec![],
            },
            directives: Some(vec![Directive {
                name: "apollo_client_ios_localCacheMutation".to_string(),
                arguments: None,
            }]),
            referenced_fragments: vec![],
            source: String::new(),
            file_path: String::new(),
        };
        assert!(frag.is_local_cache_mutation());
    }

    #[test]
    fn test_fragment_definition_module_imports() {
        let inner_frag = Arc::new(FragmentDefinition {
            name: "Inner".to_string(),
            type_: make_composite_object("User"),
            selection_set: SelectionSet {
                parent_type: make_composite_object("User"),
                selections: vec![],
            },
            directives: Some(vec![Directive {
                name: "import".to_string(),
                arguments: Some(vec![Argument {
                    name: "module".to_string(),
                    type_: make_string_type(),
                    value: GraphQLValue::String("InnerModule".to_string()),
                    deprecation_reason: None,
                }]),
            }]),
            referenced_fragments: vec![],
            source: String::new(),
            file_path: String::new(),
        });

        let frag = FragmentDefinition {
            name: "Outer".to_string(),
            type_: make_composite_object("User"),
            selection_set: SelectionSet {
                parent_type: make_composite_object("User"),
                selections: vec![],
            },
            directives: Some(vec![Directive {
                name: "import".to_string(),
                arguments: Some(vec![Argument {
                    name: "module".to_string(),
                    type_: make_string_type(),
                    value: GraphQLValue::String("OuterModule".to_string()),
                    deprecation_reason: None,
                }]),
            }]),
            referenced_fragments: vec![inner_frag],
            source: String::new(),
            file_path: String::new(),
        };

        let imports = frag.module_imports();
        assert!(imports.contains("InnerModule"));
        assert!(imports.contains("OuterModule"));
        // Should be sorted
        let import_vec: Vec<&String> = imports.iter().collect();
        assert_eq!(import_vec, vec!["InnerModule", "OuterModule"]);
    }

    #[test]
    fn test_compilation_result_stores_all_fields() {
        let query_obj = Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Query".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        });

        let result = CompilationResult {
            schema_root_types: RootTypeDefinition {
                query_type: GraphQLNamedType::Object(Arc::clone(&query_obj)),
                mutation_type: None,
                subscription_type: None,
            },
            referenced_types: vec![GraphQLNamedType::Object(Arc::clone(&query_obj))],
            operations: vec![],
            fragments: vec![],
            schema_documentation: Some("Test schema".to_string()),
        };

        assert_eq!(
            result.schema_root_types.query_type.name().schema_name,
            "Query"
        );
        assert!(result.schema_root_types.mutation_type.is_none());
        assert_eq!(result.referenced_types.len(), 1);
        assert!(result.operations.is_empty());
        assert!(result.fragments.is_empty());
        assert_eq!(result.schema_documentation.as_deref(), Some("Test schema"));
    }

    #[test]
    fn test_root_type_definition_all_root_types() {
        let query = GraphQLNamedType::Object(Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Query".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        }));
        let mutation = GraphQLNamedType::Object(Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Mutation".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        }));
        let subscription = GraphQLNamedType::Object(Arc::new(GraphQLObjectType {
            name: GraphQLName::new("Subscription".to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        }));

        let root = RootTypeDefinition {
            query_type: query,
            mutation_type: Some(mutation),
            subscription_type: Some(subscription),
        };

        let all = root.all_root_types();
        assert_eq!(all.len(), 3);
        assert_eq!(all[0].name().schema_name, "Query");
        assert_eq!(all[1].name().schema_name, "Mutation");
        assert_eq!(all[2].name().schema_name, "Subscription");

        // With only query
        let root2 = RootTypeDefinition {
            query_type: GraphQLNamedType::Object(Arc::new(GraphQLObjectType {
                name: GraphQLName::new("Query".to_string()),
                documentation: None,
                fields: IndexMap::new(),
                interfaces: vec![],
                key_fields: None,
            })),
            mutation_type: None,
            subscription_type: None,
        };
        assert_eq!(root2.all_root_types().len(), 1);
    }

    #[test]
    fn test_get_defer_condition_basic() {
        let directives = Some(vec![Directive {
            name: "defer".to_string(),
            arguments: Some(vec![Argument {
                name: "label".to_string(),
                type_: make_string_type(),
                value: GraphQLValue::String("details".to_string()),
                deprecation_reason: None,
            }]),
        }]);

        let cond = get_defer_condition(&directives).unwrap();
        assert_eq!(cond.label, "details");
        assert!(cond.variable.is_none());
    }

    #[test]
    fn test_get_defer_condition_with_variable() {
        let directives = Some(vec![Directive {
            name: "defer".to_string(),
            arguments: Some(vec![
                Argument {
                    name: "label".to_string(),
                    type_: make_string_type(),
                    value: GraphQLValue::String("details".to_string()),
                    deprecation_reason: None,
                },
                Argument {
                    name: "if".to_string(),
                    type_: GraphQLType::Scalar(make_scalar("Boolean")),
                    value: GraphQLValue::Variable("shouldDefer".to_string()),
                    deprecation_reason: None,
                },
            ]),
        }]);

        let cond = get_defer_condition(&directives).unwrap();
        assert_eq!(cond.label, "details");
        assert_eq!(cond.variable.as_deref(), Some("shouldDefer"));
    }

    #[test]
    fn test_get_defer_condition_if_false_returns_none() {
        let directives = Some(vec![Directive {
            name: "defer".to_string(),
            arguments: Some(vec![
                Argument {
                    name: "label".to_string(),
                    type_: make_string_type(),
                    value: GraphQLValue::String("details".to_string()),
                    deprecation_reason: None,
                },
                Argument {
                    name: "if".to_string(),
                    type_: GraphQLType::Scalar(make_scalar("Boolean")),
                    value: GraphQLValue::Boolean(false),
                    deprecation_reason: None,
                },
            ]),
        }]);

        assert!(get_defer_condition(&directives).is_none());
    }

    #[test]
    fn test_get_defer_condition_if_true() {
        let directives = Some(vec![Directive {
            name: "defer".to_string(),
            arguments: Some(vec![
                Argument {
                    name: "label".to_string(),
                    type_: make_string_type(),
                    value: GraphQLValue::String("details".to_string()),
                    deprecation_reason: None,
                },
                Argument {
                    name: "if".to_string(),
                    type_: GraphQLType::Scalar(make_scalar("Boolean")),
                    value: GraphQLValue::Boolean(true),
                    deprecation_reason: None,
                },
            ]),
        }]);

        let cond = get_defer_condition(&directives).unwrap();
        assert_eq!(cond.label, "details");
        assert!(cond.variable.is_none());
    }

    #[test]
    fn test_get_defer_condition_no_defer_directive() {
        let directives = Some(vec![Directive {
            name: "skip".to_string(),
            arguments: None,
        }]);
        assert!(get_defer_condition(&directives).is_none());

        assert!(get_defer_condition(&None).is_none());
    }
}
