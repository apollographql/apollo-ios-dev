use std::fmt;
use std::sync::Arc;

use indexmap::{IndexMap, IndexSet};

use graphql_compiler::{
    GraphQLEnumType, GraphQLInputObjectType, GraphQLInterfaceType, GraphQLNamedType,
    GraphQLObjectType, GraphQLScalarType, GraphQLUnionType, RootTypeDefinition,
};

// MARK: - Schema

/// A schema that holds the categorized referenced types and optional documentation.
///
/// Mirrors `IR.Schema` from `IR+Schema.swift`.
#[derive(Debug)]
pub struct Schema {
    pub referenced_types: Arc<ReferencedTypes>,
    pub documentation: Option<String>,
}

impl Schema {
    pub fn new(referenced_types: Arc<ReferencedTypes>, documentation: Option<String>) -> Self {
        Schema {
            referenced_types,
            documentation,
        }
    }
}

// MARK: - ReferencedTypes

/// Categorized collections of all types referenced in a GraphQL schema.
///
/// Mirrors `Schema.ReferencedTypes` from `IR+Schema.swift`.
pub struct ReferencedTypes {
    pub all_types: IndexSet<GraphQLNamedType>,
    pub schema_root_types: RootTypeDefinition,

    pub objects: IndexSet<Arc<GraphQLObjectType>>,
    pub interfaces: IndexSet<Arc<GraphQLInterfaceType>>,
    pub unions: IndexSet<Arc<GraphQLUnionType>>,
    pub scalars: IndexSet<Arc<GraphQLScalarType>>,
    pub custom_scalars: IndexSet<Arc<GraphQLScalarType>>,
    pub enums: IndexSet<Arc<GraphQLEnumType>>,
    pub input_objects: IndexSet<Arc<GraphQLInputObjectType>>,

    type_to_union_map: IndexMap<Arc<GraphQLObjectType>, IndexSet<Arc<GraphQLUnionType>>>,
}

impl ReferencedTypes {
    /// Creates a new `ReferencedTypes` by categorizing the given types.
    ///
    /// Mirrors the Swift initializer that categorizes types by variant and builds
    /// the type-to-union map.
    pub fn new(types: &[GraphQLNamedType], schema_root_types: RootTypeDefinition) -> Self {
        // Ensure allTypes is stable (mirrors Swift's sorted(by: { $0.name.schemaName < $1.name.schemaName }))
        let mut sorted_types = types.to_vec();
        sorted_types.sort_by(|a, b| a.name().schema_name.cmp(&b.name().schema_name));
        let all_types: IndexSet<GraphQLNamedType> = sorted_types.into_iter().collect();

        let mut objects = IndexSet::new();
        let mut interfaces = IndexSet::new();
        let mut unions = IndexSet::new();
        let mut scalars = IndexSet::new();
        let mut custom_scalars = IndexSet::new();
        let mut enums = IndexSet::new();
        let mut input_objects = IndexSet::new();

        for type_ in &all_types {
            match type_ {
                GraphQLNamedType::Object(t) => {
                    objects.insert(Arc::clone(t));
                }
                GraphQLNamedType::Interface(t) => {
                    interfaces.insert(Arc::clone(t));
                }
                GraphQLNamedType::Union(t) => {
                    unions.insert(Arc::clone(t));
                }
                GraphQLNamedType::Scalar(t) => {
                    if t.is_custom_scalar() {
                        custom_scalars.insert(Arc::clone(t));
                    } else {
                        scalars.insert(Arc::clone(t));
                    }
                }
                GraphQLNamedType::Enum(t) => {
                    enums.insert(Arc::clone(t));
                }
                GraphQLNamedType::InputObject(t) => {
                    input_objects.insert(Arc::clone(t));
                }
            }
        }

        // Build the type-to-union map: for each object, find all unions that include it
        let mut type_to_union_map: IndexMap<Arc<GraphQLObjectType>, IndexSet<Arc<GraphQLUnionType>>> =
            IndexMap::new();
        for obj in &objects {
            let containing_unions: IndexSet<Arc<GraphQLUnionType>> = unions
                .iter()
                .filter(|u| u.types.iter().any(|member| member.name == obj.name))
                .cloned()
                .collect();
            type_to_union_map.insert(Arc::clone(obj), containing_unions);
        }

        ReferencedTypes {
            all_types,
            schema_root_types,
            objects,
            interfaces,
            unions,
            scalars,
            custom_scalars,
            enums,
            input_objects,
            type_to_union_map,
        }
    }

    /// Returns the set of unions that include the given object type.
    ///
    /// Mirrors Swift's `unions(including:)` method.
    ///
    /// # Panics
    ///
    /// Panics if the object type is not found in the type-to-union map. This matches
    /// Swift's `unsafelyUnwrapped` behavior.
    pub fn unions_including(&self, type_: &GraphQLObjectType) -> &IndexSet<Arc<GraphQLUnionType>> {
        // Find the entry by name comparison since Arc identity may differ
        for (obj, unions) in &self.type_to_union_map {
            if obj.name == type_.name {
                return unions;
            }
        }
        panic!(
            "Object type '{}' not found in type_to_union_map. \
             This indicates a programming error -- all objects must be registered.",
            type_.name
        )
    }
}

impl fmt::Debug for ReferencedTypes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ReferencedTypes")
            .field("objects", &self.objects.len())
            .field("interfaces", &self.interfaces.len())
            .field("unions", &self.unions.len())
            .field("scalars", &self.scalars.len())
            .field("custom_scalars", &self.custom_scalars.len())
            .field("enums", &self.enums.len())
            .field("input_objects", &self.input_objects.len())
            .finish()
    }
}

impl fmt::Display for ReferencedTypes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "objects: {:?}", self.objects.iter().map(|t| &t.name).collect::<Vec<_>>())?;
        writeln!(f, "interfaces: {:?}", self.interfaces.iter().map(|t| &t.name).collect::<Vec<_>>())?;
        writeln!(f, "unions: {:?}", self.unions.iter().map(|t| &t.name).collect::<Vec<_>>())?;
        writeln!(f, "scalars: {:?}", self.scalars.iter().map(|t| &t.name).collect::<Vec<_>>())?;
        writeln!(f, "customScalars: {:?}", self.custom_scalars.iter().map(|t| &t.name).collect::<Vec<_>>())?;
        writeln!(f, "enums: {:?}", self.enums.iter().map(|t| &t.name).collect::<Vec<_>>())?;
        write!(f, "inputObjects: {:?}", self.input_objects.iter().map(|t| &t.name).collect::<Vec<_>>())
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    use graphql_compiler::GraphQLName;
    use indexmap::IndexMap;

    fn make_scalar(name: &str) -> Arc<GraphQLScalarType> {
        Arc::new(GraphQLScalarType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            specified_by_url: None,
        })
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

    fn make_enum(name: &str) -> Arc<GraphQLEnumType> {
        Arc::new(GraphQLEnumType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            values: vec![],
        })
    }

    fn make_input_object(name: &str) -> Arc<GraphQLInputObjectType> {
        Arc::new(GraphQLInputObjectType {
            name: GraphQLName::new(name.to_string()),
            documentation: None,
            is_one_of: false,
            fields: IndexMap::new(),
        })
    }

    fn make_root_types() -> RootTypeDefinition {
        RootTypeDefinition {
            query_type: GraphQLNamedType::Object(make_object("Query")),
            mutation_type: None,
            subscription_type: None,
        }
    }

    #[test]
    fn categorizes_objects_correctly() {
        let obj = make_object("User");
        let types = vec![GraphQLNamedType::Object(Arc::clone(&obj))];
        let rt = ReferencedTypes::new(&types, make_root_types());

        assert_eq!(rt.objects.len(), 1);
        assert!(rt.objects.contains(&obj));
        assert!(rt.interfaces.is_empty());
        assert!(rt.unions.is_empty());
    }

    #[test]
    fn categorizes_interfaces_correctly() {
        let iface = make_interface("Node");
        let types = vec![GraphQLNamedType::Interface(Arc::clone(&iface))];
        let rt = ReferencedTypes::new(&types, make_root_types());

        assert_eq!(rt.interfaces.len(), 1);
        assert!(rt.interfaces.contains(&iface));
        assert!(rt.objects.is_empty());
    }

    #[test]
    fn categorizes_unions_correctly() {
        let union = make_union("Animal", vec![]);
        let types = vec![GraphQLNamedType::Union(Arc::clone(&union))];
        let rt = ReferencedTypes::new(&types, make_root_types());

        assert_eq!(rt.unions.len(), 1);
        assert!(rt.unions.contains(&union));
    }

    #[test]
    fn categorizes_builtin_scalars_correctly() {
        let string_scalar = make_scalar("String");
        let int_scalar = make_scalar("Int");
        let types = vec![
            GraphQLNamedType::Scalar(Arc::clone(&string_scalar)),
            GraphQLNamedType::Scalar(Arc::clone(&int_scalar)),
        ];
        let rt = ReferencedTypes::new(&types, make_root_types());

        assert_eq!(rt.scalars.len(), 2);
        assert!(rt.custom_scalars.is_empty());
    }

    #[test]
    fn categorizes_custom_scalars_correctly() {
        let datetime = make_scalar("DateTime");
        let types = vec![GraphQLNamedType::Scalar(Arc::clone(&datetime))];
        let rt = ReferencedTypes::new(&types, make_root_types());

        assert!(rt.scalars.is_empty());
        assert_eq!(rt.custom_scalars.len(), 1);
        assert!(rt.custom_scalars.contains(&datetime));
    }

    #[test]
    fn categorizes_enums_correctly() {
        let status = make_enum("Status");
        let types = vec![GraphQLNamedType::Enum(Arc::clone(&status))];
        let rt = ReferencedTypes::new(&types, make_root_types());

        assert_eq!(rt.enums.len(), 1);
        assert!(rt.enums.contains(&status));
    }

    #[test]
    fn categorizes_input_objects_correctly() {
        let input = make_input_object("CreateUserInput");
        let types = vec![GraphQLNamedType::InputObject(Arc::clone(&input))];
        let rt = ReferencedTypes::new(&types, make_root_types());

        assert_eq!(rt.input_objects.len(), 1);
        assert!(rt.input_objects.contains(&input));
    }

    #[test]
    fn categorizes_all_7_variants() {
        let obj = make_object("User");
        let iface = make_interface("Node");
        let union = make_union("SearchResult", vec![Arc::clone(&obj)]);
        let scalar = make_scalar("String");
        let custom = make_scalar("DateTime");
        let enum_type = make_enum("Status");
        let input = make_input_object("Input");

        let types = vec![
            GraphQLNamedType::Object(Arc::clone(&obj)),
            GraphQLNamedType::Interface(Arc::clone(&iface)),
            GraphQLNamedType::Union(Arc::clone(&union)),
            GraphQLNamedType::Scalar(Arc::clone(&scalar)),
            GraphQLNamedType::Scalar(Arc::clone(&custom)),
            GraphQLNamedType::Enum(Arc::clone(&enum_type)),
            GraphQLNamedType::InputObject(Arc::clone(&input)),
        ];
        let rt = ReferencedTypes::new(&types, make_root_types());

        assert_eq!(rt.objects.len(), 1);
        assert_eq!(rt.interfaces.len(), 1);
        assert_eq!(rt.unions.len(), 1);
        assert_eq!(rt.scalars.len(), 1);
        assert_eq!(rt.custom_scalars.len(), 1);
        assert_eq!(rt.enums.len(), 1);
        assert_eq!(rt.input_objects.len(), 1);
        assert_eq!(rt.all_types.len(), 7);
    }

    #[test]
    fn unions_including_returns_correct_unions() {
        let cat = make_object("Cat");
        let dog = make_object("Dog");
        let animal_union = make_union("Animal", vec![Arc::clone(&cat), Arc::clone(&dog)]);
        let pet_union = make_union("Pet", vec![Arc::clone(&cat)]);

        let types = vec![
            GraphQLNamedType::Object(Arc::clone(&cat)),
            GraphQLNamedType::Object(Arc::clone(&dog)),
            GraphQLNamedType::Union(Arc::clone(&animal_union)),
            GraphQLNamedType::Union(Arc::clone(&pet_union)),
        ];
        let rt = ReferencedTypes::new(&types, make_root_types());

        // Cat is in both Animal and Pet unions
        let cat_unions = rt.unions_including(&cat);
        assert_eq!(cat_unions.len(), 2);

        // Dog is only in Animal union
        let dog_unions = rt.unions_including(&dog);
        assert_eq!(dog_unions.len(), 1);
    }

    #[test]
    fn unions_including_returns_empty_when_no_unions() {
        let obj = make_object("Standalone");
        let types = vec![GraphQLNamedType::Object(Arc::clone(&obj))];
        let rt = ReferencedTypes::new(&types, make_root_types());

        let unions = rt.unions_including(&obj);
        assert!(unions.is_empty());
    }

    #[test]
    fn schema_new_stores_fields() {
        let rt = Arc::new(ReferencedTypes::new(&[], make_root_types()));
        let schema = Schema::new(Arc::clone(&rt), Some("My schema".to_string()));

        assert!(schema.documentation.is_some());
        assert_eq!(schema.documentation.unwrap(), "My schema");
    }
}
