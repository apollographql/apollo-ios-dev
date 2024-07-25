import { 
  compileDocument,
  parseOperationDocument,
  loadSchemaFromSources,
  validateDocument,
  printSchemaToSDL,
} from "../index"
import { 
  CompilationResult
} from "../compiler/index"
import {  
  Field,
  FragmentSpread,
  InlineFragment
} from "../compiler/ir"
import { 
  Source,
  GraphQLSchema,
  DocumentNode,
  GraphQLError,
  buildASTSchema,
  parse,
  GraphQLDeferDirective,
  buildClientSchema,
} from "graphql";
import { emptyValidationOptions } from "../__testUtils__/validationHelpers";

describe("given SDL without defer directive", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals: [Animal!]
  }

  interface Animal {
    species: String!
    friend: Animal!
  }

  type Dog implements Animal {
    species: String!
    friend: Animal!
  }
  `;

  // Directive Definition Tests

  describe("automatically adds a defer directive", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([new Source(schemaSDL, "Test Schema", { line: 1, column: 1 })]);

    const documentString: string = `
    query Test {
      allAnimals {
        ... on Animal @defer(label: "deferred") {
          species
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should pass validation", () => {
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    });
  })

  // This test is being used as a fail-safe to know when graphql-js removes the 'experimental' designation from
  // the defer directive and it is automatically made available to operations. When this test starts failing 
  // the automatic addition of the experimental defer directive done in loadSchemaFromSources must be removed.
  describe("does not add a defer directive", () => {
    // Note we're not calling loadSchemaFromSources which adds the experimental defer directive
    const schemaDocument = parse(schemaSDL)
    const schema: GraphQLSchema = buildASTSchema(schemaDocument, { assumeValid: true, assumeValidSDL: true });

    const documentString: string = `
    query Test {
      allAnimals {
        ... on Animal @defer(label: "deferred") {
          species
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should fail validation", () => {
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(1)
      expect(validationErrors[0].message).toEqual(
        "Unknown directive \"@defer\"."
      )
    });
  });
})

describe("given SDL with unsupported defer directive", () => {
  const schemaSDL: string = `
  directive @defer(label: String, if: Boolean! = true) on FIELD

  type Query {
    allAnimals: [Animal!]
  }

  interface Animal {
    species: String!
    friend: Animal!
  }

  type Dog implements Animal {
    species: String!
    friend: Animal!
  }
  `;

  const schema: GraphQLSchema = loadSchemaFromSources([new Source(schemaSDL, "Test Schema", { line: 1, column: 1 })]);

  // Directive Definition Tests

  describe("replaces unsupported defer directive with experimental supported definition", () => {
    const documentString: string = `
    query Test {
      allAnimals {
        ... on Animal @defer(label: "deferred") { # This would fail validation if the original definition were not replaced
          species
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should pass validation", () => {
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    });
  })
})

describe("given SDL with valid defer directive", () => {
  const schemaSDL: string = `
  directive @defer(label: String, if: Boolean! = true) on FRAGMENT_SPREAD | INLINE_FRAGMENT

  type Query {
    allAnimals: [Animal!]
  }

  interface Animal {
    species: String!
    friend: Animal!
  }

  type Dog implements Animal {
    species: String!
    friend: Animal!
  }
  `;

  const schema: GraphQLSchema = loadSchemaFromSources([new Source(schemaSDL, "Test Schema", { line: 1, column: 1 })]);

  // Directive Definition Tests

  describe("does not add a duplicate directive", () => {
    const documentString: string = `
    query Test {
      allAnimals {
        ... on Animal @defer(label: "deferred") {
          species
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should pass validation", () => {
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    });
  })

  // Compilation Tests

  describe("query has inline fragment with @defer directive", () => {
    const documentString: string = `
    query Test {
      allAnimals {
        ... on Animal @defer(label: "deferred") {
          species
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should compile inline fragment with directive", () => {
      const compilationResult: CompilationResult = compileDocument(schema, document, false, emptyValidationOptions);
      const operation = compilationResult.operations[0];
      const allAnimals = operation.selectionSet.selections[0] as Field;
      const inlineFragment = allAnimals?.selectionSet?.selections?.[0] as InlineFragment;

      expect(inlineFragment.directives).toHaveLength(1);

      expect(inlineFragment.directives?.[0].name).toEqual("defer");
    });
  });

  describe("query has inline fragment with @defer directive with arguments", () => {
    const documentString: string = `
    query Test($a: Boolean!) {
      allAnimals {
        ... on Animal @defer(if: true, label: "species") {
          species
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should compile inline fragment with directive and arguments", () => {
      const compilationResult: CompilationResult = compileDocument(schema, document, false, emptyValidationOptions);
      const operation = compilationResult.operations[0];
      const allAnimals = operation.selectionSet.selections[0] as Field;
      const inlineFragment = allAnimals?.selectionSet?.selections?.[0] as InlineFragment;

      expect(inlineFragment.directives).toHaveLength(1);

      expect(inlineFragment.directives?.[0].name).toEqual("defer");
      
      expect(inlineFragment.directives?.[0].arguments).toHaveLength(2);
      expect(inlineFragment.directives?.[0].arguments?.[0].name).toEqual("if");
      expect(inlineFragment.directives?.[0].arguments?.[1].name).toEqual("label");
    });
  });

  describe("query has fragment spread with @defer directive", () => {
    const documentString: string = `
    query Test($a: Boolean!) {
      allAnimals {
        ... SpeciesFragment @defer
      }
    }

    fragment SpeciesFragment on Animal {
      species
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should compile fragment spread with directive", () => {
      const compilationResult: CompilationResult = compileDocument(schema, document, false, emptyValidationOptions);
      const operation = compilationResult.operations[0];
      const allAnimals = operation.selectionSet.selections[0] as Field;
      const inlineFragment = allAnimals?.selectionSet?.selections?.[0] as FragmentSpread;

      expect(inlineFragment.directives).toHaveLength(1);

      expect(inlineFragment.directives?.[0].name).toEqual("defer");
    });
  });

  describe("query has fragment spread with @defer directive with arguments", () => {
    const documentString: string = `
    query Test($a: Boolean!) {
      allAnimals {
        ... SpeciesFragment @defer(if: true, label: "species")
      }
    }

    fragment SpeciesFragment on Animal {
      species
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should compile fragment spread with directive and arguments", () => {
      const compilationResult: CompilationResult = compileDocument(schema, document, false, emptyValidationOptions);
      const operation = compilationResult.operations[0];
      const allAnimals = operation.selectionSet.selections[0] as Field;
      const inlineFragment = allAnimals?.selectionSet?.selections?.[0] as FragmentSpread;

      expect(inlineFragment.directives).toHaveLength(1);
      
      expect(inlineFragment.directives?.[0].name).toEqual("defer");
      
      expect(inlineFragment.directives?.[0].arguments).toHaveLength(2);
      expect(inlineFragment.directives?.[0].arguments?.[0].name).toEqual("if");
      expect(inlineFragment.directives?.[0].arguments?.[1].name).toEqual("label");
    });
  });

  // Validation Tests

  describe("query has inline fragment with @defer directive and no type condition", () => {
    const documentString: string = `
    query Test {
      allAnimals {
        ... @defer(label: "custom") {
          species
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should fail validation", () => {
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(1)
      expect(validationErrors[0].message).toEqual(
        "Apollo does not support deferred inline fragments without a type condition. Please add a type condition to this inline fragment."
      )
    });
  });

  describe("query has inline fragment with @defer directive and no label argument", () => {
    const documentString: string = `
    query Test {
      allAnimals {
        ... on Dog @defer {
          species
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should fail validation", () => {
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(1)
      expect(validationErrors[0].message).toEqual(
        "Apollo does not support deferred inline fragments without a 'label' argument. Please add a 'label' argument to the @defer directive on this inline fragment."
      )
    })
  })

  describe("query has fragment spread with @defer directive and no label argument", () => {
    const documentString: string = `
    query Test {
      allAnimals {
        ...DogFragment @defer
      }
    }

    fragment DogFragment on Dog {
      species
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should pass validation", () => {
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    })
  })

  describe("query has fragment spread, with @defer directive and if argument and no label argument on fragment inner type condition", () => {
    const documentString: string = `
    query Test {
      allAnimals {
        ...AnimalFragment
      }
    }

    fragment AnimalFragment on Animal {
      ... on Dog @defer(if: true) {
        species
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should fail validation", () => {
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(1)
      expect(validationErrors[0].message).toEqual(
        "Apollo does not support deferred inline fragments without a 'label' argument. Please add a 'label' argument to the @defer directive on this inline fragment."
      )
    })
  })

  describe("query has inline fragment with @defer directive and label argument", () => {
    const documentString: string = `
    query Test {
      allAnimals {
        ... on Dog @defer(label: "custom") {
          species
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should pass validation", () => {
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    })
  })

  describe("query has fragment spread with @defer directive and label argument", () => {
    const documentString: string = `
    query Test {
      allAnimals {
        ...AnimalFragment @defer(label: "custom")
      }
    }

    fragment AnimalFragment on Animal {
      species
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("should pass validation", () => {
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    })
  })
})

describe("given introspection JSON without defer directive", () => {
  const introspectionJSON: string = `
  {"data":{"__schema":{"queryType":{"name":"Query"},"mutationType":null,"subscriptionType":null,"types":[{"kind":"OBJECT","name":"Book","description":null,"fields":[{"name":"title","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"author","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"SCALAR","name":"String","description":"The \`String\` scalar type represents textual data, represented as UTF-8 character sequences. The String type is most often used by GraphQL to represent free-form human-readable text.","fields":null,"inputFields":null,"interfaces":null,"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"Query","description":null,"fields":[{"name":"books","description":null,"args":[],"type":{"kind":"LIST","name":null,"ofType":{"kind":"OBJECT","name":"Book","ofType":null}},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"SCALAR","name":"Boolean","description":"The \`Boolean\` scalar type represents \`true\` or \`false\`.","fields":null,"inputFields":null,"interfaces":null,"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__Schema","description":"A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types and directives on the server, as well as the entry points for query, mutation, and subscription operations.","fields":[{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"types","description":"A list of all types supported by this server.","args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}}}},"isDeprecated":false,"deprecationReason":null},{"name":"queryType","description":"The type that query operations will be rooted at.","args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"mutationType","description":"If this server supports mutation, the type that mutation operations will be rooted at.","args":[],"type":{"kind":"OBJECT","name":"__Type","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"subscriptionType","description":"If this server support subscription, the type that subscription operations will be rooted at.","args":[],"type":{"kind":"OBJECT","name":"__Type","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"directives","description":"A list of all directives supported by this server.","args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Directive","ofType":null}}}},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__Type","description":"The fundamental unit of any GraphQL Schema is the type. There are many kinds of types in GraphQL as represented by the \`__TypeKind\` enum.\\n\\nDepending on the kind of a type, certain fields describe information about that type. Scalar types provide no information beyond a name, description and optional \`specifiedByURL\`, while Enum types provide their values. Object and Interface types provide the fields they describe. Abstract types, Union and Interface, provide the Object types possible at runtime. List and NonNull types compose other types.","fields":[{"name":"kind","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"ENUM","name":"__TypeKind","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"name","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"specifiedByURL","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"fields","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Field","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"interfaces","description":null,"args":[],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"possibleTypes","description":null,"args":[],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"enumValues","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__EnumValue","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"inputFields","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__InputValue","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"ofType","description":null,"args":[],"type":{"kind":"OBJECT","name":"__Type","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isOneOf","description":null,"args":[],"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"ENUM","name":"__TypeKind","description":"An enum describing what kind of type a given \`__Type\` is.","fields":null,"inputFields":null,"interfaces":null,"enumValues":[{"name":"SCALAR","description":"Indicates this type is a scalar.","isDeprecated":false,"deprecationReason":null},{"name":"OBJECT","description":"Indicates this type is an object. \`fields\` and \`interfaces\` are valid fields.","isDeprecated":false,"deprecationReason":null},{"name":"INTERFACE","description":"Indicates this type is an interface. \`fields\`, \`interfaces\`, and \`possibleTypes\` are valid fields.","isDeprecated":false,"deprecationReason":null},{"name":"UNION","description":"Indicates this type is a union. \`possibleTypes\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"ENUM","description":"Indicates this type is an enum. \`enumValues\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"INPUT_OBJECT","description":"Indicates this type is an input object. \`inputFields\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"LIST","description":"Indicates this type is a list. \`ofType\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"NON_NULL","description":"Indicates this type is a non-null. \`ofType\` is a valid field.","isDeprecated":false,"deprecationReason":null}],"possibleTypes":null},{"kind":"OBJECT","name":"__Field","description":"Object and Interface types are described by a list of Fields, each of which has a name, potentially a list of arguments, and a return type.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"args","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__InputValue","ofType":null}}}},"isDeprecated":false,"deprecationReason":null},{"name":"type","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"isDeprecated","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"deprecationReason","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__InputValue","description":"Arguments provided to Fields or Directives and the input fields of an InputObject are represented as Input Values which describe their type and optionally a default value.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"type","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"defaultValue","description":"A GraphQL-formatted string representing the default value for this input value.","args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isDeprecated","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"deprecationReason","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__EnumValue","description":"One possible value for a given Enum. Enum values are unique values, not a placeholder for a string or numeric value. However an Enum value is returned in a JSON response as a string.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isDeprecated","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"deprecationReason","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__Directive","description":"A Directive provides a way to describe alternate runtime execution and type validation behavior in a GraphQL document.\\n\\nIn some cases, you need to provide options to alter GraphQL's execution behavior in ways field arguments will not suffice, such as conditionally including or skipping a field. Directives provide this by describing additional information to the executor.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isRepeatable","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"locations","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"ENUM","name":"__DirectiveLocation","ofType":null}}}},"isDeprecated":false,"deprecationReason":null},{"name":"args","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__InputValue","ofType":null}}}},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"ENUM","name":"__DirectiveLocation","description":"A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation describes one such possible adjacencies.","fields":null,"inputFields":null,"interfaces":null,"enumValues":[{"name":"QUERY","description":"Location adjacent to a query operation.","isDeprecated":false,"deprecationReason":null},{"name":"MUTATION","description":"Location adjacent to a mutation operation.","isDeprecated":false,"deprecationReason":null},{"name":"SUBSCRIPTION","description":"Location adjacent to a subscription operation.","isDeprecated":false,"deprecationReason":null},{"name":"FIELD","description":"Location adjacent to a field.","isDeprecated":false,"deprecationReason":null},{"name":"FRAGMENT_DEFINITION","description":"Location adjacent to a fragment definition.","isDeprecated":false,"deprecationReason":null},{"name":"FRAGMENT_SPREAD","description":"Location adjacent to a fragment spread.","isDeprecated":false,"deprecationReason":null},{"name":"INLINE_FRAGMENT","description":"Location adjacent to an inline fragment.","isDeprecated":false,"deprecationReason":null},{"name":"VARIABLE_DEFINITION","description":"Location adjacent to a variable definition.","isDeprecated":false,"deprecationReason":null},{"name":"SCHEMA","description":"Location adjacent to a schema definition.","isDeprecated":false,"deprecationReason":null},{"name":"SCALAR","description":"Location adjacent to a scalar definition.","isDeprecated":false,"deprecationReason":null},{"name":"OBJECT","description":"Location adjacent to an object type definition.","isDeprecated":false,"deprecationReason":null},{"name":"FIELD_DEFINITION","description":"Location adjacent to a field definition.","isDeprecated":false,"deprecationReason":null},{"name":"ARGUMENT_DEFINITION","description":"Location adjacent to an argument definition.","isDeprecated":false,"deprecationReason":null},{"name":"INTERFACE","description":"Location adjacent to an interface definition.","isDeprecated":false,"deprecationReason":null},{"name":"UNION","description":"Location adjacent to a union definition.","isDeprecated":false,"deprecationReason":null},{"name":"ENUM","description":"Location adjacent to an enum definition.","isDeprecated":false,"deprecationReason":null},{"name":"ENUM_VALUE","description":"Location adjacent to an enum value definition.","isDeprecated":false,"deprecationReason":null},{"name":"INPUT_OBJECT","description":"Location adjacent to an input object type definition.","isDeprecated":false,"deprecationReason":null},{"name":"INPUT_FIELD_DEFINITION","description":"Location adjacent to an input object field definition.","isDeprecated":false,"deprecationReason":null}],"possibleTypes":null}],"directives":[{"name":"include","description":"Directs the executor to include this field or fragment only when the \`if\` argument is true.","locations":["FIELD","FRAGMENT_SPREAD","INLINE_FRAGMENT"],"args":[{"name":"if","description":"Included when true.","type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"defaultValue":null}]},{"name":"skip","description":"Directs the executor to skip this field or fragment when the \`if\` argument is true.","locations":["FIELD","FRAGMENT_SPREAD","INLINE_FRAGMENT"],"args":[{"name":"if","description":"Skipped when true.","type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"defaultValue":null}]},{"name":"deprecated","description":"Marks an element of a GraphQL schema as no longer supported.","locations":["FIELD_DEFINITION","ARGUMENT_DEFINITION","INPUT_FIELD_DEFINITION","ENUM_VALUE"],"args":[{"name":"reason","description":"Explains why this element was deprecated, usually also including a suggestion for how to access supported similar data. Formatted using the Markdown syntax, as specified by [CommonMark](https://commonmark.org/).","type":{"kind":"SCALAR","name":"String","ofType":null},"defaultValue":"\\"No longer supported\\""}]},{"name":"specifiedBy","description":"Exposes a URL that specifies the behavior of this scalar.","locations":["SCALAR"],"args":[{"name":"url","description":"The URL that specifies the behavior of this scalar.","type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"defaultValue":null}]},{"name":"oneOf","description":"Indicates exactly one field must be supplied and this field must not be \`null\`.","locations":["INPUT_OBJECT"],"args":[]}]}}}
  `;

  // Directive Definition Tests

  describe("automatically adds a defer directive", () => {
    const documentString: string = `
    query BooksQuery {
      books {
        title
        ... on Book @defer(label: "deferredBookAuthor") {
          author
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("ensure the introspection JSON is correct for test", () => {
      const payload = JSON.parse(introspectionJSON).data;
      const schema = buildClientSchema(payload);
      const directives = schema.getDirectives()

      expect(directives.length).toEqual(5)
      expect(directives.map((value) => value.name).toString()).toEqual("include,skip,deprecated,specifiedBy,oneOf")
    });

    it("should pass validation as introspection source", () => {
      const schema = loadSchemaFromSources([new Source(introspectionJSON, "introspection_response.json")]);
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    });

    it("should convert to SDL and pass validation as SDL source", () => {
      const introspectionSchema = loadSchemaFromSources([new Source(introspectionJSON, "introspection_response.json")]);
      const sdlDocument = printSchemaToSDL(introspectionSchema)
      const sdlSchema = loadSchemaFromSources([new Source(sdlDocument, "schema.graphqls")]);
      const validationErrors: readonly GraphQLError[] = validateDocument(sdlSchema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    });
  })
});

describe("given introspection JSON with unsupported defer directive", () => {
  const introspectionJSON: string = `
  {"data":{"__schema":{"queryType":{"name":"Query"},"mutationType":null,"subscriptionType":null,"types":[{"kind":"OBJECT","name":"Book","description":null,"fields":[{"name":"title","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"author","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"SCALAR","name":"String","description":"The \`String\` scalar type represents textual data, represented as UTF-8 character sequences. The String type is most often used by GraphQL to represent free-form human-readable text.","fields":null,"inputFields":null,"interfaces":null,"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"Query","description":null,"fields":[{"name":"books","description":null,"args":[],"type":{"kind":"LIST","name":null,"ofType":{"kind":"OBJECT","name":"Book","ofType":null}},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"SCALAR","name":"Boolean","description":"The \`Boolean\` scalar type represents \`true\` or \`false\`.","fields":null,"inputFields":null,"interfaces":null,"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__Schema","description":"A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types and directives on the server, as well as the entry points for query, mutation, and subscription operations.","fields":[{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"types","description":"A list of all types supported by this server.","args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}}}},"isDeprecated":false,"deprecationReason":null},{"name":"queryType","description":"The type that query operations will be rooted at.","args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"mutationType","description":"If this server supports mutation, the type that mutation operations will be rooted at.","args":[],"type":{"kind":"OBJECT","name":"__Type","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"subscriptionType","description":"If this server support subscription, the type that subscription operations will be rooted at.","args":[],"type":{"kind":"OBJECT","name":"__Type","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"directives","description":"A list of all directives supported by this server.","args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Directive","ofType":null}}}},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__Type","description":"The fundamental unit of any GraphQL Schema is the type. There are many kinds of types in GraphQL as represented by the \`__TypeKind\` enum.\\n\\nDepending on the kind of a type, certain fields describe information about that type. Scalar types provide no information beyond a name, description and optional \`specifiedByURL\`, while Enum types provide their values. Object and Interface types provide the fields they describe. Abstract types, Union and Interface, provide the Object types possible at runtime. List and NonNull types compose other types.","fields":[{"name":"kind","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"ENUM","name":"__TypeKind","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"name","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"specifiedByURL","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"fields","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Field","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"interfaces","description":null,"args":[],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"possibleTypes","description":null,"args":[],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"enumValues","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__EnumValue","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"inputFields","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__InputValue","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"ofType","description":null,"args":[],"type":{"kind":"OBJECT","name":"__Type","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isOneOf","description":null,"args":[],"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"ENUM","name":"__TypeKind","description":"An enum describing what kind of type a given \`__Type\` is.","fields":null,"inputFields":null,"interfaces":null,"enumValues":[{"name":"SCALAR","description":"Indicates this type is a scalar.","isDeprecated":false,"deprecationReason":null},{"name":"OBJECT","description":"Indicates this type is an object. \`fields\` and \`interfaces\` are valid fields.","isDeprecated":false,"deprecationReason":null},{"name":"INTERFACE","description":"Indicates this type is an interface. \`fields\`, \`interfaces\`, and \`possibleTypes\` are valid fields.","isDeprecated":false,"deprecationReason":null},{"name":"UNION","description":"Indicates this type is a union. \`possibleTypes\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"ENUM","description":"Indicates this type is an enum. \`enumValues\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"INPUT_OBJECT","description":"Indicates this type is an input object. \`inputFields\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"LIST","description":"Indicates this type is a list. \`ofType\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"NON_NULL","description":"Indicates this type is a non-null. \`ofType\` is a valid field.","isDeprecated":false,"deprecationReason":null}],"possibleTypes":null},{"kind":"OBJECT","name":"__Field","description":"Object and Interface types are described by a list of Fields, each of which has a name, potentially a list of arguments, and a return type.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"args","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__InputValue","ofType":null}}}},"isDeprecated":false,"deprecationReason":null},{"name":"type","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"isDeprecated","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"deprecationReason","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__InputValue","description":"Arguments provided to Fields or Directives and the input fields of an InputObject are represented as Input Values which describe their type and optionally a default value.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"type","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"defaultValue","description":"A GraphQL-formatted string representing the default value for this input value.","args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isDeprecated","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"deprecationReason","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__EnumValue","description":"One possible value for a given Enum. Enum values are unique values, not a placeholder for a string or numeric value. However an Enum value is returned in a JSON response as a string.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isDeprecated","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"deprecationReason","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__Directive","description":"A Directive provides a way to describe alternate runtime execution and type validation behavior in a GraphQL document.\\n\\nIn some cases, you need to provide options to alter GraphQL's execution behavior in ways field arguments will not suffice, such as conditionally including or skipping a field. Directives provide this by describing additional information to the executor.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isRepeatable","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"locations","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"ENUM","name":"__DirectiveLocation","ofType":null}}}},"isDeprecated":false,"deprecationReason":null},{"name":"args","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__InputValue","ofType":null}}}},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"ENUM","name":"__DirectiveLocation","description":"A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation describes one such possible adjacencies.","fields":null,"inputFields":null,"interfaces":null,"enumValues":[{"name":"QUERY","description":"Location adjacent to a query operation.","isDeprecated":false,"deprecationReason":null},{"name":"MUTATION","description":"Location adjacent to a mutation operation.","isDeprecated":false,"deprecationReason":null},{"name":"SUBSCRIPTION","description":"Location adjacent to a subscription operation.","isDeprecated":false,"deprecationReason":null},{"name":"FIELD","description":"Location adjacent to a field.","isDeprecated":false,"deprecationReason":null},{"name":"FRAGMENT_DEFINITION","description":"Location adjacent to a fragment definition.","isDeprecated":false,"deprecationReason":null},{"name":"FRAGMENT_SPREAD","description":"Location adjacent to a fragment spread.","isDeprecated":false,"deprecationReason":null},{"name":"INLINE_FRAGMENT","description":"Location adjacent to an inline fragment.","isDeprecated":false,"deprecationReason":null},{"name":"VARIABLE_DEFINITION","description":"Location adjacent to a variable definition.","isDeprecated":false,"deprecationReason":null},{"name":"SCHEMA","description":"Location adjacent to a schema definition.","isDeprecated":false,"deprecationReason":null},{"name":"SCALAR","description":"Location adjacent to a scalar definition.","isDeprecated":false,"deprecationReason":null},{"name":"OBJECT","description":"Location adjacent to an object type definition.","isDeprecated":false,"deprecationReason":null},{"name":"FIELD_DEFINITION","description":"Location adjacent to a field definition.","isDeprecated":false,"deprecationReason":null},{"name":"ARGUMENT_DEFINITION","description":"Location adjacent to an argument definition.","isDeprecated":false,"deprecationReason":null},{"name":"INTERFACE","description":"Location adjacent to an interface definition.","isDeprecated":false,"deprecationReason":null},{"name":"UNION","description":"Location adjacent to a union definition.","isDeprecated":false,"deprecationReason":null},{"name":"ENUM","description":"Location adjacent to an enum definition.","isDeprecated":false,"deprecationReason":null},{"name":"ENUM_VALUE","description":"Location adjacent to an enum value definition.","isDeprecated":false,"deprecationReason":null},{"name":"INPUT_OBJECT","description":"Location adjacent to an input object type definition.","isDeprecated":false,"deprecationReason":null},{"name":"INPUT_FIELD_DEFINITION","description":"Location adjacent to an input object field definition.","isDeprecated":false,"deprecationReason":null}],"possibleTypes":null}],"directives":[{"name":"defer","description":null,"locations":["FIELD"],"args":[{"name":"label","description":null,"type":{"kind":"SCALAR","name":"String","ofType":null},"defaultValue":null},{"name":"if","description":null,"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"defaultValue":"true"}]},{"name":"include","description":"Directs the executor to include this field or fragment only when the \`if\` argument is true.","locations":["FIELD","FRAGMENT_SPREAD","INLINE_FRAGMENT"],"args":[{"name":"if","description":"Included when true.","type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"defaultValue":null}]},{"name":"skip","description":"Directs the executor to skip this field or fragment when the \`if\` argument is true.","locations":["FIELD","FRAGMENT_SPREAD","INLINE_FRAGMENT"],"args":[{"name":"if","description":"Skipped when true.","type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"defaultValue":null}]},{"name":"deprecated","description":"Marks an element of a GraphQL schema as no longer supported.","locations":["FIELD_DEFINITION","ARGUMENT_DEFINITION","INPUT_FIELD_DEFINITION","ENUM_VALUE"],"args":[{"name":"reason","description":"Explains why this element was deprecated, usually also including a suggestion for how to access supported similar data. Formatted using the Markdown syntax, as specified by [CommonMark](https://commonmark.org/).","type":{"kind":"SCALAR","name":"String","ofType":null},"defaultValue":"\\"No longer supported\\""}]},{"name":"specifiedBy","description":"Exposes a URL that specifies the behavior of this scalar.","locations":["SCALAR"],"args":[{"name":"url","description":"The URL that specifies the behavior of this scalar.","type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"defaultValue":null}]},{"name":"oneOf","description":"Indicates exactly one field must be supplied and this field must not be \`null\`.","locations":["INPUT_OBJECT"],"args":[]}]}}}
  `;

  // Directive Definition Tests

  describe("replaces unsupported defer directive with experimental supported definition", () => {
    const documentString: string = `
    query BooksQuery {
      books {
        title
        ... on Book @defer(label: "deferredBookAuthor") {
          author
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("ensure the introspection JSON is correct for test", () => {
      const payload = JSON.parse(introspectionJSON).data;
      const schema = buildClientSchema(payload);
      const directives = schema.getDirectives()

      expect(directives.length).toEqual(6)
      expect(directives.map((value) => value.name).toString()).toEqual("defer,include,skip,deprecated,specifiedBy,oneOf")

      const deferDirective = schema.getDirective(GraphQLDeferDirective.name)

      expect(deferDirective?.locations.toString()).toEqual("FIELD")
    });

    it("should pass validation as introspection source", () => {
      const schema = loadSchemaFromSources([new Source(introspectionJSON, "introspection_response.json")]);
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    });

    it("should convert to SDL and pass validation as SDL source", () => {
      const introspectionSchema = loadSchemaFromSources([new Source(introspectionJSON, "introspection_response.json")]);
      const sdlDocument = printSchemaToSDL(introspectionSchema)
      const sdlSchema = loadSchemaFromSources([new Source(sdlDocument, "schema.graphqls")]);
      const validationErrors: readonly GraphQLError[] = validateDocument(sdlSchema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    });
  })
});

describe("given introspection JSON with valid defer directive", () => {
  const introspectionJSON: string = `
  {"data":{"__schema":{"queryType":{"name":"Query"},"mutationType":null,"subscriptionType":null,"types":[{"kind":"OBJECT","name":"Book","description":null,"fields":[{"name":"title","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"author","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"SCALAR","name":"String","description":"The \`String\` scalar type represents textual data, represented as UTF-8 character sequences. The String type is most often used by GraphQL to represent free-form human-readable text.","fields":null,"inputFields":null,"interfaces":null,"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"Query","description":null,"fields":[{"name":"books","description":null,"args":[],"type":{"kind":"LIST","name":null,"ofType":{"kind":"OBJECT","name":"Book","ofType":null}},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"SCALAR","name":"Boolean","description":"The \`Boolean\` scalar type represents \`true\` or \`false\`.","fields":null,"inputFields":null,"interfaces":null,"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__Schema","description":"A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types and directives on the server, as well as the entry points for query, mutation, and subscription operations.","fields":[{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"types","description":"A list of all types supported by this server.","args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}}}},"isDeprecated":false,"deprecationReason":null},{"name":"queryType","description":"The type that query operations will be rooted at.","args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"mutationType","description":"If this server supports mutation, the type that mutation operations will be rooted at.","args":[],"type":{"kind":"OBJECT","name":"__Type","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"subscriptionType","description":"If this server support subscription, the type that subscription operations will be rooted at.","args":[],"type":{"kind":"OBJECT","name":"__Type","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"directives","description":"A list of all directives supported by this server.","args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Directive","ofType":null}}}},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__Type","description":"The fundamental unit of any GraphQL Schema is the type. There are many kinds of types in GraphQL as represented by the \`__TypeKind\` enum.\\n\\nDepending on the kind of a type, certain fields describe information about that type. Scalar types provide no information beyond a name, description and optional \`specifiedByURL\`, while Enum types provide their values. Object and Interface types provide the fields they describe. Abstract types, Union and Interface, provide the Object types possible at runtime. List and NonNull types compose other types.","fields":[{"name":"kind","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"ENUM","name":"__TypeKind","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"name","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"specifiedByURL","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"fields","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Field","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"interfaces","description":null,"args":[],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"possibleTypes","description":null,"args":[],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"enumValues","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__EnumValue","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"inputFields","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__InputValue","ofType":null}}},"isDeprecated":false,"deprecationReason":null},{"name":"ofType","description":null,"args":[],"type":{"kind":"OBJECT","name":"__Type","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isOneOf","description":null,"args":[],"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"ENUM","name":"__TypeKind","description":"An enum describing what kind of type a given \`__Type\` is.","fields":null,"inputFields":null,"interfaces":null,"enumValues":[{"name":"SCALAR","description":"Indicates this type is a scalar.","isDeprecated":false,"deprecationReason":null},{"name":"OBJECT","description":"Indicates this type is an object. \`fields\` and \`interfaces\` are valid fields.","isDeprecated":false,"deprecationReason":null},{"name":"INTERFACE","description":"Indicates this type is an interface. \`fields\`, \`interfaces\`, and \`possibleTypes\` are valid fields.","isDeprecated":false,"deprecationReason":null},{"name":"UNION","description":"Indicates this type is a union. \`possibleTypes\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"ENUM","description":"Indicates this type is an enum. \`enumValues\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"INPUT_OBJECT","description":"Indicates this type is an input object. \`inputFields\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"LIST","description":"Indicates this type is a list. \`ofType\` is a valid field.","isDeprecated":false,"deprecationReason":null},{"name":"NON_NULL","description":"Indicates this type is a non-null. \`ofType\` is a valid field.","isDeprecated":false,"deprecationReason":null}],"possibleTypes":null},{"kind":"OBJECT","name":"__Field","description":"Object and Interface types are described by a list of Fields, each of which has a name, potentially a list of arguments, and a return type.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"args","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__InputValue","ofType":null}}}},"isDeprecated":false,"deprecationReason":null},{"name":"type","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"isDeprecated","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"deprecationReason","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__InputValue","description":"Arguments provided to Fields or Directives and the input fields of an InputObject are represented as Input Values which describe their type and optionally a default value.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"type","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__Type","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"defaultValue","description":"A GraphQL-formatted string representing the default value for this input value.","args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isDeprecated","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"deprecationReason","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__EnumValue","description":"One possible value for a given Enum. Enum values are unique values, not a placeholder for a string or numeric value. However an Enum value is returned in a JSON response as a string.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isDeprecated","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"deprecationReason","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"OBJECT","name":"__Directive","description":"A Directive provides a way to describe alternate runtime execution and type validation behavior in a GraphQL document.\\n\\nIn some cases, you need to provide options to alter GraphQL's execution behavior in ways field arguments will not suffice, such as conditionally including or skipping a field. Directives provide this by describing additional information to the executor.","fields":[{"name":"name","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"description","description":null,"args":[],"type":{"kind":"SCALAR","name":"String","ofType":null},"isDeprecated":false,"deprecationReason":null},{"name":"isRepeatable","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"isDeprecated":false,"deprecationReason":null},{"name":"locations","description":null,"args":[],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"ENUM","name":"__DirectiveLocation","ofType":null}}}},"isDeprecated":false,"deprecationReason":null},{"name":"args","description":null,"args":[{"name":"includeDeprecated","description":null,"type":{"kind":"SCALAR","name":"Boolean","ofType":null},"defaultValue":"false"}],"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"LIST","name":null,"ofType":{"kind":"NON_NULL","name":null,"ofType":{"kind":"OBJECT","name":"__InputValue","ofType":null}}}},"isDeprecated":false,"deprecationReason":null}],"inputFields":null,"interfaces":[],"enumValues":null,"possibleTypes":null},{"kind":"ENUM","name":"__DirectiveLocation","description":"A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation describes one such possible adjacencies.","fields":null,"inputFields":null,"interfaces":null,"enumValues":[{"name":"QUERY","description":"Location adjacent to a query operation.","isDeprecated":false,"deprecationReason":null},{"name":"MUTATION","description":"Location adjacent to a mutation operation.","isDeprecated":false,"deprecationReason":null},{"name":"SUBSCRIPTION","description":"Location adjacent to a subscription operation.","isDeprecated":false,"deprecationReason":null},{"name":"FIELD","description":"Location adjacent to a field.","isDeprecated":false,"deprecationReason":null},{"name":"FRAGMENT_DEFINITION","description":"Location adjacent to a fragment definition.","isDeprecated":false,"deprecationReason":null},{"name":"FRAGMENT_SPREAD","description":"Location adjacent to a fragment spread.","isDeprecated":false,"deprecationReason":null},{"name":"INLINE_FRAGMENT","description":"Location adjacent to an inline fragment.","isDeprecated":false,"deprecationReason":null},{"name":"VARIABLE_DEFINITION","description":"Location adjacent to a variable definition.","isDeprecated":false,"deprecationReason":null},{"name":"SCHEMA","description":"Location adjacent to a schema definition.","isDeprecated":false,"deprecationReason":null},{"name":"SCALAR","description":"Location adjacent to a scalar definition.","isDeprecated":false,"deprecationReason":null},{"name":"OBJECT","description":"Location adjacent to an object type definition.","isDeprecated":false,"deprecationReason":null},{"name":"FIELD_DEFINITION","description":"Location adjacent to a field definition.","isDeprecated":false,"deprecationReason":null},{"name":"ARGUMENT_DEFINITION","description":"Location adjacent to an argument definition.","isDeprecated":false,"deprecationReason":null},{"name":"INTERFACE","description":"Location adjacent to an interface definition.","isDeprecated":false,"deprecationReason":null},{"name":"UNION","description":"Location adjacent to a union definition.","isDeprecated":false,"deprecationReason":null},{"name":"ENUM","description":"Location adjacent to an enum definition.","isDeprecated":false,"deprecationReason":null},{"name":"ENUM_VALUE","description":"Location adjacent to an enum value definition.","isDeprecated":false,"deprecationReason":null},{"name":"INPUT_OBJECT","description":"Location adjacent to an input object type definition.","isDeprecated":false,"deprecationReason":null},{"name":"INPUT_FIELD_DEFINITION","description":"Location adjacent to an input object field definition.","isDeprecated":false,"deprecationReason":null}],"possibleTypes":null}],"directives":[{"name":"defer","description":null,"locations":["FRAGMENT_SPREAD","INLINE_FRAGMENT"],"args":[{"name":"label","description":null,"type":{"kind":"SCALAR","name":"String","ofType":null},"defaultValue":null},{"name":"if","description":null,"type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"defaultValue":"true"}]},{"name":"include","description":"Directs the executor to include this field or fragment only when the \`if\` argument is true.","locations":["FIELD","FRAGMENT_SPREAD","INLINE_FRAGMENT"],"args":[{"name":"if","description":"Included when true.","type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"defaultValue":null}]},{"name":"skip","description":"Directs the executor to skip this field or fragment when the \`if\` argument is true.","locations":["FIELD","FRAGMENT_SPREAD","INLINE_FRAGMENT"],"args":[{"name":"if","description":"Skipped when true.","type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"Boolean","ofType":null}},"defaultValue":null}]},{"name":"deprecated","description":"Marks an element of a GraphQL schema as no longer supported.","locations":["FIELD_DEFINITION","ARGUMENT_DEFINITION","INPUT_FIELD_DEFINITION","ENUM_VALUE"],"args":[{"name":"reason","description":"Explains why this element was deprecated, usually also including a suggestion for how to access supported similar data. Formatted using the Markdown syntax, as specified by [CommonMark](https://commonmark.org/).","type":{"kind":"SCALAR","name":"String","ofType":null},"defaultValue":"\\"No longer supported\\""}]},{"name":"specifiedBy","description":"Exposes a URL that specifies the behavior of this scalar.","locations":["SCALAR"],"args":[{"name":"url","description":"The URL that specifies the behavior of this scalar.","type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String","ofType":null}},"defaultValue":null}]},{"name":"oneOf","description":"Indicates exactly one field must be supplied and this field must not be \`null\`.","locations":["INPUT_OBJECT"],"args":[]}]}}}
  `;

  // Directive Definition Tests

  describe("does not add a duplicate directive", () => {
    const documentString: string = `
    query BooksQuery {
      books {
        title
        ... on Book @defer(label: "deferredBookAuthor") {
          author
        }
      }
    }
    `;

    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    it("ensure the introspection JSON is correct for test", () => {
      const payload = JSON.parse(introspectionJSON).data;
      const schema = buildClientSchema(payload);
      const directives = schema.getDirectives()

      expect(directives.length).toEqual(6)
      expect(directives.map((value) => value.name).toString()).toEqual("defer,include,skip,deprecated,specifiedBy,oneOf")

      const deferDirective = schema.getDirective(GraphQLDeferDirective.name)

      expect(deferDirective?.locations.toString()).toEqual("FRAGMENT_SPREAD,INLINE_FRAGMENT")
    });

    it("should pass validation as introspection source", () => {
      const schema = loadSchemaFromSources([new Source(introspectionJSON, "introspection_response.json")]);
      const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    });

    it("should convert to SDL and pass validation as SDL source", () => {
      const introspectionSchema = loadSchemaFromSources([new Source(introspectionJSON, "introspection_response.json")]);
      const sdlDocument = printSchemaToSDL(introspectionSchema)
      const sdlSchema = loadSchemaFromSources([new Source(sdlDocument, "schema.graphqls")]);
      const validationErrors: readonly GraphQLError[] = validateDocument(sdlSchema, document, emptyValidationOptions)

      expect(validationErrors).toHaveLength(0)
    });
  })
});
