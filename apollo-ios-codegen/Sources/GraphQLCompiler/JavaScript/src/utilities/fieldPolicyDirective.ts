import {
  DirectiveNode,
  getNamedType,
  getNullableType,
  GraphQLCompositeType,
  GraphQLError,
  GraphQLField,
  GraphQLInputType,
  GraphQLInterfaceType,
  GraphQLObjectType,
  GraphQLSchema,
  isInputObjectType,
  isInterfaceType,
  isListType,
  isNonNullType,
  isObjectType,
  isUnionType,
  Kind,
  valueFromASTUntyped,
} from "graphql";
import { directive_fieldPolicy } from "./apolloCodegenSchemaExtension";

const directiveName = directive_fieldPolicy.name.value

export function addFieldPolicyDirectivesToSchema(
  schema: GraphQLSchema
) {
  const types = schema.getTypeMap();

  for (const t in types) {
    const type = types[t];

    if (type instanceof GraphQLObjectType || type instanceof GraphQLInterfaceType) {
      applyFieldPoliciesFor(type);
    }
  }
}

export function applyFieldPoliciesFor(
  type: GraphQLCompositeType
) {
  const directives = fieldPolicyDirectivesFor(type)
  if (!directives || isUnionType(type)) {
    return;
  }

  const typeFields = type.getFields()

  for (const directive of directives) {
    const forFieldValueNode = directive.arguments?.find(
      (b) => b.name.value === "forField"
    )?.value
    let forField: string | undefined = undefined;
    if (forFieldValueNode?.kind === Kind.STRING) {
      forField = forFieldValueNode.value
    }

    if (!forField) {
      throw new GraphQLError(
        `@fieldPolicy directive must have a 'forField' value.`,
        { nodes: directive }
      );
    }

    const keyArgsValueNode = directive.arguments?.find(
      (b) => b.name.value === "keyArgs"
    )?.value
    let keyArgs: string[] = [];
    if (keyArgsValueNode?.kind === Kind.STRING) {
      const rawArgs = keyArgsValueNode.value.split(/\s+/);
      keyArgs = [...new Set(rawArgs.filter(Boolean))];
    }

    if (keyArgs.length === 0) {
      throw new GraphQLError(
        `'keyArgs' must be a space-separated list of identifiers.`,
        { nodes: directive }
      );
    }

    // check that the field exists
    const actualField = typeFields[forField]
    if (!actualField) {
      throw new GraphQLError(
        `Field "${forField}" does not exist on type "${type.name}".`,
        { nodes: type.astNode ? [type.astNode, directive] : directive}
      );
    }

    // validate the provided key args match an input parameter
    validateKeyArgs(actualField, keyArgs);

    // List input and return type validation
    validateListRules(actualField);

    (actualField as any)._apolloFieldPolicies = keyArgs;
  }
}

function fieldPolicyDirectivesFor(
  type: GraphQLCompositeType
): DirectiveNode[] | undefined {
  if(!isObjectType(type) && !isInterfaceType(type)) {
    return undefined;
  }

  const result: DirectiveNode[] = [];

  for (const extension of type.extensionASTNodes ?? []) {
    const directive = extension.directives?.find(
      (d) => d.name.value === directiveName
    );
    if (directive) {
      result.push(directive)
    }
  }

  for (const directive of type.astNode?.directives ?? []) {
    if (directive.name.value === directiveName) {
      result.push(directive);
    }
  }

  if("getInterfaces" in type) {
    for (const interfaceType of type.getInterfaces()) {
      const found = fieldPolicyDirectivesFor(interfaceType);
      if (!found) {
        continue;
      }

      for (const foundDirective of found) {
        var duplicate = false;
        for (const directive of result) {
          if (matchDirectiveArguments(directive, foundDirective)) {
            duplicate = true;
            break;
          }
        }

        if (!duplicate) {
          result.push(foundDirective);
        }
      }
    }
  }

  return result
}

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

function validateKeyArgs(
  actualField: GraphQLField<any, any>,
  keyArgs: string[]
): void {
  for (const keyArg of keyArgs) {
    validateKeyArgPath(actualField, keyArg);
  }
}

function validateKeyArgPath(
  field: GraphQLField<any, any>,
  keyArg: string
): void {
  const parts = keyArg.split(".").filter(Boolean);
  const [argName, ...path] = parts;

  const arg = field.args.find(a => a.name === argName);
  if (!arg) {
    throw new GraphQLError(
      `@fieldPolicy key argument "${keyArg}" does not exist as an input argument of field "${field.name}".`,
      { nodes: field.astNode }
    );
  }

  let curType: GraphQLInputType = base(arg.type);

  for (let i = 0; i < path.length; i++) {
    const segment = path[i];
    if (!isInputObjectType(curType)) {
      throw new GraphQLError(
        `@fieldPolicy key "${keyArg}" traverses "${segment}" on non-object input type "${String(curType)}".`,
        { nodes: field.astNode }
      );
    }
    const fieldMap = curType.getFields();
    const nextField = fieldMap[segment];
    if (!nextField) {
      const suggestions = Object.keys(fieldMap).join(", ");
      throw new GraphQLError(
        `@fieldPolicy key "${keyArg}" refers to unknown input field "${segment}" on "${curType.name}". Known fields: ${suggestions}`,
        { nodes: field.astNode }
      );
    }
    curType = base(nextField.type);
  }

  if (!parts.length || isInputObjectType(curType)) {
    throw new GraphQLError(
      `@fieldPolicy key "${keyArg}" must resolve to a leaf input type (scalar/enum), got "${String(curType)}".`,
      { nodes: field.astNode }
    );
  }
}

function base(type: GraphQLInputType): GraphQLInputType {
  return getNamedType(type) as GraphQLInputType;
}

function isListArg(t: GraphQLInputType): boolean {
  return isListType(getNullableType(t));
}

function hasNestedList(t: GraphQLInputType): boolean {
  let outer: any = isNonNullType(t) ? t.ofType : t;
  if (!isListType(outer)) return false;

  let inner: any = isNonNullType(outer.ofType) ? outer.ofType.ofType : outer.ofType;
  return isListType(inner);
}

function validateListRules(field: GraphQLField<any, any>) {
  const hasListReturnType = isListType(getNullableType(field.type));

  let numListInputs = 0;

  for (const arg of field.args) {
    if (isListArg(arg.type)) {
      numListInputs += 1;

      if (hasNestedList(arg.type)) {
        throw new GraphQLError(
          `@fieldPolicy does not allow nested list input parameters. Argument "${arg.name}" has type "${String(arg.type)}".`,
          { nodes: field.astNode }
        );
      }
    }
  }

  if (numListInputs > 1) {
    throw new GraphQLError(
      `@fieldPolicy can only have at most 1 List type input parameter.`,
      { nodes: field.astNode }
    );
  }

  if ((hasListReturnType && numListInputs !== 1) ||
      (!hasListReturnType && numListInputs !== 0)) {
    throw new GraphQLError(
      `@fieldPolicy requires either both a List return type and exactly 1 List input parameter, or neither.`,
      { nodes: field.astNode }
    );
  }
}