import { 
  // compileDocument,
  parseOperationDocument,
  loadSchemaFromSources,
  validateDocument,
} from "../index"
import { 
  Source,
  GraphQLSchema,
  DocumentNode,
  GraphQLError
} from "graphql";
import { emptyValidationOptions } from "../__testUtils__/validationHelpers";

describe("given schema", () => {
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

  const schema: GraphQLSchema = loadSchemaFromSources([new Source(schemaSDL, "Test Schema", { line: 1, column: 1 })]);

  // Disabling Tests

  describe("query has inline fragment with @defer directive", () => {
    const documentString: string = `
    query Test {
      allAnimals {
        ... on Animal @defer {
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
        "@defer support is disabled until the implementation is complete."
      )
    });
  });

  describe("query has fragment spread with @defer directive", () => {
  const documentString: string = `
  query Test {
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

  it("should fail validation", () => {
    const validationErrors: readonly GraphQLError[] = validateDocument(schema, document, emptyValidationOptions)

    expect(validationErrors).toHaveLength(1)
    expect(validationErrors[0].message).toEqual(
      "@defer support is disabled until the implementation is complete."
    )
  });
});

});
