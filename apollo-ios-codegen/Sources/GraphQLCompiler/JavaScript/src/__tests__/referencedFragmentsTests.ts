import {
  compileDocument,
  parseOperationDocument,
  loadSchemaFromSources,
  mergeDocuments,
} from "../index"
import {
  CompilationResult
} from "../compiler/index"
import {
  FragmentDefinition,
  OperationDefinition
} from "../compiler/ir"
import {
  Source,
  GraphQLSchema,
  DocumentNode
} from "graphql";
import { emptyValidationOptions } from "../__testUtils__/validationHelpers";

describe("operation with referencedFragments", () => {
  const operationADocument: DocumentNode = parseOperationDocument(
    new Source( `
    query OperationA {
      ...FragmentA
      ...FragmentC
    }
    `, "OperationA", { line: 1, column: 1 })
  );

  const fragmentADocument: DocumentNode = parseOperationDocument(
    new Source( `
    fragment FragmentA on Query {
      a
      ...FragmentB
    }
    `, "FragmentA", { line: 1, column: 1 })
  );

  const fragmentBDocument: DocumentNode = parseOperationDocument(
    new Source( `
    fragment FragmentB on Query {
      b
    }
    `, "FragmentB", { line: 1, column: 1 })
  );

  const fragmentCDocument: DocumentNode = parseOperationDocument(
    new Source( `
    fragment FragmentC on Query {
      c
    }
    `, "FragmentC", { line: 1, column: 1 })
  );

  const schema: GraphQLSchema = loadSchemaFromSources([new Source(`
  type Query {
    a: String!
    b: String!
    c: String!
  }
  `,
   "Test Schema", { line: 1, column: 1 })]);

  const document: DocumentNode = mergeDocuments([
    operationADocument,
    fragmentADocument,
    fragmentBDocument,
    fragmentCDocument])

  const compilationResult: CompilationResult = compileDocument(schema, document, false, emptyValidationOptions);

  const operationA: OperationDefinition = compilationResult.operations.find(function(element) {
    return element.name == 'OperationA'
  }) as OperationDefinition

  const fragmentA: FragmentDefinition = compilationResult.fragments.find(function(element) {
    return element.name == 'FragmentA'
  }) as FragmentDefinition

  const fragmentB: FragmentDefinition = compilationResult.fragments.find(function(element) {
    return element.name == 'FragmentB'
  }) as FragmentDefinition

  const fragmentC: FragmentDefinition = compilationResult.fragments.find(function(element) {
    return element.name == 'FragmentC'
  }) as FragmentDefinition

  it("compilation result OperationA should have referencedFragments including only directly referenced fragments.", () => {
    expect(operationA.referencedFragments).toEqual([fragmentA, fragmentC])
  });

  it("compilation result FragmentA should have referencedFragments including only directly referenced fragments.", () => {
    expect(fragmentA.referencedFragments).toEqual([fragmentB])
  });

});

describe("operation with referencedFragments on child entity selection sets", () => {
  const operationADocument: DocumentNode = parseOperationDocument(
    new Source( `
    query OperationA {
      a {
        ...FragmentA
      }
      ...FragmentC
    }
    `, "OperationA", { line: 1, column: 1 })
  );

  const fragmentADocument: DocumentNode = parseOperationDocument(
    new Source( `
    fragment FragmentA on A {
      A
      b {
        ...FragmentB
      }
    }
    `, "FragmentA", { line: 1, column: 1 })
  );

  const fragmentBDocument: DocumentNode = parseOperationDocument(
    new Source( `
    fragment FragmentB on B {
      B
    }
    `, "FragmentB", { line: 1, column: 1 })
  );

  const fragmentCDocument: DocumentNode = parseOperationDocument(
    new Source( `
    fragment FragmentC on Query {
      c
    }
    `, "FragmentC", { line: 1, column: 1 })
  );

  const schema: GraphQLSchema = loadSchemaFromSources([new Source(`
  type Query {
    a: A!
    b: B!
    c: String!
  }
  type A {
    A: String!
    b: B!
  }
  type B {
    B: String!
  }
  `,
   "Test Schema", { line: 1, column: 1 })]);

  const document: DocumentNode = mergeDocuments([
    operationADocument,
    fragmentADocument,
    fragmentBDocument,
    fragmentCDocument])

  const compilationResult: CompilationResult = compileDocument(schema, document, false, emptyValidationOptions);

  const operationA: OperationDefinition = compilationResult.operations.find(function(element) {
    return element.name == 'OperationA'
  }) as OperationDefinition

  const fragmentA: FragmentDefinition = compilationResult.fragments.find(function(element) {
    return element.name == 'FragmentA'
  }) as FragmentDefinition

  const fragmentB: FragmentDefinition = compilationResult.fragments.find(function(element) {
    return element.name == 'FragmentB'
  }) as FragmentDefinition

  const fragmentC: FragmentDefinition = compilationResult.fragments.find(function(element) {
    return element.name == 'FragmentC'
  }) as FragmentDefinition

  it("compilation result OperationA should have referencedFragments including only directly referenced fragments.", () => {
    expect(operationA.referencedFragments).toEqual([fragmentA, fragmentC])
  });

  it("compilation result FragmentA should have referencedFragments including only directly referenced fragments.", () => {
    expect(fragmentA.referencedFragments).toEqual([fragmentB])
  });

});
