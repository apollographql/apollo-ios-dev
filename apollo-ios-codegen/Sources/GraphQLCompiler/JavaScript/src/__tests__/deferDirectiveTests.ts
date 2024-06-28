import { 
  compileDocument,
  parseOperationDocument,
  loadSchemaFromSources,
  validateDocument,
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
  parse
} from "graphql";
import { emptyValidationOptions } from "../__testUtils__/validationHelpers";

describe("given schema SDL without any defer directive", () => {
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

describe("given schema with unsupported defer directive", () => {
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

describe("given schema with valid defer directive", () => {
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

});
