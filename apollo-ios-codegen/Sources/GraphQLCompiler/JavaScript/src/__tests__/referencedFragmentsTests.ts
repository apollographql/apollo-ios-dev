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

  const compilationResult: CompilationResult = compileDocument(schema, document, false, false, emptyValidationOptions);

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

  const compilationResult: CompilationResult = compileDocument(schema, document, false, false, emptyValidationOptions);

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

describe("local cache mutation operation with referenced fragments", () => {
  const schemaSDL: string =
`type Query {
  allAnimals: [Animal!]
}

interface Animal {
  species: String!
  friend: Animal!
}`;

  const schema: GraphQLSchema = loadSchemaFromSources([new Source(schemaSDL, "Test Schema", { line: 1, column: 1 })]);

  const documentString: string =
`query Test @apollo_client_ios_localCacheMutation {
  allAnimals {
    ...SpeciesFragment
  }
}

fragment SpeciesFragment on Animal {
  species
  ...FriendFragment
}

fragment FriendFragment on Animal {
  friend {
    species
  }
}`;

  const document: DocumentNode = parseOperationDocument(
    new Source(documentString, "Test Query", { line: 1, column: 1 })
  );

  it("should flag the referenced fragments as being local cache mutations too.", () => {
    const compilationResult: CompilationResult = compileDocument(schema, document, false, false, emptyValidationOptions);

    const speciesFragment: FragmentDefinition = compilationResult.fragments.find(function (element) {
      return element.name == 'SpeciesFragment'
    }) as FragmentDefinition
    const friendFragment: FragmentDefinition = compilationResult.fragments.find(function (element) {
      return element.name == 'FriendFragment'
    }) as FragmentDefinition

    expect(speciesFragment.overrideAsLocalCacheMutation).toBeTruthy();
    expect(friendFragment.overrideAsLocalCacheMutation).toBeTruthy();
  });
});

describe("local cache mutation fragment with referenced fragments", () => {
  const schemaSDL: string =
`type Query {
  allAnimals: [Animal!]
}

interface Animal {
  name: String!
  species: String!
  friend: Animal!
}`;

  const schema: GraphQLSchema = loadSchemaFromSources([new Source(schemaSDL, "Test Schema", { line: 1, column: 1 })]);

  const documentString: string =
`query Test {
  allAnimals {
    ...NameFragment
    ...SpeciesFragment
  }
}

fragment NameFragment on Animal {
  name
}

fragment SpeciesFragment on Animal @apollo_client_ios_localCacheMutation {
  species
  ...FriendFragment
}

fragment FriendFragment on Animal {
  friend {
    species
  }
}`;

  const document: DocumentNode = parseOperationDocument(
    new Source(documentString, "Test Query", { line: 1, column: 1 })
  );

  it("should only flag the cache mutation referenced fragment as being local cache mutation.", () => {
    const compilationResult: CompilationResult = compileDocument(schema, document, false, false, emptyValidationOptions);
    
    const nameFragment: FragmentDefinition = compilationResult.fragments.find(function (element) {
      return element.name == 'NameFragment'
    }) as FragmentDefinition
    const speciesFragment: FragmentDefinition = compilationResult.fragments.find(function (element) {
      return element.name == 'SpeciesFragment'
    }) as FragmentDefinition
    const friendFragment: FragmentDefinition = compilationResult.fragments.find(function (element) {
      return element.name == 'FriendFragment'
    }) as FragmentDefinition

    expect(nameFragment.overrideAsLocalCacheMutation).toBeFalsy();
    expect(speciesFragment.overrideAsLocalCacheMutation).toBeFalsy();

    expect(friendFragment.overrideAsLocalCacheMutation).toBeTruthy();
  });
});
