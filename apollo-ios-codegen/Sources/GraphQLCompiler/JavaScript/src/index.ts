import {
  Source,
  buildClientSchema,
  GraphQLSchema,
  parse,
  DocumentNode,
  concatAST,
  GraphQLError,
  validate,
  buildASTSchema,
  printSchema,
  extendSchema,
  Kind,
  GraphQLDeferDirective,
  GraphQLDirective,
  DirectiveDefinitionNode,
  ASTNode,
} from "graphql";
import { defaultValidationRules, ValidationOptions } from "./validationRules";
import { compileToIR, CompilationResult } from "./compiler";
import { assertValidSchema, assertValidSDL } from "./utilities/graphql";
import {
  addApolloCodegenSchemaExtensionToDocument,
} from "./utilities/apolloCodegenSchemaExtension";
import { definitionNode } from "./utilities";

// We need to export all the classes we want to map to native objects,
// so we have access to the constructor functions for type checks.
export {
  Source,
  GraphQLError,
  GraphQLSchema,
  GraphQLScalarType,
  GraphQLObjectType,
  GraphQLInterfaceType,
  GraphQLUnionType,
  GraphQLEnumType,
  GraphQLInputObjectType,
} from "graphql";
export { GraphQLSchemaValidationError } from "./utilities/graphql";

export function loadSchemaFromSources(sources: Source[]): GraphQLSchema {
  var introspectionJSONResult: Source | undefined

  var documents = new Array<DocumentNode>()
  for (const source of sources) {
    if (source.name.endsWith(".json")) {
      if (!introspectionJSONResult) {
        introspectionJSONResult = source
      } else {
        throw new Error(`Schema search paths can only include one JSON schema definition.
        Found "${introspectionJSONResult.name} & "${source.name}".`)
      }
    } else {
      documents.push(parse(source))
    }
  }

  var document = addApolloCodegenSchemaExtensionToDocument(concatAST(documents))
  document = validateOrAddExperimentalDeferDirectiveToDocument(document)

  if (!introspectionJSONResult) { assertValidSDL(document) }

  const schema = introspectionJSONResult ?
    extendSchema(loadSchemaFromIntrospectionResult(introspectionJSONResult.body), document, { assumeValid: true, assumeValidSDL: true }) :
    buildASTSchema(document, { assumeValid: true, assumeValidSDL: true })

  assertValidSchema(schema)

  return schema
}

function loadSchemaFromIntrospectionResult(
  introspectionResult: string
): GraphQLSchema {
  let payload = JSON.parse(introspectionResult);

  if (payload.data) {
    payload = payload.data;
  }

  const schema = buildClientSchema(payload);

  return schema;
}

export function printSchemaToSDL(schema: GraphQLSchema): string {
  return printSchema(schema)
}

export function parseOperationDocument(source: Source): DocumentNode {
  return parse(source);
}

export function mergeDocuments(documents: DocumentNode[]): DocumentNode {
  return concatAST(documents);
}

export function validateDocument(
  schema: GraphQLSchema,
  document: DocumentNode,
  validationOptions: ValidationOptions,
): readonly GraphQLError[] {
  return validate(schema, document, defaultValidationRules(validationOptions));
}

export function compileDocument(
  schema: GraphQLSchema,
  document: DocumentNode,
  legacySafelistingCompatibleOperations: boolean,
  validationOptions: ValidationOptions
): CompilationResult {
  return compileToIR(schema, document, legacySafelistingCompatibleOperations, validationOptions);
}

// While @defer is experimental the directive needs to be manually added to the list of available 
// directives for the schema document. If the directive is already in the document it must be 
// validated to ensure it matches the directive definition that Apollo iOS defer support was
// built to support.
//
// Once defer is part of the GraphQL spec and the directive is no longer considered experimental
// this check can be removed.
function validateOrAddExperimentalDeferDirectiveToDocument(document: DocumentNode): DocumentNode {
  const definition = document.definitions.find(isDeferDirectiveDefinitionNode)

  if (definition === undefined) {
    return concatAST([document, experimentalDeferDirectiveDocumentNode()])
  }

  if (!match(definition, GraphQLDeferDirective)) {
    throw new Error(
      `Mismatched ${GraphQLDeferDirective.toString()} directive found.`,
    );
  }

  return document
}

// Returns whether the current node is a defer directive definition node.
function isDeferDirectiveDefinitionNode(node: ASTNode): node is DirectiveDefinitionNode {
  return (
    node.kind === Kind.DIRECTIVE_DEFINITION && 
    node.name.value === GraphQLDeferDirective.name
  )
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

function experimentalDeferDirectiveDocumentNode(): DocumentNode {
  return {
    kind: Kind.DOCUMENT,
    definitions: [definitionNode(GraphQLDeferDirective)]
  }
}
