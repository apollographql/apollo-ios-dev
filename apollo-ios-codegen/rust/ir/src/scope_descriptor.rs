use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use indexmap::IndexSet;

use graphql_compiler::{DeferCondition, GraphQLCompositeType};
use utilities::linked_list::LinkedList;

use crate::inclusion_conditions::{AnyOf, InclusionConditions};
use crate::schema::ReferencedTypes;

// MARK: - TypeScope

/// The set of types that a `SelectionSet` matches.
///
/// Mirrors `TypeScope` typealias from `IR+ScopeDescriptor.swift`.
pub type TypeScope = IndexSet<GraphQLCompositeType>;

// MARK: - ScopeCondition

/// A condition defining a scope boundary within an entity's selection sets.
///
/// Mirrors `IR.ScopeCondition` from `IR+ScopeDescriptor.swift`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ScopeCondition {
    /// The type narrowing condition (e.g., `... on SomeType`).
    pub type_: Option<GraphQLCompositeType>,
    /// The inclusion conditions (e.g., `@include(if: $flag)`).
    pub conditions: Option<InclusionConditions>,
    /// The defer condition (e.g., `@defer`).
    pub defer_condition: Option<DeferCondition>,
}

impl ScopeCondition {
    pub fn new(
        type_: Option<GraphQLCompositeType>,
        conditions: Option<InclusionConditions>,
        defer_condition: Option<DeferCondition>,
    ) -> Self {
        ScopeCondition {
            type_,
            conditions,
            defer_condition,
        }
    }

    /// Creates a `ScopeCondition` with only a type narrowing.
    pub fn with_type(type_: GraphQLCompositeType) -> Self {
        ScopeCondition {
            type_: Some(type_),
            conditions: None,
            defer_condition: None,
        }
    }

    /// Creates a `ScopeCondition` with only inclusion conditions.
    pub fn with_conditions(conditions: InclusionConditions) -> Self {
        ScopeCondition {
            type_: None,
            conditions: Some(conditions),
            defer_condition: None,
        }
    }

    /// Returns `true` if this scope condition has no type, no conditions, and no defer.
    pub fn is_empty(&self) -> bool {
        self.type_.is_none()
            && self.conditions.as_ref().map_or(true, |c| c.is_empty())
            && self.defer_condition.is_none()
    }

    /// Returns `true` if this scope condition includes a defer directive.
    pub fn is_deferred(&self) -> bool {
        self.defer_condition.is_some()
    }
}

impl fmt::Display for ScopeCondition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut parts: Vec<String> = Vec::new();
        if let Some(ref t) = self.type_ {
            parts.push(format!("{}", t));
        }
        if let Some(ref c) = self.conditions {
            parts.push(format!("{}", c));
        }
        if let Some(ref d) = self.defer_condition {
            parts.push(format!("{:?}", d));
        }
        write!(f, "{}", parts.join(" "))
    }
}

// MARK: - ScopeDescriptor

/// Defines the scope for an `IR.SelectionSet`. The "scope" indicates where in the entity
/// the selection set is located, what types the `SelectionSet` implements, and what inclusion
/// conditions it requires.
///
/// Mirrors `IR.ScopeDescriptor` from `IR+ScopeDescriptor.swift`.
#[derive(Clone, Debug)]
pub struct ScopeDescriptor {
    /// The parentType of the `SelectionSet`.
    /// Should always be equivalent to the last "type" value of the `scope_path`.
    pub type_: GraphQLCompositeType,

    /// A list of the parent types/conditions for the selection set and its parents
    /// on the same entity.
    pub scope_path: LinkedList<ScopeCondition>,

    /// All of the types that the `SelectionSet` implements. That is, all of the types in the
    /// `type_path`, all of those types' implemented interfaces, and all unions that include
    /// those types.
    pub(crate) matching_types: TypeScope,

    /// All of the inclusion conditions on the entity that must be included for the `SelectionSet`
    /// to be included.
    pub(crate) matching_conditions: Option<InclusionConditions>,

    /// A reference to all types in the schema, used for type scope computation.
    pub all_types_in_schema: Arc<ReferencedTypes>,
}

impl ScopeDescriptor {
    /// Returns `true` if the last scope condition in the path is deferred.
    pub fn is_deferred(&self) -> bool {
        self.scope_path.last().is_deferred()
    }

    /// Creates a `ScopeDescriptor` for a root `SelectionSet`.
    ///
    /// This should only be used to create a `ScopeDescriptor` for a root `SelectionSet`.
    /// Nested type cases should be created by calling `appending()` on the
    /// parent `SelectionSet`'s scope descriptor.
    pub fn descriptor(
        for_type: &GraphQLCompositeType,
        inclusion_conditions: Option<&InclusionConditions>,
        given_all_types: &Arc<ReferencedTypes>,
    ) -> ScopeDescriptor {
        let scope = Self::type_scope_adding(for_type, None, given_all_types);
        ScopeDescriptor {
            scope_path: LinkedList::new(ScopeCondition::new(
                Some(for_type.clone()),
                inclusion_conditions.cloned(),
                None,
            )),
            type_: for_type.clone(),
            matching_types: scope,
            matching_conditions: inclusion_conditions.cloned(),
            all_types_in_schema: Arc::clone(given_all_types),
        }
    }

    /// Computes the type scope by adding a new type to an existing scope.
    ///
    /// Mirrors Swift's `typeScope(addingType:to:givenAllTypes:)`.
    ///
    /// For Object types: adds all interfaces the object implements, and all unions
    /// that include the object.
    /// For Interface types: adds all objects implementing the interface, their
    /// interfaces (transitive), and unions containing those objects.
    /// For Union types: handled implicitly (just the union itself is added).
    fn type_scope_adding(
        new_type: &GraphQLCompositeType,
        to_scope: Option<&TypeScope>,
        all_types: &ReferencedTypes,
    ) -> TypeScope {
        if let Some(scope) = to_scope {
            if scope.contains(new_type) {
                return scope.clone();
            }
        }

        let mut new_scope = to_scope.cloned().unwrap_or_default();
        new_scope.insert(new_type.clone());

        // If the type implements interfaces, add them
        match new_type {
            GraphQLCompositeType::Object(obj) => {
                // Add all interfaces this object implements
                for iface in &obj.interfaces {
                    new_scope.insert(GraphQLCompositeType::Interface(Arc::clone(iface)));
                }
                // Add all unions that include this object
                let unions = all_types.unions_including(obj);
                for union in unions {
                    new_scope.insert(GraphQLCompositeType::Union(Arc::clone(union)));
                }
            }
            GraphQLCompositeType::Interface(iface) => {
                // Add all interfaces this interface implements (interface-to-interface)
                for parent_iface in &iface.interfaces {
                    new_scope.insert(GraphQLCompositeType::Interface(Arc::clone(parent_iface)));
                }
            }
            GraphQLCompositeType::Union(_) => {
                // Union itself is already added
            }
        }

        new_scope
    }

    /// Returns a new `ScopeDescriptor` appending the new `ScopeCondition` to the `scope_path`.
    /// Any new types are added to the `matching_types`, and any new conditions are added to the
    /// `matching_conditions`.
    pub fn appending(&self, scope_condition: ScopeCondition) -> ScopeDescriptor {
        let matching_types = if let Some(ref new_type) = scope_condition.type_ {
            Self::type_scope_adding(new_type, Some(&self.matching_types), &self.all_types_in_schema)
        } else {
            self.matching_types.clone()
        };

        let matching_conditions = if let Some(ref new_conditions) = scope_condition.conditions {
            Some(
                self.matching_conditions
                    .as_ref()
                    .map(|mc| mc.appending_conditions(new_conditions))
                    .unwrap_or_else(|| new_conditions.clone()),
            )
        } else {
            self.matching_conditions.clone()
        };

        ScopeDescriptor {
            scope_path: self.scope_path.appending(scope_condition.clone()),
            type_: scope_condition.type_.unwrap_or_else(|| self.type_.clone()),
            matching_types,
            matching_conditions,
            all_types_in_schema: Arc::clone(&self.all_types_in_schema),
        }
    }

    /// Returns a new `ScopeDescriptor` appending a type narrowing.
    pub fn appending_type(&self, new_type: GraphQLCompositeType) -> ScopeDescriptor {
        self.appending(ScopeCondition::with_type(new_type))
    }

    /// Returns a new `ScopeDescriptor` appending inclusion conditions.
    pub fn appending_conditions(&self, conditions: InclusionConditions) -> ScopeDescriptor {
        self.appending(ScopeCondition::with_conditions(conditions))
    }

    /// Indicates if the receiver matches all of the types in the given `TypeScope`.
    pub fn matches_type_scope(&self, other_scope: &TypeScope) -> bool {
        other_scope.is_subset(&self.matching_types)
    }

    /// Indicates if the receiver matches the given type.
    pub fn matches(&self, other_type: &GraphQLCompositeType) -> bool {
        self.matching_types.contains(other_type)
    }

    /// Indicates if the receiver matches the given inclusion conditions.
    pub fn matches_conditions(&self, other_conditions: &InclusionConditions) -> bool {
        other_conditions.is_subset_of(self.matching_conditions.as_ref())
    }

    /// Indicates if the receiver matches any of the given inclusion condition groups.
    pub fn matches_any_of(&self, other_conditions: &AnyOf<InclusionConditions>) -> bool {
        for condition_group in &other_conditions.elements {
            if condition_group.is_subset_of(self.matching_conditions.as_ref()) {
                return true;
            }
        }
        false
    }

    /// Indicates if the receiver matches the given defer condition.
    pub fn matches_defer(&self, other_defer_condition: &DeferCondition) -> bool {
        self.scope_path
            .last()
            .defer_condition
            .as_ref()
            .map_or(false, |dc| dc == other_defer_condition)
    }

    /// Indicates if the receiver matches the given scope condition.
    pub fn matches_scope_condition(&self, condition: &ScopeCondition) -> bool {
        if let Some(ref type_) = condition.type_ {
            if !self.matches(type_) {
                return false;
            }
        }

        if let Some(ref inclusion_conditions) = condition.conditions {
            if !self.matches_conditions(inclusion_conditions) {
                return false;
            }
        }

        if let Some(ref defer_condition) = condition.defer_condition {
            if !self.matches_defer(defer_condition) {
                return false;
            }
        }

        true
    }
}

// Custom PartialEq: matches Swift's == which compares scopePath and matchingTypes
impl PartialEq for ScopeDescriptor {
    fn eq(&self, other: &Self) -> bool {
        self.scope_path == other.scope_path && self.matching_types == other.matching_types
    }
}

impl Eq for ScopeDescriptor {}

// Custom Hash: matches Swift's hash(into:) which hashes scopePath and matchingTypes
impl Hash for ScopeDescriptor {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.scope_path.hash(state);
        // Hash the matching_types deterministically
        for type_ in &self.matching_types {
            type_.hash(state);
        }
        self.matching_types.len().hash(state);
    }
}

impl fmt::Display for ScopeDescriptor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.scope_path)
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    use graphql_compiler::{
        GraphQLInterfaceType, GraphQLName, GraphQLNamedType, GraphQLObjectType, GraphQLUnionType,
        RootTypeDefinition,
    };
    use indexmap::IndexMap;

    fn make_object(name: &str) -> Arc<GraphQLObjectType> {
        Arc::new(GraphQLObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
        })
    }

    fn make_object_with_interfaces(
        name: &str,
        interfaces: Vec<Arc<GraphQLInterfaceType>>,
    ) -> Arc<GraphQLObjectType> {
        Arc::new(GraphQLObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces,
            key_fields: None,
        })
    }

    fn make_interface(name: &str) -> Arc<GraphQLInterfaceType> {
        Arc::new(GraphQLInterfaceType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            fields: IndexMap::new(),
            interfaces: vec![],
            key_fields: None,
            implementing_objects: vec![],
        })
    }

    fn make_union(name: &str, types: Vec<Arc<GraphQLObjectType>>) -> Arc<GraphQLUnionType> {
        Arc::new(GraphQLUnionType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            types,
        })
    }

    fn make_root_types() -> RootTypeDefinition {
        RootTypeDefinition {
            query_type: GraphQLNamedType::Object(make_object("Query")),
            mutation_type: None,
            subscription_type: None,
        }
    }

    fn make_referenced_types(types: &[GraphQLNamedType]) -> Arc<ReferencedTypes> {
        Arc::new(ReferencedTypes::new(types, make_root_types()))
    }

    // -- ScopeCondition tests --

    #[test]
    fn scope_condition_is_empty_when_all_none() {
        let sc = ScopeCondition::new(None, None, None);
        assert!(sc.is_empty());
    }

    #[test]
    fn scope_condition_not_empty_with_type() {
        let obj = make_object("User");
        let sc = ScopeCondition::with_type(GraphQLCompositeType::Object(obj));
        assert!(!sc.is_empty());
    }

    #[test]
    fn scope_condition_is_deferred_with_defer_condition() {
        let sc = ScopeCondition::new(
            None,
            None,
            Some(DeferCondition {
                label: "deferred".to_string(),
                variable: None,
            }),
        );
        assert!(sc.is_deferred());
    }

    #[test]
    fn scope_condition_not_deferred_without_defer() {
        let sc = ScopeCondition::new(None, None, None);
        assert!(!sc.is_deferred());
    }

    // -- ScopeDescriptor tests --

    #[test]
    fn descriptor_creates_initial_scope() {
        let obj = make_object("Query");
        let obj_type = GraphQLCompositeType::Object(Arc::clone(&obj));
        let all_types = make_referenced_types(&[GraphQLNamedType::Object(Arc::clone(&obj))]);

        let desc = ScopeDescriptor::descriptor(&obj_type, None, &all_types);

        assert_eq!(desc.type_, obj_type);
        assert!(desc.matching_types.contains(&obj_type));
        assert!(desc.matching_conditions.is_none());
        assert_eq!(desc.scope_path.count(), 1);
    }

    #[test]
    fn descriptor_matches_own_type() {
        let obj = make_object("User");
        let obj_type = GraphQLCompositeType::Object(Arc::clone(&obj));
        let all_types = make_referenced_types(&[GraphQLNamedType::Object(Arc::clone(&obj))]);

        let desc = ScopeDescriptor::descriptor(&obj_type, None, &all_types);
        assert!(desc.matches(&obj_type));
    }

    #[test]
    fn descriptor_does_not_match_unrelated_type() {
        let user = make_object("User");
        let post = make_object("Post");
        let user_type = GraphQLCompositeType::Object(Arc::clone(&user));
        let post_type = GraphQLCompositeType::Object(Arc::clone(&post));
        let all_types = make_referenced_types(&[
            GraphQLNamedType::Object(Arc::clone(&user)),
            GraphQLNamedType::Object(Arc::clone(&post)),
        ]);

        let desc = ScopeDescriptor::descriptor(&user_type, None, &all_types);
        assert!(!desc.matches(&post_type));
    }

    #[test]
    fn descriptor_matches_implemented_interface() {
        let node = make_interface("Node");
        let user = make_object_with_interfaces("User", vec![Arc::clone(&node)]);
        let user_type = GraphQLCompositeType::Object(Arc::clone(&user));
        let node_type = GraphQLCompositeType::Interface(Arc::clone(&node));

        let all_types = make_referenced_types(&[
            GraphQLNamedType::Object(Arc::clone(&user)),
            GraphQLNamedType::Interface(Arc::clone(&node)),
        ]);

        let desc = ScopeDescriptor::descriptor(&user_type, None, &all_types);
        assert!(desc.matches(&user_type));
        assert!(desc.matches(&node_type));
    }

    #[test]
    fn descriptor_matches_containing_union() {
        let user = make_object("User");
        let search_result = make_union("SearchResult", vec![Arc::clone(&user)]);
        let user_type = GraphQLCompositeType::Object(Arc::clone(&user));
        let union_type = GraphQLCompositeType::Union(Arc::clone(&search_result));

        let all_types = make_referenced_types(&[
            GraphQLNamedType::Object(Arc::clone(&user)),
            GraphQLNamedType::Union(Arc::clone(&search_result)),
        ]);

        let desc = ScopeDescriptor::descriptor(&user_type, None, &all_types);
        assert!(desc.matches(&user_type));
        assert!(desc.matches(&union_type));
    }

    #[test]
    fn appending_type_extends_scope_path() {
        let user = make_object("User");
        let admin = make_object("Admin");
        let user_type = GraphQLCompositeType::Object(Arc::clone(&user));
        let admin_type = GraphQLCompositeType::Object(Arc::clone(&admin));

        let all_types = make_referenced_types(&[
            GraphQLNamedType::Object(Arc::clone(&user)),
            GraphQLNamedType::Object(Arc::clone(&admin)),
        ]);

        let desc = ScopeDescriptor::descriptor(&user_type, None, &all_types);
        let appended = desc.appending_type(admin_type.clone());

        assert_eq!(appended.scope_path.count(), 2);
        assert_eq!(appended.type_, admin_type);
        assert!(appended.matches(&user_type));
        assert!(appended.matches(&admin_type));
    }

    #[test]
    fn appending_conditions_preserves_type() {
        let user = make_object("User");
        let user_type = GraphQLCompositeType::Object(Arc::clone(&user));

        let all_types = make_referenced_types(&[GraphQLNamedType::Object(Arc::clone(&user))]);

        let desc = ScopeDescriptor::descriptor(&user_type, None, &all_types);
        let cond = crate::inclusion_conditions::InclusionConditions::new(
            crate::inclusion_conditions::InclusionCondition::include_if("flag".to_string()),
        );
        let appended = desc.appending_conditions(cond);

        assert_eq!(appended.type_, user_type);
        assert!(appended.matching_conditions.is_some());
        assert_eq!(appended.scope_path.count(), 2);
    }

    #[test]
    fn matches_scope_condition_with_type() {
        let user = make_object("User");
        let user_type = GraphQLCompositeType::Object(Arc::clone(&user));

        let all_types = make_referenced_types(&[GraphQLNamedType::Object(Arc::clone(&user))]);

        let desc = ScopeDescriptor::descriptor(&user_type, None, &all_types);
        let sc = ScopeCondition::with_type(user_type);
        assert!(desc.matches_scope_condition(&sc));
    }

    #[test]
    fn matches_scope_condition_with_unknown_type_fails() {
        let user = make_object("User");
        let post = make_object("Post");
        let user_type = GraphQLCompositeType::Object(Arc::clone(&user));
        let post_type = GraphQLCompositeType::Object(Arc::clone(&post));

        let all_types = make_referenced_types(&[
            GraphQLNamedType::Object(Arc::clone(&user)),
            GraphQLNamedType::Object(Arc::clone(&post)),
        ]);

        let desc = ScopeDescriptor::descriptor(&user_type, None, &all_types);
        let sc = ScopeCondition::with_type(post_type);
        assert!(!desc.matches_scope_condition(&sc));
    }

    #[test]
    fn is_deferred_from_scope_path() {
        let user = make_object("User");
        let user_type = GraphQLCompositeType::Object(Arc::clone(&user));

        let all_types = make_referenced_types(&[GraphQLNamedType::Object(Arc::clone(&user))]);

        let desc = ScopeDescriptor::descriptor(&user_type, None, &all_types);
        assert!(!desc.is_deferred());

        let deferred_scope = ScopeCondition::new(
            None,
            None,
            Some(DeferCondition {
                label: "deferLabel".to_string(),
                variable: None,
            }),
        );
        let deferred_desc = desc.appending(deferred_scope);
        assert!(deferred_desc.is_deferred());
    }

    #[test]
    fn equality_based_on_scope_path_and_matching_types() {
        let user = make_object("User");
        let user_type = GraphQLCompositeType::Object(Arc::clone(&user));

        let all_types = make_referenced_types(&[GraphQLNamedType::Object(Arc::clone(&user))]);

        let desc1 = ScopeDescriptor::descriptor(&user_type, None, &all_types);
        let desc2 = ScopeDescriptor::descriptor(&user_type, None, &all_types);
        assert_eq!(desc1, desc2);
    }
}
