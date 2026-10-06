use std::fmt;
use std::sync::Arc;

use graphql_compiler::{compilation_result, Argument, GraphQLType};

use crate::entity::Entity;
use crate::inclusion_conditions::{AnyOf, InclusionConditions};
use crate::selection_set::SelectionSet;

// MARK: - Field

/// A field in an IR selection set. Uses an enum to replace Swift's class hierarchy
/// (Field -> ScalarField, EntityField).
///
/// Mirrors `IR.Field`, `IR.ScalarField`, `IR.EntityField` from `IR+Fields.swift`.
#[derive(Clone, Debug)]
pub enum Field {
    Scalar(ScalarField),
    Entity(EntityField),
}

impl Field {
    /// The name of the field.
    pub fn name(&self) -> &str {
        match self {
            Field::Scalar(f) => &f.underlying_field.name,
            Field::Entity(f) => &f.underlying_field.name,
        }
    }

    /// The alias of the field, if any.
    pub fn alias(&self) -> Option<&str> {
        match self {
            Field::Scalar(f) => f.underlying_field.alias.as_deref(),
            Field::Entity(f) => f.underlying_field.alias.as_deref(),
        }
    }

    /// The response key for this field (alias if present, otherwise name).
    pub fn response_key(&self) -> &str {
        match self {
            Field::Scalar(f) => f.underlying_field.response_key(),
            Field::Entity(f) => f.underlying_field.response_key(),
        }
    }

    /// The GraphQL type of the field.
    pub fn type_(&self) -> &GraphQLType {
        match self {
            Field::Scalar(f) => &f.underlying_field.type_,
            Field::Entity(f) => &f.underlying_field.type_,
        }
    }

    /// The arguments of the field, if any.
    pub fn arguments(&self) -> Option<&[Argument]> {
        match self {
            Field::Scalar(f) => f.underlying_field.arguments.as_deref(),
            Field::Entity(f) => f.underlying_field.arguments.as_deref(),
        }
    }

    /// The inclusion conditions of the field, if any.
    pub fn inclusion_conditions(&self) -> Option<&AnyOf<InclusionConditions>> {
        match self {
            Field::Scalar(f) => f.inclusion_conditions.as_ref(),
            Field::Entity(f) => f.inclusion_conditions.as_ref(),
        }
    }

    /// Sets the inclusion conditions of the field.
    pub fn set_inclusion_conditions(
        &mut self,
        conditions: Option<AnyOf<InclusionConditions>>,
    ) {
        match self {
            Field::Scalar(f) => f.inclusion_conditions = conditions,
            Field::Entity(f) => f.inclusion_conditions = conditions,
        }
    }

    /// Returns a reference to the underlying compilation result field.
    pub fn underlying_field(&self) -> &Arc<compilation_result::Field> {
        match self {
            Field::Scalar(f) => &f.underlying_field,
            Field::Entity(f) => &f.underlying_field,
        }
    }
}

impl PartialEq for Field {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Field::Scalar(a), Field::Scalar(b)) => a == b,
            (Field::Entity(a), Field::Entity(b)) => a == b,
            _ => false,
        }
    }
}

impl Eq for Field {}

impl fmt::Display for Field {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let name = self.name();
        let type_ = self.type_();
        write!(f, "{}: {}", name, type_)?;
        if let Some(conditions) = self.inclusion_conditions() {
            write!(f, " {}", conditions)?;
        }
        Ok(())
    }
}

// MARK: - ScalarField

/// A field that resolves to a scalar value.
///
/// Mirrors `IR.ScalarField` from `IR+Fields.swift`.
#[derive(Clone, Debug)]
pub struct ScalarField {
    pub underlying_field: Arc<compilation_result::Field>,
    pub inclusion_conditions: Option<AnyOf<InclusionConditions>>,
}

impl ScalarField {
    pub fn new(
        field: Arc<compilation_result::Field>,
        inclusion_conditions: Option<AnyOf<InclusionConditions>>,
    ) -> Self {
        ScalarField {
            underlying_field: field,
            inclusion_conditions,
        }
    }
}

impl PartialEq for ScalarField {
    fn eq(&self, other: &Self) -> bool {
        *self.underlying_field == *other.underlying_field
            && self.inclusion_conditions == other.inclusion_conditions
    }
}

impl Eq for ScalarField {}

// MARK: - EntityField

/// A field that resolves to a composite type with a selection set.
///
/// Mirrors `IR.EntityField` from `IR+Fields.swift`.
#[derive(Clone, Debug)]
pub struct EntityField {
    pub underlying_field: Arc<compilation_result::Field>,
    pub inclusion_conditions: Option<AnyOf<InclusionConditions>>,
    pub selection_set: Arc<SelectionSet>,
}

impl EntityField {
    pub fn new(
        field: Arc<compilation_result::Field>,
        inclusion_conditions: Option<AnyOf<InclusionConditions>>,
        selection_set: Arc<SelectionSet>,
    ) -> Self {
        EntityField {
            underlying_field: field,
            inclusion_conditions,
            selection_set,
        }
    }

    /// The entity that this field's selection set selects on.
    pub fn entity(&self) -> &Arc<Entity> {
        &self.selection_set.type_info.entity
    }
}

impl PartialEq for EntityField {
    fn eq(&self, other: &Self) -> bool {
        *self.underlying_field == *other.underlying_field
            && self.inclusion_conditions == other.inclusion_conditions
            && self.selection_set == other.selection_set
    }
}

impl Eq for EntityField {}
