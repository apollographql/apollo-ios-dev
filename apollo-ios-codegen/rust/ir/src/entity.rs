use std::fmt;
use std::sync::{Arc, RwLock};

use graphql_compiler::{
    compilation_result, GraphQLCompositeType, GraphQLType,
};
use utilities::linked_list::LinkedList;

use crate::entity_selection_tree::EntitySelectionTree;

// MARK: - Entity

/// Represents a concrete entity in an operation or fragment that fields are selected upon.
///
/// Multiple `SelectionSet`s may select fields on the same `Entity`. All `SelectionSet`s that will
/// be selected on the same object share the same `Entity`.
///
/// Mirrors `IR.Entity` from `IR+Entity.swift`.
pub struct Entity {
    /// The selections that are selected for the entity across all type scopes in the operation.
    /// Represented as a tree.
    /// Wrapped in RwLock per D-30 to allow mutation through Arc during IR construction.
    pub(crate) selection_tree: RwLock<EntitySelectionTree>,

    /// The path of root types from the definition root to this entity.
    /// Stored separately from selection_tree because root_type_path is immutable
    /// after construction and accessed frequently without needing a lock.
    pub(crate) root_type_path: LinkedList<GraphQLCompositeType>,

    /// The location within a GraphQL definition (operation or fragment) where the `Entity` is
    /// located.
    pub location: Location,
}

impl fmt::Debug for Entity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Entity")
            .field("root_type_path", &self.root_type_path)
            .field("location", &self.location)
            .finish()
    }
}

impl Entity {
    /// Creates a root entity from a source definition (operation or fragment).
    pub fn new_root(source: SourceDefinition) -> Self {
        let root_type = source.root_type().clone();
        let root_type_path = LinkedList::new(root_type);
        Entity {
            location: Location {
                source,
                field_path: None,
            },
            selection_tree: RwLock::new(EntitySelectionTree::new(root_type_path.clone())),
            root_type_path,
        }
    }

    /// Creates an entity at a specific location with a given root type path.
    pub(crate) fn new(location: Location, root_type_path: LinkedList<GraphQLCompositeType>) -> Self {
        Entity {
            location,
            selection_tree: RwLock::new(EntitySelectionTree::new(root_type_path.clone())),
            root_type_path,
        }
    }

    /// The path of root types from the definition root to this entity.
    pub fn root_type_path(&self) -> &LinkedList<GraphQLCompositeType> {
        &self.root_type_path
    }

    /// The root type of this entity (the last element of root_type_path).
    pub fn root_type(&self) -> &GraphQLCompositeType {
        self.root_type_path.last()
    }
}

// MARK: - Location

/// Represents the location within a GraphQL definition (operation or fragment) of an `Entity`.
///
/// Mirrors `Entity.Location` from `IR+Entity.swift`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Location {
    /// The operation or fragment definition that the entity belongs to.
    pub source: SourceDefinition,

    /// The path of fields from the root of the `source` definition to the entity.
    ///
    /// Example:
    /// For an operation:
    /// ```graphql
    /// query MyQuery {
    ///   allAnimals {
    ///     predators {
    ///       height {
    ///         ...
    ///       }
    ///     }
    ///   }
    /// }
    /// ```
    /// The `Height` entity would have a field path of [allAnimals, predators, height].
    pub field_path: Option<LinkedList<FieldComponent>>,
}

impl Location {
    /// Returns a new location with the given field component appended.
    pub fn appending(&self, field_component: FieldComponent) -> Location {
        let field_path = match &self.field_path {
            Some(path) => path.appending(field_component),
            None => LinkedList::new(field_component),
        };
        Location {
            source: self.source.clone(),
            field_path: Some(field_path),
        }
    }

    /// Returns a new location with all given field components appended.
    pub fn appending_path(&self, components: impl IntoIterator<Item = FieldComponent>) -> Location {
        let components: Vec<FieldComponent> = components.into_iter().collect();
        if components.is_empty() {
            return self.clone();
        }
        let field_path = match &self.field_path {
            Some(path) => path.appending_sequence(components),
            None => LinkedList::from_collection(components),
        };
        Location {
            source: self.source.clone(),
            field_path: Some(field_path),
        }
    }
}

impl std::ops::Add<FieldComponent> for &Location {
    type Output = Location;

    fn add(self, rhs: FieldComponent) -> Self::Output {
        self.appending(rhs)
    }
}

// MARK: - SourceDefinition

/// The source definition (operation or fragment) that an entity belongs to.
///
/// Mirrors `Entity.Location.SourceDefinition` from `IR+Entity.swift`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum SourceDefinition {
    Operation(Arc<compilation_result::OperationDefinition>),
    NamedFragment(Arc<compilation_result::FragmentDefinition>),
}

impl SourceDefinition {
    /// Returns the root type of the source definition.
    pub fn root_type(&self) -> &GraphQLCompositeType {
        match self {
            SourceDefinition::Operation(def) => &def.root_type,
            SourceDefinition::NamedFragment(def) => &def.type_,
        }
    }
}

impl fmt::Display for SourceDefinition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SourceDefinition::Operation(def) => write!(f, "Operation({})", def.name),
            SourceDefinition::NamedFragment(def) => write!(f, "NamedFragment({})", def.name),
        }
    }
}

// MARK: - FieldComponent

/// A component of the field path, representing a field name and its type.
///
/// Mirrors `Entity.Location.FieldComponent` from `IR+Entity.swift`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct FieldComponent {
    pub name: String,
    pub type_: GraphQLType,
}

impl FieldComponent {
    pub fn new(name: String, type_: GraphQLType) -> Self {
        FieldComponent { name, type_ }
    }
}

/// Type alias for the field path, matching Swift's `Entity.Location.FieldPath`.
pub type FieldPath = LinkedList<FieldComponent>;
