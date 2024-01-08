import { DirectiveDefinitionNode, DocumentNode, Kind, concatAST, GraphQLString } from "graphql";
import { nameNode, nonNullNode, stringNode, typeNode } from "./nodeHelpers";

export const directive_apollo_client_ios_localCacheMutation: DirectiveDefinitionNode = {
  kind: Kind.DIRECTIVE_DEFINITION,
  description: stringNode("A directive used by the Apollo iOS client to annotate operations or fragments that should be used exclusively for generating local cache mutations instead of as standard operations."),
  name: nameNode("apollo_client_ios_localCacheMutation"),
  repeatable: false,
  locations: [nameNode("QUERY"), nameNode("MUTATION"), nameNode("SUBSCRIPTION"), nameNode("FRAGMENT_DEFINITION")]
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

export const apolloCodegenSchemaExtension: DocumentNode = {
  kind: Kind.DOCUMENT,
  definitions: [
    directive_apollo_client_ios_localCacheMutation,
    directive_import_statement
  ]
}

export function addApolloCodegenSchemaExtensionToDocument(document: DocumentNode): DocumentNode {
  return document.definitions.some(definition =>
    definition.kind == Kind.DIRECTIVE_DEFINITION &&
    definition.name.value == directive_apollo_client_ios_localCacheMutation.name.value
  ) ?
    document :
    concatAST([document, apolloCodegenSchemaExtension])
}
