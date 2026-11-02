import {
  GraphQLError,
  GraphQLField,
  type GraphQLSchema,
  Source,
} from "graphql";
import { loadSchemaFromSources } from "..";
// import { Field } from "../compiler/ir";

type FieldWithMeta = GraphQLField & {
  _apolloFieldPolicies: string[];
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

    const rectType = schema.getTypeMap()["Rectangle"];
    if (!rectType || !("getFields" in rectType)) throw new Error("Missing Rectangle type.");

    const rectFields = rectType.getFields();
    for (const fieldName in rectFields) {
      const field = rectFields[fieldName] as FieldWithMeta;
      expect(field._apolloFieldPolicies ?? []).toEqual([]);
    }

    const shape = schema.getTypeMap()["Shape"];
    if (!shape || !("getFields" in shape)) throw new Error("Missing Shape type.");

    const shapeFields = shape.getFields();
    for (const fieldName in shapeFields) {
      const field = shapeFields[fieldName] as FieldWithMeta;
      expect(field._apolloFieldPolicies ?? []).toEqual([]);
    }
  });
});

describe("given SDL with valid fieldPolicy", () => {
  const schemaSDL: string = `
  type Query {
    rectangle(withWidth: Int!): Rectangle!
  }

  type Rectangle {
    width: Int!
    height: Int!
  }

  extend type Query @fieldPolicy(forField: "rectangle", keyArgs: "withWidth")
  `;

  it("should set _apolloFieldPolicies property", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const queryType = schema.getTypeMap()["Query"];
    if (!queryType || !("getFields" in queryType)) throw new Error("Missing Query type.");

    const queryFields = queryType.getFields();
    for (const fieldName in queryFields) {
      const field = queryFields[fieldName] as FieldWithMeta;
      expect(fieldName).toEqual("rectangle");
      expect(field._apolloFieldPolicies).toHaveLength(1);
      expect(field._apolloFieldPolicies).toContain("withWidth");
    }
  });
});

describe("given fieldPolicy on interface extension", () => {
  const schemaSDL: string = `
  interface Animal {
    animal(withName: String): Animal!

    id: ID!
    species: String!
  }

  type Dog implements Animal {
    animal(withName: String): Animal!

    id: ID!
    species: String!
    owner: String
  }

  extend interface Animal @fieldPolicy(forField: "animal", keyArgs: "withName")
  `;

  it("should set _apolloFieldPolicies property", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const animalType = schema.getTypeMap()["Animal"];
    if (!animalType || !("getFields" in animalType)) throw new Error("Missing Animal type.");

    const animalFields = animalType.getFields();
    for (const fieldName in animalFields) {
      const field = animalFields[fieldName] as FieldWithMeta;
      if (fieldName == "animal") {
        expect(field._apolloFieldPolicies).toHaveLength(1);
        expect(field._apolloFieldPolicies).toContain("withName")
      } else {
        expect(field._apolloFieldPolicies ?? []).toEqual([]);
      }
    }

    const dogType = schema.getTypeMap()["Dog"];
    if (!dogType || !("getFields" in dogType)) throw new Error("Missing Dog type.");

    const dogFields = dogType.getFields();
    for (const fieldName in dogFields) {
      const field = dogFields[fieldName] as FieldWithMeta;
      if (fieldName == "animal") {
        expect(field._apolloFieldPolicies).toHaveLength(1);
        expect(field._apolloFieldPolicies).toContain("withName")
      } else {
        expect(field._apolloFieldPolicies ?? []).toEqual([]);
      }
    }
  });
});

describe("given fieldPolicy on interface and object extensions", () => {
  const schemaSDL: string = `
  interface Animal {
    animal(withName: String): Animal!

    id: ID!
    species: String!
  }

  type Dog implements Animal {
    animal(withName: String): Animal!

    id: ID!
    species: String!
    owner: String
  }

  extend interface Animal @fieldPolicy(forField: "animal", keyArgs: "withName")
  extend type Dog @fieldPolicy(forField: "animal", keyArgs: "withName")
  `;

  it("should set _apolloFieldPolicies property without duplicates.", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const animalType = schema.getTypeMap()["Animal"];
    if (!animalType || !("getFields" in animalType)) throw new Error("Missing Animal type.");

    const animalFields = animalType.getFields();
    for (const fieldName in animalFields) {
      const field = animalFields[fieldName] as FieldWithMeta;
      if (fieldName == "animal") {
        expect(field._apolloFieldPolicies).toHaveLength(1);
        expect(field._apolloFieldPolicies).toContain("withName")
      } else {
        expect(field._apolloFieldPolicies ?? []).toEqual([]);
      }
    }

    const dogType = schema.getTypeMap()["Dog"];
    if (!dogType || !("getFields" in dogType)) throw new Error("Missing Dog type.");

    const dogFields = dogType.getFields();
    for (const fieldName in dogFields) {
      const field = dogFields[fieldName] as FieldWithMeta;
      if (fieldName == "animal") {
        expect(field._apolloFieldPolicies).toHaveLength(1);
        expect(field._apolloFieldPolicies).toContain("withName")
      } else {
        expect(field._apolloFieldPolicies ?? []).toEqual([]);
      }
    }
  });
});

describe("given fieldPolicy on interface", () => {
  const schemaSDL: string = `
  interface Animal @fieldPolicy(forField: "animal", keyArgs: "withName") {
    animal(withName: String): Animal!

    id: ID!
    species: String!
  }

  type Dog implements Animal {
    animal(withName: String): Animal!

    id: ID!
    species: String!
    owner: String
  }
  `;

  it("should set _apolloFieldPolicies property", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const animalType = schema.getTypeMap()["Animal"];
    if (!animalType || !("getFields" in animalType)) throw new Error("Missing Animal type.");

    const animalFields = animalType.getFields();
    for (const fieldName in animalFields) {
      const field = animalFields[fieldName] as FieldWithMeta;
      if (fieldName == "animal") {
        expect(field._apolloFieldPolicies).toHaveLength(1);
        expect(field._apolloFieldPolicies).toContain("withName")
      } else {
        expect(field._apolloFieldPolicies ?? []).toEqual([]);
      }
    }

    const dogType = schema.getTypeMap()["Dog"];
    if (!dogType || !("getFields" in dogType)) throw new Error("Missing Dog type.");

    const dogFields = dogType.getFields();
    for (const fieldName in dogFields) {
      const field = dogFields[fieldName] as FieldWithMeta;
      if (fieldName == "animal") {
        expect(field._apolloFieldPolicies).toHaveLength(1);
        expect(field._apolloFieldPolicies).toContain("withName")
      } else {
        expect(field._apolloFieldPolicies ?? []).toEqual([]);
      }
    }
  });
});

describe("given fieldPolicy on interface and object", () => {
  const schemaSDL: string = `
  interface Animal @fieldPolicy(forField: "animal", keyArgs: "withName") {
    animal(withName: String): Animal!

    id: ID!
    species: String!
  }

  type Dog implements Animal @fieldPolicy(forField: "animal", keyArgs: "withName") {
    animal(withName: String): Animal!

    id: ID!
    species: String!
    owner: String
  }
  `;

  it("should set _apolloFieldPolicies property", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const animalType = schema.getTypeMap()["Animal"];
    if (!animalType || !("getFields" in animalType)) throw new Error("Missing Animal type.");

    const animalFields = animalType.getFields();
    for (const fieldName in animalFields) {
      const field = animalFields[fieldName] as FieldWithMeta;
      if (fieldName == "animal") {
        expect(field._apolloFieldPolicies).toHaveLength(1);
        expect(field._apolloFieldPolicies).toContain("withName")
      } else {
        expect(field._apolloFieldPolicies ?? []).toEqual([]);
      }
    }

    const dogType = schema.getTypeMap()["Dog"];
    if (!dogType || !("getFields" in dogType)) throw new Error("Missing Dog type.");

    const dogFields = dogType.getFields();
    for (const fieldName in dogFields) {
      const field = dogFields[fieldName] as FieldWithMeta;
      if (fieldName == "animal") {
        expect(field._apolloFieldPolicies).toHaveLength(1);
        expect(field._apolloFieldPolicies).toContain("withName")
      } else {
        expect(field._apolloFieldPolicies ?? []).toEqual([]);
      }
    }
  });
});

describe("given field with list input and non-list return type", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID!]): Animal!
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIds")
  `;

  it("should throw error requiring List return type", () => {
    expect(() =>
      loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ])
    ).toThrow(GraphQLError);
  });
});

describe("given field with list return type and non-list input type", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withId: ID!): [Animal!]
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withId")
  `;

  it("should throw error requiring List input type", () => {
    expect(() =>
      loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ])
    ).toThrow(GraphQLError);
  });
});

describe("given field with list return type and multiple list input types", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID!], andNames: [String!]): [Animal!]
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIds andNames")
  `;

  it("should throw error requiring only 1 List input type", () => {
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
    allAnimals(withIds: [ID!]): [Animal!]
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIds")
  `; 

  it("should set _apolloFieldPolicies on field ", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const queryType = schema.getTypeMap()["Query"];
    if (!queryType || !("getFields" in queryType)) throw new Error("Missing Query type.");

    const queryFields = queryType.getFields();
    for (const fieldName in queryFields) {
      const field = queryFields[fieldName] as FieldWithMeta;
      expect(fieldName).toEqual("allAnimals");
      expect(field._apolloFieldPolicies).toHaveLength(1);
      expect(field._apolloFieldPolicies).toContain("withIds");
    }
  });
});

describe("given field policy with multiple valid keyArgs", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID!], andSpecies: String!): [Animal!]
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

    const queryType = schema.getTypeMap()["Query"];
    if (!queryType || !("getFields" in queryType)) throw new Error("Missing Query type.");

    const queryFields = queryType.getFields();
    for (const fieldName in queryFields) {
      const field = queryFields[fieldName] as FieldWithMeta;
      expect(fieldName).toEqual("allAnimals");
      expect(field._apolloFieldPolicies).toHaveLength(2);
      expect(field._apolloFieldPolicies).toEqual(["withIds", "andSpecies"]);
    }
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

describe("given field policy with nested list parameter", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [[ID]!]!, andSpecies: String!): [Animal!]
  }

  type Animal {
    id: ID!
    name: String!
    species: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIds andSpecies")
  `;

  it("should throw error for nested list", () => {
    expect(() =>
      loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ])
    ).toThrow(GraphQLError);
  });
});

describe("given field policy with nested list return type", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID!]!): [[Animal!]!]
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIds")
  `;

  it("should throw error for nested list return type", () => {
    expect(() =>
      loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ])
    ).toThrow(
      '@fieldPolicy does not allow nested list return types. Field "allAnimals" has type "[[Animal!]!]".'
    );
  });
});

describe("given field policy with input object", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withName: AnimalInput!, andSpecies: String!): Animal!
  }

  input AnimalInput {
    dog: DogInput
  }

  input DogInput {
    name: String!
  }

  type Animal {
    id: ID!
    name: String!
    species: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withName.dog.name andSpecies")
  `;

  it("should validate dot notation nested values", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const queryType = schema.getTypeMap()["Query"];
    if (!queryType || !("getFields" in queryType)) throw new Error("Missing Query type.");

    const queryFields = queryType.getFields();
    for (const fieldName in queryFields) {
      const field = queryFields[fieldName] as FieldWithMeta;
      expect(fieldName).toEqual("allAnimals");
      expect(field._apolloFieldPolicies).toHaveLength(2);
      expect(field._apolloFieldPolicies).toEqual(["withName.dog.name", "andSpecies"]);
    }
  });
});
describe("given field policy with list inside input object and non-list return type", () => {
  const schemaSDL: string = `
  type Query {
    animal(input: AnimalInput!): Animal!
  }

  input AnimalInput {
    names: [String!]!
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "animal", keyArgs: "input.names")
  `;

  it("should throw error for list key on non-list return type", () => {
    expect(() =>
      loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ])
    ).toThrow(
      '@fieldPolicy key "input.names" resolves to a list, which requires a List return type. Field "animal" has type "Animal!".'
    );
  });
});

describe("given field policy with key path through list of input objects", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(inputs: [AnimalInput!]!): [Animal!]
  }

  input AnimalInput {
    id: ID!
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "inputs.id")
  `;

  it("should throw error for key path through a list", () => {
    expect(() =>
      loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ])
    ).toThrow(
      '@fieldPolicy key "inputs.id" traverses "id" through a list. A list is only supported as the last value of a key argument.'
    );
  });
});

describe("given field policy with nested list inside input object", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID!]!, input: AnimalInput!): [Animal!]
  }

  input AnimalInput {
    species: [[String!]!]!
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIds input.species")
  `;

  it("should throw error for nested list input field", () => {
    expect(() =>
      loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ])
    ).toThrow(
      '@fieldPolicy does not allow nested list input parameters. Input field "species" of key "input.species" has type "[[String!]!]!".'
    );
  });
});

describe("given field policy with list argument and list inside input object", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID!]!, input: AnimalInput!): [Animal!]
  }

  input AnimalInput {
    species: [String!]!
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIds input.species")
  `;

  it("should throw error for multiple list keys", () => {
    expect(() =>
      loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ])
    ).toThrow(
      '@fieldPolicy can only have 1 key argument that resolves to a list. Key arguments "withIds", "input.species" all resolve to lists.'
    );
  });
});

describe("given field policy with list argument and scalar inside input object", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID!]!, input: AnimalInput!): [Animal!]
  }

  input AnimalInput {
    species: String!
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "withIds input.species")
  `;

  it("should set _apolloFieldPolicies on field", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const queryType = schema.getTypeMap()["Query"];
    if (!queryType || !("getFields" in queryType)) throw new Error("Missing Query type.");

    const field = queryType.getFields()["allAnimals"] as FieldWithMeta;
    expect(field._apolloFieldPolicies).toEqual(["withIds", "input.species"]);
  });
});

describe("given field with list return type and list input that is not a key argument", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(withIds: [ID!]!, species: String!): [Animal!]
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "species")
  `;

  it("should throw error requiring a list key argument", () => {
    expect(() =>
      loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ])
    ).toThrow(
      '@fieldPolicy on a field with a List return type requires a key argument that resolves to a list. Field "allAnimals" has type "[Animal!]".'
    );
  });
});

describe("given field with list return type and list key inside input object", () => {
  const schemaSDL: string = `
  type Query {
    allAnimals(input: AnimalInput!): [Animal!]
  }

  input AnimalInput {
    ids: [ID!]!
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "allAnimals", keyArgs: "input.ids")
  `;

  it("should set _apolloFieldPolicies on field", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const queryType = schema.getTypeMap()["Query"];
    if (!queryType || !("getFields" in queryType)) throw new Error("Missing Query type.");

    const field = queryType.getFields()["allAnimals"] as FieldWithMeta;
    expect(field._apolloFieldPolicies).toEqual(["input.ids"]);
  });
});

describe("given field with non-list return type and list input that is not a key argument", () => {
  const schemaSDL: string = `
  type Query {
    animal(withIds: [ID!]!, species: String!): Animal
  }

  type Animal {
    id: ID!
    name: String!
  }

  extend type Query @fieldPolicy(forField: "animal", keyArgs: "species")
  `;

  it("should set _apolloFieldPolicies on field", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const queryType = schema.getTypeMap()["Query"];
    if (!queryType || !("getFields" in queryType)) throw new Error("Missing Query type.");

    const field = queryType.getFields()["animal"] as FieldWithMeta;
    expect(field._apolloFieldPolicies).toEqual(["species"]);
  });
});
