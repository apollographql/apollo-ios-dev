import {
  DefinitionNode,
  DirectiveDefinitionNode,
  DocumentNode,
  GraphQLDeferDirective,
  GraphQLDirective,
  Kind,
  concatAST,
} from "graphql";
import { definitionNode } from "./nodeHelpers";

// While @defer is experimental the directive needs to be manually added to the list of directives
// available to operations. If the directive is already in the schema it must be validated to 
// ensure it matches the @defer directive definition supported by Apollo iOS.
//
// Once defer is part of the GraphQL spec and the directive is no longer considered experimental
// this function can be removed.
export function addExperimentalDeferDirectiveToDocument(document: DocumentNode): DocumentNode {
  const definition = document.definitions.find(isDeferDirectiveDefinitionNodePredicate)

  if (definition === undefined) {
    return concatAST([document, experimentalDeferDirectiveDocumentNode()])
  }

  const directiveDefinition = definition as DirectiveDefinitionNode

  if (!match(directiveDefinition, GraphQLDeferDirective)) {
    console.warn(`Unsupported ${directiveDefinition.name.value} directive found. It will be replaced with a supported definition instead.`)

    const modifiedDocument: DocumentNode = {
      kind: Kind.DOCUMENT,
      definitions: document.definitions.filter(
        (value) => !isDeferDirectiveDefinitionNodePredicate(value) ? value : undefined)
        .concat(definitionNode(GraphQLDeferDirective))
    }

    return modifiedDocument
  }

  return document
}

// Checks whether the definition node is a defer directive definition node.
function isDeferDirectiveDefinitionNodePredicate(value: DefinitionNode) {
  return (
    value.kind === Kind.DIRECTIVE_DEFINITION && 
    value.name.value === GraphQLDeferDirective.name
  )
}

function experimentalDeferDirectiveDocumentNode(): DocumentNode {
  return {
    kind: Kind.DOCUMENT,
    definitions: [definitionNode(GraphQLDeferDirective)]
  }
}

// Checks whether the supplied directive definition node matches against important properties
// of the experimentally defined defer directive that Apollo iOS expects.
function match(definition: DirectiveDefinitionNode, target: GraphQLDirective): Boolean {
  return(
    definition.repeatable === target.isRepeatable &&
    definition.locations.map((node) => node.value).sort().toString() === target.locations.slice(0).sort().toString() &&
    definition.arguments?.map((value) => value.name.value).sort().toString() === target.args.map((value) => value.name).sort().toString()
  )
}
