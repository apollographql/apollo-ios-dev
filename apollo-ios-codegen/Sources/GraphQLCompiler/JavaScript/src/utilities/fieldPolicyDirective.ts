import {
  DirectiveNode,
  GraphQLCompositeType,
  GraphQLError,
  GraphQLInterfaceType,
  GraphQLObjectType,
  GraphQLSchema,
  isInterfaceType,
  isListType,
  isObjectType,
  isUnionType,
  Kind,
  valueFromASTUntyped,
} from "graphql";
import { directive_fieldPolicy } from "./apolloCodegenSchemaExtension";

const directiveName = directive_fieldPolicy.name.value

// type FieldPolicyDirectiveResult = {
//   directive: DirectiveNode;
//   source: GraphQLObjectType;
// };

export function addFieldPolicyDirectivesToSchema(
  schema: GraphQLSchema
) {
  const types = schema.getTypeMap();

  for (const t in types) {
    const type = types[t];

    if (type instanceof GraphQLObjectType || type instanceof GraphQLInterfaceType) {
      // (type as any)._apolloFieldPolicies = applyFieldPoliciesFor(type);
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
    let keyArgs: string[] | undefined = undefined;
    if (keyArgsValueNode?.kind == Kind.STRING) {
      const rawArgs = keyArgsValueNode.value.split(" ");
      keyArgs = [...new Set(rawArgs.filter(Boolean))];
    }

    if (!keyArgs) {
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
    const inputs = actualField.astNode?.arguments;
    const inputNames = new Set(inputs?.map(input => input.name.value) ?? []);
    for (const keyArg of keyArgs) {
      if (!inputNames.has(keyArg)) {
        throw new GraphQLError(
          `@fieldPolicy key argument "${keyArg}" does not exist as an input argument of field "${actualField.name}".`,
          {
            nodes: actualField.astNode
          }
        );
      }
    }

    // List input and return type validation
    if (inputs) {
      var numListInputs = 0;
      const hasListReturnType = isListType(actualField.type);

      for (const inputArg of inputs) {
        if (inputArg.type.kind == "ListType") {
          numListInputs += 1;
        }
      }

      // validate we have at most 1 list input parameter
      if (numListInputs > 1) {
        throw new GraphQLError(
          `@fieldPolicy can only have at most 1 List type input parameter.`,
          { nodes: actualField.astNode }
        );
      }

      // validate that a list input parameter and return type exist either together
      // or not at all
      if ((hasListReturnType && numListInputs != 1) || (numListInputs == 1 && !hasListReturnType)) {
        throw new GraphQLError(
          `@fieldPolicy requires either both a List return type and 1 List input parameter, or neither.`,
          { nodes: actualField.astNode }
        );
      }
    }

    if (!(actualField as any)._apolloFieldPolicies) {
      (actualField as any)._apolloFieldPolicies = keyArgs
    } else {
      (actualField as any)._apolloFieldPolicies = []
    }
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