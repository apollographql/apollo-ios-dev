// Phase 3: GraphQL compiler bridge
//
// This crate provides Swift-equivalent GraphQL type system types and a
// conversion adapter from apollo-compiler parsed types. No apollo-compiler
// types are exposed in the public API.

pub mod adapter;
pub mod compilation_result;
pub mod graphql_error;
pub mod graphql_name;
pub mod graphql_source;
pub mod graphql_type;
pub mod graphql_value;
pub mod schema;
pub mod validation;
pub mod validation_options;

// Re-export primary types for convenient downstream imports.
pub use adapter::TypeRegistry;
pub use compilation_result::{
    Argument, CompilationResult, DeferCondition, Directive, Field, FragmentDefinition,
    FragmentSpread, InclusionCondition, InlineFragment, OperationDefinition, OperationType,
    RootTypeDefinition, Selection, SelectionSet, VariableDefinition,
};
pub use graphql_error::{GraphQLError, GraphQLSchemaValidationError};
pub use graphql_name::{GraphQLName, GraphQLNamedItem};
pub use graphql_source::{GraphQLSource, GraphQLSourceLocation};
pub use graphql_type::GraphQLType;
pub use graphql_value::GraphQLValue;
pub use schema::{
    GraphQLAbstractType, GraphQLCompositeType, GraphQLEnumType, GraphQLEnumValue, GraphQLField,
    GraphQLFieldArgument, GraphQLInputField, GraphQLInputObjectType, GraphQLInterfaceType,
    GraphQLNamedType, GraphQLObjectType, GraphQLScalarType, GraphQLSchema, GraphQLUnionType,
};
pub use validation::{validate_operations, OperationSource, ValidationError};
pub use validation_options::{DisallowedFieldNames, ValidationOptions};
