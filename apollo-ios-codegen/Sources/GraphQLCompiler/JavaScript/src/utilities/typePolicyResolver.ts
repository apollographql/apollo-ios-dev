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

  for (const directive of type.astNode?.directives ?? []) {
    if (directive.name.value === directiveName) {
      return { directive, source: type };
    }
  }

  if ("getInterfaces" in type) {
    let result: TypePolicyDirectiveResult | undefined;

    for (const interfaceType of type.getInterfaces()) {
      const found = typePolicyDirectiveFor(interfaceType);
      if (!found) continue;

      if (!result) {
        result = found;
      } else if (!matchDirectiveArguments(result.directive, found.directive)) {
        throw new GraphQLError(
          `Type "${type.name}" inherits conflicting @typePolicy directives from interfaces "${result.source.name}" and "${found.source.name}". Please specify a @typePolicy directive on the concrete type.`,
          { nodes: type.astNode }
        );
      }
    }

    return result;
  }

  return undefined;
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

    const fieldType = isNonNullType(actualField.type)
      ? actualField.type.ofType
      : actualField.type;

    if (!isScalarType(fieldType)) {
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

    if (type instanceof GraphQLObjectType) {
      (type as any)._apolloKeyFields = keyFieldsFor(type);
    }
  }
}
