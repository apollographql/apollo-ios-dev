import {
  compileDocument,
  parseOperationDocument,
  loadSchemaFromSources,
} from "../index"
import {
  CompilationResult
} from "../compiler/index"
import {
  Source,
  GraphQLSchema,
  DocumentNode,
  GraphQLEnumType,
  GraphQLInputObjectType,
  GraphQLInterfaceType,
} from "graphql";
import {
  readFileSync
} from "fs"
import {
  join
} from 'path';
import { emptyValidationOptions } from "../__testUtils__/validationHelpers";

describe("mutation defined using ReportCarProblemInput", () => {
  const documentString: string = `
  mutation Test($input: ReportCarProblemInput!) {
    mutateCar(input: $input) {
      name
    }
  }
  `;

  const document: DocumentNode = parseOperationDocument(
    new Source(documentString, "Test Mutation", { line: 1, column: 1 })
  );

  describe("given schema from introspection JSON with mutation using input type with enum field", () => {
    const schemaJSON: string = readFileSync(join(__dirname, "./input-object-enum-test-schema.json"), 'utf-8')
    const schema: GraphQLSchema = loadSchemaFromSources([new Source(schemaJSON, "TestSchema.json", { line: 1, column: 1 })]);

    it("should compile with referencedTypes including ReportCarProblemInput and CarProblem enum", () => {
      const compilationResult: CompilationResult = compileDocument(schema, document, false, false, emptyValidationOptions);
      const reportCarProblemInput: GraphQLInputObjectType = compilationResult.referencedTypes.find(function(element) {
        return element.name == 'ReportCarProblemInput'
      }) as GraphQLInputObjectType
      const carProblemEnum: GraphQLEnumType = compilationResult.referencedTypes.find(function(element) {
        return element.name == 'CarProblem'
      }) as GraphQLEnumType

      expect(reportCarProblemInput).not.toBeUndefined()
      expect(carProblemEnum).not.toBeUndefined()
    });
  });

  describe("given schema from SDL with mutation using input type with enum field", () => {
    const schemaSDL: string = `
    type Query {
      cars: [Car!]
    }

    type Mutation {
      mutateCar(input: ReportCarProblemInput!): Car!
    }

    input ReportCarProblemInput {
      problem: CarProblem!
    }

    enum CarProblem {
      RADIATOR
    }

    interface Car {
      name: String!
    }
    `;

    const schema: GraphQLSchema = loadSchemaFromSources([new Source(schemaSDL, "Test Schema", { line: 1, column: 1 })]);

    it("should compile with referencedTypes inlcuding InputObject and enum", () => {
      const compilationResult: CompilationResult = compileDocument(schema, document, false, false, emptyValidationOptions);
      const reportCarProblemInput: GraphQLInputObjectType = compilationResult.referencedTypes.find(function(element) {
        return element.name == 'ReportCarProblemInput'
      }) as GraphQLInputObjectType
      const carProblemEnum: GraphQLEnumType = compilationResult.referencedTypes.find(function(element) {
        return element.name == 'CarProblem'
      }) as GraphQLEnumType

      expect(reportCarProblemInput).not.toBeUndefined()
      expect(carProblemEnum).not.toBeUndefined()
    });
  });
});

describe("query with selections", () => {
  const documentString: string = `
  query fetchMyString {
    missingInterfaceString
  }
  `;

  const document: DocumentNode = parseOperationDocument(
    new Source(documentString, "Test Query", { line: 1, column: 1 })
  );

  describe("given interface on root query", () => {
    const schemaSDL: string = `
    interface MissingInterface {
      missingInterfaceString: String!
    }

    type Query implements MissingInterface {
      missingInterfaceString: String!
    }
    `;

    const schema: GraphQLSchema = loadSchemaFromSources([new Source(schemaSDL, "Test Schema", { line: 1, column: 1 })]);

    it("should compile with referencedTypes including interface", () => {
      const compilationResult: CompilationResult = compileDocument(schema, document, false, false, emptyValidationOptions);
      const validInterface: GraphQLInterfaceType = compilationResult.referencedTypes.find(function(element) {
        return element.name == 'MissingInterface'
      }) as GraphQLInterfaceType

      expect(validInterface).not.toBeUndefined()
    });
  });
});

describe("reduceGeneratedSchemaTypes with interface inline fragment", () => {
  const schemaSDL: string = `
    interface Node {
      id: ID!
    }

    interface NamedNode implements Node {
      id: ID!
      name: String!
    }

    type ConcreteNamedNode implements Node & NamedNode {
      id: ID!
      name: String!
    }

    type ConcreteNode implements Node {
      id: ID!
    }

    type Query {
      node: Node!
    }
  `;

  const schema: GraphQLSchema = loadSchemaFromSources([
    new Source(schemaSDL, "Test Schema", { line: 1, column: 1 })
  ]);

  it("includes implementing objects of an interface used as a type condition", () => {
    const documentString: string = `
      query GetNode {
        node {
          id
          ... on NamedNode {
            name
          }
        }
      }
    `;
    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    const result: CompilationResult = compileDocument(
      schema, document, false, true, emptyValidationOptions
    );

    const concreteNamedNode = result.referencedTypes.find(t => t.name === "ConcreteNamedNode");
    expect(concreteNamedNode).not.toBeUndefined();
  });

  it("excludes implementing objects of an interface used only as a field return type", () => {
    const documentString: string = `
      query GetNode {
        node {
          id
        }
      }
    `;
    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    const result: CompilationResult = compileDocument(
      schema, document, false, true, emptyValidationOptions
    );

    const concreteNamedNode = result.referencedTypes.find(t => t.name === "ConcreteNamedNode");
    const concreteNode = result.referencedTypes.find(t => t.name === "ConcreteNode");
    expect(concreteNamedNode).toBeUndefined();
    expect(concreteNode).toBeUndefined();
  });

  it("includes implementing objects when the same interface appears as both a field type and a type condition", () => {
    const documentString: string = `
      query GetNode {
        node {
          id
          ... on Node {
            id
          }
        }
      }
    `;
    const document: DocumentNode = parseOperationDocument(
      new Source(documentString, "Test Query", { line: 1, column: 1 })
    );

    const result: CompilationResult = compileDocument(
      schema, document, false, true, emptyValidationOptions
    );

    const concreteNamedNode = result.referencedTypes.find(t => t.name === "ConcreteNamedNode");
    const concreteNode = result.referencedTypes.find(t => t.name === "ConcreteNode");
    expect(concreteNamedNode).not.toBeUndefined();
    expect(concreteNode).not.toBeUndefined();
  });
});
