import { DirectiveDefinitionNode, DocumentNode, Kind, concatAST, GraphQLString } from "graphql";
import { nameNode, nonNullNode, stringNode, typeNode } from "./nodeHelpers";

export const directive_apollo_client_ios_localCacheMutation: DirectiveDefinitionNode = {
  kind: Kind.DIRECTIVE_DEFINITION,
  description: stringNode("A directive used by the Apollo iOS client to annotate operations or fragments that should be used exclusively for generating local cache mutations instead of as standard operations."),
  name: nameNode("apollo_client_ios_localCacheMutation"),
  repeatable: false,
  locations: [nameNode("QUERY"), nameNode("MUTATION"), nameNode("SUBSCRIPTION"), nameNode("FRAGMENT_DEFINITION")]
}

export const directive_typePolicy: DirectiveDefinitionNode = {
  kind: Kind.DIRECTIVE_DEFINITION,
  description: stringNode("Attach extra information to a given type."),
  name: nameNode("typePolicy"),
  arguments: [
    {
      kind: Kind.INPUT_VALUE_DEFINITION,
      description: stringNode("A selection set containing fields used to compute the cache key of an object. Referenced fields must have non-nullable scalar types. Order is important."),
      name: nameNode("keyFields"),
      type: nonNullNode(typeNode(GraphQLString))
    }
  ],
  repeatable: false,
  locations: [nameNode("OBJECT"), nameNode("INTERFACE")]
}

export const directive_fieldPolicy: DirectiveDefinitionNode = {
  kind: Kind.DIRECTIVE_DEFINITION,
  description: stringNode("A directive used by Apollo iOS to map query input data to cache keys of objects."),
  name: nameNode("fieldPolicy"),
  arguments: [
    {
      kind: Kind.INPUT_VALUE_DEFINITION,
      description: stringNode("The field you are setting the @fieldPolicy for."),
      name: nameNode("forField"),
      type: nonNullNode(typeNode(GraphQLString))
    },
    {
      kind: Kind.INPUT_VALUE_DEFINITION,
      description: stringNode("Set of fields used to compute the cache key."),
      name: nameNode("keyArgs"),
      type: nonNullNode(typeNode(GraphQLString))
    }
  ],
  repeatable: true,
  locations: [nameNode("OBJECT"), nameNode("INTERFACE")]
}

export const directive_import_statement: DirectiveDefinitionNode = {
  kind: Kind.DIRECTIVE_DEFINITION,
  description: stringNode("A directive used by the Apollo iOS code generation engine to generate custom import statements in operation or fragment definition files. An import statement to import a module with the name provided in the `module` argument will be added to the generated definition file."),
  name: nameNode("import"),
  arguments: [
    {
      kind: Kind.INPUT_VALUE_DEFINITION,
      description: stringNode("The name of the module to import."),
      name: nameNode("module"),
      type: nonNullNode(typeNode(GraphQLString))
    }
  ],
  repeatable: true,
  locations: [nameNode("QUERY"), nameNode("MUTATION"), nameNode("SUBSCRIPTION"), nameNode("FRAGMENT_DEFINITION")]
}

const apolloDirectives = [
  directive_apollo_client_ios_localCacheMutation,
  directive_import_statement,
  directive_typePolicy,
  directive_fieldPolicy
]

export function addApolloCodegenSchemaExtensionToDocument(document: DocumentNode): DocumentNode {
  const directives = apolloDirectives.filter(directive => !document.definitions.some(definition =>
    definition.kind == Kind.DIRECTIVE_DEFINITION &&
    definition.name.value == directive.name.value
  ));

  return concatAST([document, {
    kind: Kind.DOCUMENT,
    definitions: directives
  }]);
}
