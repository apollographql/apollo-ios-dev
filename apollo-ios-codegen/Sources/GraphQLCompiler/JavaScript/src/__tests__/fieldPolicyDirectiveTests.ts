import {
  GraphQLError,
  type GraphQLNamedType,
  type GraphQLSchema,
  Source,
} from "graphql";
import { loadSchemaFromSources } from "..";

type ObjectWithMeta = GraphQLNamedType & {
  _apolloFieldPolicies: Record<string, string[]>;
};

describe("given SDL without fieldPolicy", () => {
  const schemaSDL: string = `
  type Query {
    allRectangles(ids: [ID!]): [Rectangle!]
  }

  interface Shape {
    surface: Int!
  }

  type Rectangle {
    width: Int!
    height: Int!
  }
  `;

  it("should set empty _apolloFieldPolicies property", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const rect = schema.getTypeMap()["Rectangle"] as ObjectWithMeta;
    expect(Object.keys(rect._apolloFieldPolicies)).toHaveLength(0);

    const shape = schema.getTypeMap()["Shape"] as ObjectWithMeta;
    expect(Object.keys(shape._apolloFieldPolicies)).toHaveLength(0);
  });
});

describe("given SDL with valid fieldPolicy", () => {
  const schemaSDL: string = `
  type Query {
    allRectangles(withWidth: Int!): [Rectangle!]
  }

  type Rectangle {
    width: Int!
    height: Int!
  }

  extend type Query @fieldPolicy(forField: "allRectangles", keyArgs: "withWidth")
  `;

  it("should set _apolloFieldPolicies property", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const queryType = schema.getTypeMap()["Query"] as ObjectWithMeta;
    expect(queryType._apolloFieldPolicies).toBeDefined();
    expect(Object.keys(queryType._apolloFieldPolicies!)).toHaveLength(1);
    expect(queryType._apolloFieldPolicies).toHaveProperty("allRectangles");
    expect(queryType._apolloFieldPolicies?.allRectangles).toEqual(["withWidth"]);
  });
});

describe("given fieldPolicy on interface extension", () => {
  const schemaSDL: string = `
  interface Animal {
    allAnimals(ofSpecies: String): [Animal!]

    id: ID!
    species: String!
  }

  type Dog implements Animal {
    allAnimals(ofSpecies: String): [Animal!]

    id: ID!
    species: String!
    owner: String
  }

  extend interface Animal @fieldPolicy(forField: "allAnimals", keyArgs: "ofSpecies")
  `;

  it("should set _apolloFieldPolicies property", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const animalType = schema.getTypeMap()["Animal"] as ObjectWithMeta;
    expect(animalType._apolloFieldPolicies).toBeDefined();
    expect(Object.keys(animalType._apolloFieldPolicies!)).toHaveLength(1);

    const dogType = schema.getTypeMap()["Dog"] as ObjectWithMeta;
    expect(dogType._apolloFieldPolicies).toBeDefined();
    expect(Object.keys(dogType._apolloFieldPolicies!)).toHaveLength(1);
  });
});

describe("given fieldPolicy on interface and object extensions", () => {
  const schemaSDL: string = `
  interface Animal {
    allAnimals(ofSpecies: String): [Animal!]

    id: ID!
    species: String!
  }

  type Dog implements Animal {
    allAnimals(ofSpecies: String): [Animal!]

    id: ID!
    species: String!
    owner: String
  }

  extend interface Animal @fieldPolicy(forField: "allAnimals", keyArgs: "ofSpecies")
  extend type Dog @fieldPolicy(forField: "allAnimals", keyArgs: "ofSpecies")
  `;

  it("should set _apolloFieldPolicies property without duplicates.", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const animalType = schema.getTypeMap()["Animal"] as ObjectWithMeta;
    expect(animalType._apolloFieldPolicies).toBeDefined();
    expect(Object.keys(animalType._apolloFieldPolicies!)).toHaveLength(1);

    const dogType = schema.getTypeMap()["Dog"] as ObjectWithMeta;
    expect(dogType._apolloFieldPolicies).toBeDefined();
    expect(Object.keys(dogType._apolloFieldPolicies!)).toHaveLength(1);
  });
});

describe("given fieldPolicy on interface", () => {
  const schemaSDL: string = `
  interface Animal @fieldPolicy(forField: "allAnimals", keyArgs: "ofSpecies") {
    allAnimals(ofSpecies: String): [Animal!]

    id: ID!
    species: String!
  }

  type Dog implements Animal {
    allAnimals(ofSpecies: String): [Animal!]

    id: ID!
    species: String!
    owner: String
  }
  `;

  it("should set _apolloFieldPolicies property", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const animalType = schema.getTypeMap()["Animal"] as ObjectWithMeta;
    expect(animalType._apolloFieldPolicies).toBeDefined();
    expect(Object.keys(animalType._apolloFieldPolicies!)).toHaveLength(1);

    const dogType = schema.getTypeMap()["Dog"] as ObjectWithMeta;
    expect(dogType._apolloFieldPolicies).toBeDefined();
    expect(Object.keys(dogType._apolloFieldPolicies!)).toHaveLength(1);
  });
});

describe("given fieldPolicy on interface and object", () => {
  const schemaSDL: string = `
  interface Animal @fieldPolicy(forField: "allAnimals", keyArgs: "ofSpecies") {
    allAnimals(ofSpecies: String): [Animal!]

    id: ID!
    species: String!
  }

  type Dog implements Animal @fieldPolicy(forField: "allAnimals", keyArgs: "ofSpecies") {
    allAnimals(ofSpecies: String): [Animal!]

    id: ID!
    species: String!
    owner: String
  }
  `;

  it("should set _apolloFieldPolicies property", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const animalType = schema.getTypeMap()["Animal"] as ObjectWithMeta;
    expect(animalType._apolloFieldPolicies).toBeDefined();
    expect(Object.keys(animalType._apolloFieldPolicies!)).toHaveLength(1);

    const dogType = schema.getTypeMap()["Dog"] as ObjectWithMeta;
    expect(dogType._apolloFieldPolicies).toBeDefined();
    expect(Object.keys(dogType._apolloFieldPolicies!)).toHaveLength(1);
  });
});

describe("given field with list inputs and non-list return type", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID]!): Animal!
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIDs")
  `;

  it("should throw error requiring List return type", () => {
    expect(() =>
      loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ])
    ).toThrow(GraphQLError);
  });
});

describe("given field with list inputs and list return type", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID]!): [Animal!]
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIds")
  `;

  it("should throw error requiring List return type", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const queryType = schema.getTypeMap()["Query"] as ObjectWithMeta;
    expect(queryType._apolloFieldPolicies).toBeDefined();
    expect(Object.keys(queryType._apolloFieldPolicies!)).toHaveLength(1);
    expect(queryType._apolloFieldPolicies).toHaveProperty("allAnimals");
    expect(queryType._apolloFieldPolicies?.allAnimals).toEqual(["withIds"]);
  });
});

describe("given field policy with multiple valid keyArgs", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID]!, andSpecies: String!): [Animal!]
  }

  type Animal {
    id: ID!
    name: String!
    species: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIds andSpecies")
  `;

  it("should set _apolloFieldPolicies property", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const queryType = schema.getTypeMap()["Query"] as ObjectWithMeta;
    expect(queryType._apolloFieldPolicies).toBeDefined();
    expect(Object.keys(queryType._apolloFieldPolicies!)).toHaveLength(1);
    expect(queryType._apolloFieldPolicies).toHaveProperty("allAnimals");
    expect(queryType._apolloFieldPolicies?.allAnimals).toEqual(["withIds", "andSpecies"]);
  });
});

describe("given field policy with one invalid keyArg", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID]!, andSpecies: String!): [Animal!]
  }

  type Animal {
    id: ID!
    name: String!
    species: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIds andName")
  `;

  it("should throw error for invalid keyArgs", () => {
    expect(() =>
      loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ])
    ).toThrow(GraphQLError);
  });
});