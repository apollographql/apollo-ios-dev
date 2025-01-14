import {
  DirectiveNode,
  GraphQLCompositeType,
  GraphQLError,
  GraphQLInterfaceType,
  GraphQLObjectType,
  GraphQLSchema,
  isInterfaceType,
  isNonNullType,
  isScalarType,
  isUnionType,
  Kind,
  valueFromASTUntyped,
} from "graphql";
import { directive_typePolicy } from "./apolloCodegenSchemaExtension";

const directiveName = directive_typePolicy.name.value;

type TypePolicyDirectiveResult = {
  directive: DirectiveNode;
  source: GraphQLObjectType | GraphQLInterfaceType;
};

function matchDirectiveArguments(
  first: DirectiveNode,
  second: DirectiveNode
): boolean {
  return (
    (first.arguments ?? [])
      .map((node) =>
        JSON.stringify([node.name.value, valueFromASTUntyped(node.value)])
      )
      .sort()
      .toString() ===
    (second.arguments ?? [])
      .map((node) =>
        JSON.stringify([node.name.value, valueFromASTUntyped(node.value)])
      )
      .sort()
      .toString()
  );
}

function typePolicyDirectiveFor(
  type: GraphQLCompositeType
): TypePolicyDirectiveResult | undefined {
  if (isUnionType(type)) {
    return undefined;
  }

  for (const extension of type.extensionASTNodes ?? []) {
    const directive = extension.directives?.find(
      (d) => d.name.value === directiveName
    );
    if (directive) {
      return { directive, source: type };
    }
  }

  let result: TypePolicyDirectiveResult | undefined;
  for (const directive of type.astNode?.directives ?? []) {
    if (directive.name.value === directiveName) {
      result = { directive, source: type };
      break;
    }
  }

  if ("getInterfaces" in type) {
    for (const interfaceType of type.getInterfaces()) {
      const found = typePolicyDirectiveFor(interfaceType);
      if (!found) continue;

      if (!result) {
        result = found;
      } else if (!matchDirectiveArguments(result.directive, found.directive)) {
        if (result.source === type) {
          throw new GraphQLError(
            `Type "${type.name}" has a @typePolicy directive which conflicts with the @typePolicy directive on interface "${found.source.name}".`,
            { nodes: type.astNode }
          );
        } else {
          throw new GraphQLError(
            `Type "${type.name}" inherits conflicting @typePolicy directives from interfaces "${result.source.name}" and "${found.source.name}".`,
            { nodes: type.astNode }
          );
        }
      }
    }
  }

  return result;
}

function validateKeyFields(
  result: TypePolicyDirectiveResult,
  keyFields: string[]
) {
  const { directive, source: type } = result;

  if (isUnionType(type)) {
    return;
  }

  const label = isInterfaceType(type) ? "interface" : "object";

  var allFields = type.getFields();
  for (const keyField of keyFields) {
    if (!keyField) {
      throw new GraphQLError(
        `Key fields must be a space-separated list of identifiers.`,
        { nodes: directive }
      );
    }

    const actualField = allFields[keyField];
    if (!actualField) {
      throw new GraphQLError(
        `Key field "${keyField}" does not exist on ${label} "${type.name}".`,
        { nodes: type.astNode ? [type.astNode, directive] : directive }
      );
    }

    if (!isNonNullType(actualField.type)) {
      throw new GraphQLError(
        `Key field "${keyField}" on ${label} "${type.name}" must be non-nullable.`,
        {
          nodes: actualField.astNode
            ? [actualField.astNode, directive]
            : directive,
        }
      );
    }

    if (!isScalarType(actualField.type.ofType)) {
      throw new GraphQLError(
        `Key field "${keyField}" on ${label} "${type.name}" must be a scalar type, got ${actualField.type}.`,
        {
          nodes: actualField.astNode
            ? [actualField.astNode, directive]
            : directive,
        }
      );
    }
  }
}

export function keyFieldsFor(type: GraphQLCompositeType): string[] {
  const result = typePolicyDirectiveFor(type);
  if (!result) {
    return [];
  }

  const argumentValue = result.directive?.arguments?.find(
    (b) => b.name.value === "keyFields"
  )?.value;
  if (!argumentValue || argumentValue.kind !== Kind.STRING) {
    return [];
  }

  const fields = argumentValue.value.split(" ");

  validateKeyFields(result, fields);

  return fields;
}

export function addTypePolicyDirectivesToSchema(schema: GraphQLSchema) {
  const types = schema.getTypeMap();

  for (const key in types) {
    const type = types[key];

    if (type instanceof GraphQLObjectType || type instanceof GraphQLInterfaceType) {
      (type as any)._apolloKeyFields = keyFieldsFor(type);
    }
  }
}
