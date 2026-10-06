use std::fmt;
use std::hash::{Hash, Hasher};

use indexmap::IndexSet;

use graphql_compiler::compilation_result;

// MARK: - InclusionCondition

/// A condition representing an `@include` or `@skip` directive to determine if a field
/// or fragment should be included.
///
/// Mirrors `IR.InclusionCondition` from `IR+InclusionConditions.swift`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct InclusionCondition {
    /// The name of variable used to determine if the inclusion condition is met.
    pub variable: String,

    /// If `is_inverted` is `true`, this condition represents a `@skip` directive and is included
    /// if the variable resolves to `false`.
    pub is_inverted: bool,
}

impl InclusionCondition {
    pub fn new(variable: String, is_inverted: bool) -> Self {
        InclusionCondition {
            variable,
            is_inverted,
        }
    }

    /// Creates an `InclusionCondition` representing an `@include` directive.
    pub fn include_if(variable: String) -> InclusionCondition {
        InclusionCondition::new(variable, false)
    }

    /// Creates an `InclusionCondition` representing a `@skip` directive.
    pub fn skip_if(variable: String) -> InclusionCondition {
        InclusionCondition::new(variable, true)
    }

    /// Returns a new condition with the `is_inverted` flag flipped.
    pub fn inverted(&self) -> InclusionCondition {
        InclusionCondition {
            variable: self.variable.clone(),
            is_inverted: !self.is_inverted,
        }
    }
}

impl fmt::Display for InclusionCondition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.is_inverted {
            write!(f, "@skip(if: ${})", self.variable)
        } else {
            write!(f, "@include(if: ${})", self.variable)
        }
    }
}

// MARK: - InclusionConditions

/// A set of inclusion conditions that must all be met (AND semantics).
///
/// Mirrors `IR.InclusionConditions` (Collection) from `IR+InclusionConditions.swift`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InclusionConditions {
    conditions: IndexSet<InclusionCondition>,
}

impl Hash for InclusionConditions {
    fn hash<H: Hasher>(&self, state: &mut H) {
        // Hash each element in order for deterministic hashing
        for condition in &self.conditions {
            condition.hash(state);
        }
        self.conditions.len().hash(state);
    }
}

impl InclusionConditions {
    pub fn new(condition: InclusionCondition) -> Self {
        let mut conditions = IndexSet::new();
        conditions.insert(condition);
        InclusionConditions { conditions }
    }

    fn from_set(conditions: IndexSet<InclusionCondition>) -> Self {
        InclusionConditions { conditions }
    }

    /// Returns `true` if the given condition is contained in this set.
    pub fn contains(&self, condition: &InclusionCondition) -> bool {
        self.conditions.contains(condition)
    }

    /// Appends a condition to the set (mutating).
    pub fn append(&mut self, condition: InclusionCondition) {
        self.conditions.insert(condition);
    }

    /// Returns a new `InclusionConditions` with the given condition appended.
    pub fn appending(&self, condition: InclusionCondition) -> InclusionConditions {
        let mut conditions = self.conditions.clone();
        conditions.insert(condition);
        InclusionConditions::from_set(conditions)
    }

    /// Appends all conditions from another `InclusionConditions` (mutating).
    pub(crate) fn append_conditions(&mut self, other: &InclusionConditions) {
        for condition in &other.conditions {
            self.conditions.insert(condition.clone());
        }
    }

    /// Returns a new `InclusionConditions` with all conditions from `other` appended.
    pub fn appending_conditions(&self, other: &InclusionConditions) -> InclusionConditions {
        let mut conditions = self.conditions.clone();
        for condition in &other.conditions {
            conditions.insert(condition.clone());
        }
        InclusionConditions::from_set(conditions)
    }

    /// Returns `true` if all conditions in `self` are contained in `other`.
    pub fn is_subset_of(&self, other: Option<&InclusionConditions>) -> bool {
        match other {
            Some(other) => self.conditions.is_subset(&other.conditions),
            None => self.conditions.is_empty(),
        }
    }

    /// Returns the number of conditions in the set.
    pub fn len(&self) -> usize {
        self.conditions.len()
    }

    /// Returns `true` if the set is empty.
    pub fn is_empty(&self) -> bool {
        self.conditions.is_empty()
    }

    /// Returns an iterator over the conditions.
    pub fn iter(&self) -> indexmap::set::Iter<'_, InclusionCondition> {
        self.conditions.iter()
    }

    /// Returns the condition at the given index.
    pub fn get_index(&self, index: usize) -> Option<&InclusionCondition> {
        self.conditions.get_index(index)
    }

    /// Computes `self && rhs` producing an `InclusionResult`.
    pub fn and_condition(&self, rhs: &InclusionCondition) -> InclusionResult {
        InclusionResult::Conditional(self.clone()).and_condition(rhs)
    }
}

impl fmt::Display for InclusionConditions {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let descriptions: Vec<String> = self.conditions.iter().map(|c| c.to_string()).collect();
        write!(f, "{}", descriptions.join(" && "))
    }
}

impl<'a> IntoIterator for &'a InclusionConditions {
    type Item = &'a InclusionCondition;
    type IntoIter = indexmap::set::Iter<'a, InclusionCondition>;

    fn into_iter(self) -> Self::IntoIter {
        self.conditions.iter()
    }
}

// MARK: - InclusionResult

/// The result of combining inclusion conditions with AND semantics.
///
/// Mirrors `IR.InclusionConditions.Result` from `IR+InclusionConditions.swift`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum InclusionResult {
    /// Always included (unconditional).
    Included,
    /// Always skipped.
    Skipped,
    /// Conditionally included based on the given conditions.
    Conditional(InclusionConditions),
}

impl InclusionResult {
    /// Returns the conditions if this is the `Conditional` variant, `None` otherwise.
    pub fn conditions(&self) -> Option<&InclusionConditions> {
        match self {
            InclusionResult::Conditional(conditions) => Some(conditions),
            _ => None,
        }
    }

    /// Computes `allOf` from a sequence of `InclusionCondition` (IR-level).
    ///
    /// Iterates conditions applying `&&` logic: starts as `Included`, folds each condition.
    pub fn all_of_ir(conditions: impl IntoIterator<Item = InclusionCondition>) -> Self {
        let mut result = InclusionResult::Included;
        for condition in conditions {
            result = result.and_condition(&condition);
        }
        result
    }

    /// Computes `allOf` from a sequence of `CompilationResult.InclusionCondition`.
    ///
    /// Iterates conditions applying `&&` logic, converting from compilation-result types.
    pub fn all_of_compilation(
        conditions: impl IntoIterator<Item = compilation_result::InclusionCondition>,
    ) -> Self {
        let mut result = InclusionResult::Included;
        for condition in conditions {
            result = result.and_compilation_condition(&condition);
        }
        result
    }

    /// Applies `&&` with a compilation-result inclusion condition.
    ///
    /// Converts the compilation-result condition to an IR condition and delegates.
    pub fn and_compilation_condition(
        self,
        rhs: &compilation_result::InclusionCondition,
    ) -> Self {
        match rhs {
            compilation_result::InclusionCondition::Skipped => InclusionResult::Skipped,
            compilation_result::InclusionCondition::Included => self,
            compilation_result::InclusionCondition::Variable { name, is_inverted } => {
                let new_condition = InclusionCondition::new(name.clone(), *is_inverted);
                self.and_condition(&new_condition)
            }
        }
    }

    /// Applies `&&` with an IR inclusion condition.
    ///
    /// - `Skipped && anything = Skipped`
    /// - `Included && rhs = Conditional([rhs])`
    /// - `Conditional(conds) && rhs`:
    ///   - If `conds` contains `rhs.inverted()`, both include(x) and skip(x) are present,
    ///     so the result is always `Skipped`.
    ///   - Otherwise, append `rhs` to `conds`.
    pub fn and_condition(self, rhs: &InclusionCondition) -> Self {
        match self {
            InclusionResult::Skipped => InclusionResult::Skipped,
            InclusionResult::Included => {
                InclusionResult::Conditional(InclusionConditions::new(rhs.clone()))
            }
            InclusionResult::Conditional(mut conditions) => {
                // If both an include & skip exist with the same variable, the result
                // is always skipped.
                if conditions.contains(&rhs.inverted()) {
                    return InclusionResult::Skipped;
                }
                conditions.append(rhs.clone());
                InclusionResult::Conditional(conditions)
            }
        }
    }
}

// MARK: - AnyOf

/// A set of elements where at least one must be satisfied (OR semantics).
///
/// Mirrors `AnyOf<T>` from `IR+InclusionConditions.swift`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AnyOf<T: Hash + Eq> {
    pub elements: IndexSet<T>,
}

impl<T: Hash + Eq> Hash for AnyOf<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        for element in &self.elements {
            element.hash(state);
        }
        self.elements.len().hash(state);
    }
}

impl<T: Hash + Eq> AnyOf<T> {
    /// Creates an `AnyOf` with a single element.
    pub fn new(element: T) -> Self {
        let mut elements = IndexSet::new();
        elements.insert(element);
        AnyOf { elements }
    }

    /// Creates an `AnyOf` from an optional element. Returns `None` if the element is `None`.
    pub fn from_option(element: Option<T>) -> Option<Self> {
        element.map(Self::new)
    }

    /// Creates an `AnyOf` from an iterator of elements.
    pub fn from_iter(elements: impl IntoIterator<Item = T>) -> Self {
        AnyOf {
            elements: elements.into_iter().collect(),
        }
    }
}

impl<T: Hash + Eq + Clone> AnyOf<T> {
    /// Appends all elements from `other` into this set.
    pub fn append_contents_of(&mut self, other: &AnyOf<T>) {
        for element in &other.elements {
            self.elements.insert(element.clone());
        }
    }
}

impl AnyOf<InclusionConditions> {
    /// Creates an `AnyOf<InclusionConditions>` from a single `InclusionCondition`.
    pub fn from_condition(condition: InclusionCondition) -> Self {
        AnyOf::new(InclusionConditions::new(condition))
    }
}

impl<T: Hash + Eq + fmt::Display> fmt::Display for AnyOf<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let wrap_in_parens = self.elements.len() > 1;
        for (i, element) in self.elements.iter().enumerate() {
            if i > 0 {
                write!(f, " || ")?;
            }
            if wrap_in_parens {
                write!(f, "({})", element)?;
            } else {
                write!(f, "{}", element)?;
            }
        }
        Ok(())
    }
}

// MARK: - any_of_or free function

/// Implements the `||` operator for `Option<AnyOf<InclusionConditions>>`.
///
/// Returns `None` if either side is `None` (unconditional), otherwise merges elements.
pub fn any_of_or(
    lhs: Option<AnyOf<InclusionConditions>>,
    rhs: Option<AnyOf<InclusionConditions>>,
) -> Option<AnyOf<InclusionConditions>> {
    match (lhs, rhs) {
        (Some(mut lhs), Some(rhs)) => {
            lhs.append_contents_of(&rhs);
            Some(lhs)
        }
        _ => None,
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;

    // -- InclusionCondition tests --

    #[test]
    fn include_if_creates_non_inverted_condition() {
        let condition = InclusionCondition::include_if("isAdmin".to_string());
        assert_eq!(condition.variable, "isAdmin");
        assert!(!condition.is_inverted);
    }

    #[test]
    fn skip_if_creates_inverted_condition() {
        let condition = InclusionCondition::skip_if("isHidden".to_string());
        assert_eq!(condition.variable, "isHidden");
        assert!(condition.is_inverted);
    }

    #[test]
    fn inverted_flips_is_inverted() {
        let include = InclusionCondition::include_if("flag".to_string());
        let skip = include.inverted();
        assert!(skip.is_inverted);
        assert_eq!(skip.variable, "flag");

        let back = skip.inverted();
        assert!(!back.is_inverted);
    }

    #[test]
    fn display_formats_include_correctly() {
        let condition = InclusionCondition::include_if("showField".to_string());
        assert_eq!(condition.to_string(), "@include(if: $showField)");
    }

    #[test]
    fn display_formats_skip_correctly() {
        let condition = InclusionCondition::skip_if("hideField".to_string());
        assert_eq!(condition.to_string(), "@skip(if: $hideField)");
    }

    #[test]
    fn equality_by_variable_and_inverted() {
        let a = InclusionCondition::include_if("x".to_string());
        let b = InclusionCondition::include_if("x".to_string());
        let c = InclusionCondition::skip_if("x".to_string());
        assert_eq!(a, b);
        assert_ne!(a, c);
    }

    // -- InclusionConditions tests --

    #[test]
    fn conditions_new_creates_single_element_set() {
        let cond = InclusionCondition::include_if("a".to_string());
        let conditions = InclusionConditions::new(cond.clone());
        assert_eq!(conditions.len(), 1);
        assert!(conditions.contains(&cond));
    }

    #[test]
    fn conditions_append_adds_condition() {
        let mut conditions = InclusionConditions::new(InclusionCondition::include_if("a".to_string()));
        conditions.append(InclusionCondition::skip_if("b".to_string()));
        assert_eq!(conditions.len(), 2);
    }

    #[test]
    fn conditions_appending_returns_new_set() {
        let conditions = InclusionConditions::new(InclusionCondition::include_if("a".to_string()));
        let new_conditions = conditions.appending(InclusionCondition::skip_if("b".to_string()));
        assert_eq!(conditions.len(), 1);
        assert_eq!(new_conditions.len(), 2);
    }

    #[test]
    fn conditions_is_subset_of_some() {
        let a = InclusionConditions::new(InclusionCondition::include_if("x".to_string()));
        let mut b = InclusionConditions::new(InclusionCondition::include_if("x".to_string()));
        b.append(InclusionCondition::include_if("y".to_string()));
        assert!(a.is_subset_of(Some(&b)));
        assert!(!b.is_subset_of(Some(&a)));
    }

    #[test]
    fn conditions_is_subset_of_none() {
        let empty_conditions = InclusionConditions::from_set(IndexSet::new());
        assert!(empty_conditions.is_subset_of(None));

        let non_empty = InclusionConditions::new(InclusionCondition::include_if("x".to_string()));
        assert!(!non_empty.is_subset_of(None));
    }

    #[test]
    fn conditions_display() {
        let mut conditions = InclusionConditions::new(InclusionCondition::include_if("a".to_string()));
        conditions.append(InclusionCondition::skip_if("b".to_string()));
        assert_eq!(conditions.to_string(), "@include(if: $a) && @skip(if: $b)");
    }

    // -- InclusionResult tests --

    #[test]
    fn all_of_ir_with_empty_iter_returns_included() {
        let result = InclusionResult::all_of_ir(std::iter::empty());
        assert_eq!(result, InclusionResult::Included);
    }

    #[test]
    fn all_of_ir_with_one_variable_returns_conditional() {
        let result = InclusionResult::all_of_ir(
            vec![InclusionCondition::include_if("x".to_string())],
        );
        match &result {
            InclusionResult::Conditional(conds) => {
                assert_eq!(conds.len(), 1);
                assert!(conds.contains(&InclusionCondition::include_if("x".to_string())));
            }
            _ => panic!("Expected Conditional, got {:?}", result),
        }
    }

    #[test]
    fn all_of_ir_with_contradicting_conditions_returns_skipped() {
        let result = InclusionResult::all_of_ir(vec![
            InclusionCondition::include_if("x".to_string()),
            InclusionCondition::skip_if("x".to_string()),
        ]);
        assert_eq!(result, InclusionResult::Skipped);
    }

    #[test]
    fn all_of_ir_with_multiple_non_contradicting() {
        let result = InclusionResult::all_of_ir(vec![
            InclusionCondition::include_if("a".to_string()),
            InclusionCondition::include_if("b".to_string()),
        ]);
        match &result {
            InclusionResult::Conditional(conds) => {
                assert_eq!(conds.len(), 2);
            }
            _ => panic!("Expected Conditional, got {:?}", result),
        }
    }

    #[test]
    fn and_condition_skipped_stays_skipped() {
        let result = InclusionResult::Skipped.and_condition(
            &InclusionCondition::include_if("x".to_string()),
        );
        assert_eq!(result, InclusionResult::Skipped);
    }

    #[test]
    fn and_condition_included_becomes_conditional() {
        let result = InclusionResult::Included.and_condition(
            &InclusionCondition::include_if("x".to_string()),
        );
        match &result {
            InclusionResult::Conditional(conds) => {
                assert_eq!(conds.len(), 1);
            }
            _ => panic!("Expected Conditional, got {:?}", result),
        }
    }

    #[test]
    fn result_conditions_returns_none_for_included() {
        assert!(InclusionResult::Included.conditions().is_none());
    }

    #[test]
    fn result_conditions_returns_none_for_skipped() {
        assert!(InclusionResult::Skipped.conditions().is_none());
    }

    #[test]
    fn result_conditions_returns_some_for_conditional() {
        let result = InclusionResult::Conditional(
            InclusionConditions::new(InclusionCondition::include_if("x".to_string())),
        );
        assert!(result.conditions().is_some());
    }

    // -- all_of_compilation tests --

    #[test]
    fn all_of_compilation_with_included_returns_included() {
        let result = InclusionResult::all_of_compilation(
            vec![compilation_result::InclusionCondition::Included],
        );
        assert_eq!(result, InclusionResult::Included);
    }

    #[test]
    fn all_of_compilation_with_skipped_returns_skipped() {
        let result = InclusionResult::all_of_compilation(
            vec![compilation_result::InclusionCondition::Skipped],
        );
        assert_eq!(result, InclusionResult::Skipped);
    }

    #[test]
    fn all_of_compilation_with_variable_returns_conditional() {
        let result = InclusionResult::all_of_compilation(vec![
            compilation_result::InclusionCondition::Variable {
                name: "flag".to_string(),
                is_inverted: false,
            },
        ]);
        match &result {
            InclusionResult::Conditional(conds) => {
                assert_eq!(conds.len(), 1);
                assert!(conds.contains(&InclusionCondition::include_if("flag".to_string())));
            }
            _ => panic!("Expected Conditional, got {:?}", result),
        }
    }

    #[test]
    fn all_of_compilation_mixed_included_and_variable() {
        let result = InclusionResult::all_of_compilation(vec![
            compilation_result::InclusionCondition::Included,
            compilation_result::InclusionCondition::Variable {
                name: "x".to_string(),
                is_inverted: true,
            },
        ]);
        match &result {
            InclusionResult::Conditional(conds) => {
                assert_eq!(conds.len(), 1);
                assert!(conds.contains(&InclusionCondition::skip_if("x".to_string())));
            }
            _ => panic!("Expected Conditional, got {:?}", result),
        }
    }

    // -- AnyOf tests --

    #[test]
    fn any_of_single_element() {
        let any = AnyOf::new(42);
        assert_eq!(any.elements.len(), 1);
        assert!(any.elements.contains(&42));
    }

    #[test]
    fn any_of_from_option_some() {
        let any = AnyOf::from_option(Some(42));
        assert!(any.is_some());
        assert_eq!(any.unwrap().elements.len(), 1);
    }

    #[test]
    fn any_of_from_option_none() {
        let any: Option<AnyOf<i32>> = AnyOf::from_option(None);
        assert!(any.is_none());
    }

    #[test]
    fn any_of_from_iter_multiple() {
        let any = AnyOf::from_iter(vec![1, 2, 3]);
        assert_eq!(any.elements.len(), 3);
    }

    #[test]
    fn any_of_append_contents_of() {
        let mut a = AnyOf::new(1);
        let b = AnyOf::from_iter(vec![2, 3]);
        a.append_contents_of(&b);
        assert_eq!(a.elements.len(), 3);
    }

    #[test]
    fn any_of_from_condition() {
        let any = AnyOf::from_condition(InclusionCondition::include_if("x".to_string()));
        assert_eq!(any.elements.len(), 1);
    }

    // -- any_of_or tests --

    #[test]
    fn any_of_or_none_lhs_returns_none() {
        let rhs = Some(AnyOf::new(
            InclusionConditions::new(InclusionCondition::include_if("x".to_string())),
        ));
        assert!(any_of_or(None, rhs).is_none());
    }

    #[test]
    fn any_of_or_none_rhs_returns_none() {
        let lhs = Some(AnyOf::new(
            InclusionConditions::new(InclusionCondition::include_if("x".to_string())),
        ));
        assert!(any_of_or(lhs, None).is_none());
    }

    #[test]
    fn any_of_or_both_some_merges() {
        let lhs = Some(AnyOf::new(
            InclusionConditions::new(InclusionCondition::include_if("a".to_string())),
        ));
        let rhs = Some(AnyOf::new(
            InclusionConditions::new(InclusionCondition::include_if("b".to_string())),
        ));
        let result = any_of_or(lhs, rhs);
        assert!(result.is_some());
        assert_eq!(result.unwrap().elements.len(), 2);
    }

    #[test]
    fn any_of_or_both_none_returns_none() {
        assert!(any_of_or(None, None).is_none());
    }
}
