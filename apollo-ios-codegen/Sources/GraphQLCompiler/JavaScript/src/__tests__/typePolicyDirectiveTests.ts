import {
  GraphQLError,
  type GraphQLNamedType,
  type GraphQLSchema,
  Source,
} from "graphql";
import { loadSchemaFromSources } from "..";

type ObjectWithMeta = GraphQLNamedType & {
  _apolloKeyFields: string[];
};

describe("given SDL without typePolicy", () => {
  const schemaSDL: string = `
  type Query {
    allRectangles: [Rectangle!]
  }

  interface Shape {
    surface: Int!
  }

  type Rectangle {
    width: Int!
    height: Int!
  }
  `;

  it("should set empty _apolloKeyFields property", () => {
    const schema: GraphQLSchema = loadSchemaFromSources([
      new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
    ]);

    const type = schema.getTypeMap()["Rectangle"] as ObjectWithMeta;
    expect(type._apolloKeyFields).toHaveLength(0);

    const iface = schema.getTypeMap()["Shape"] as ObjectWithMeta;
    expect(iface._apolloKeyFields).toHaveLength(0);
  });
});

describe("given SDL with valid typePolicy", () => {
  describe("on object", () => {
    const schemaSDL: string = `
    type Query {
      allRectangles: [Rectangle!]
    }

    type Rectangle @typePolicy(keyFields: "width height") {
      width: Int!
      height: Int!
    }
    `;

    it("should set _apolloKeyFields property", () => {
      const schema: GraphQLSchema = loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ]);

      const type = schema.getTypeMap()["Rectangle"] as ObjectWithMeta;
      expect(type._apolloKeyFields).toHaveLength(2);
      expect(type._apolloKeyFields).toContain("width");
      expect(type._apolloKeyFields).toContain("height");
    });
  });

  describe("on interface", () => {
    const schemaSDL: string = `
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal @typePolicy(keyFields: "id") {
      id: ID!
    }

    interface Domesticated {
      owner: String
    }

    type Dog implements Animal & Domesticated {
      id: ID!
      species: String!
      owner: String
    }
    `;

    it("should set _apolloKeyFields property", () => {
      const schema: GraphQLSchema = loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ]);

      const type = schema.getTypeMap()["Dog"] as ObjectWithMeta;
      expect(type._apolloKeyFields).toHaveLength(1);
      expect(type._apolloKeyFields).toContain("id");

      const iface = schema.getTypeMap()["Animal"] as ObjectWithMeta;
      expect(iface._apolloKeyFields).toHaveLength(1);
      expect(iface._apolloKeyFields).toContain("id");
    });
  });

  describe("on multiple interfaces", () => {
    const schemaSDL: string = `
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal @typePolicy(keyFields: "id") {
      id: ID!
    }

    interface Domesticated @typePolicy(keyFields: "id") {
      id: ID!
      owner: String
    }

    type Dog implements Animal & Domesticated {
      id: ID!
      species: String!
      owner: String
    }
    `;

    it("should set _apolloKeyFields property", () => {
      const schema: GraphQLSchema = loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ]);

      const type = schema.getTypeMap()["Dog"] as ObjectWithMeta;
      expect(type._apolloKeyFields).toHaveLength(1);
      expect(type._apolloKeyFields).toContain("id");
    });
  });

  describe("on interface and object", () => {
    const schemaSDL: string = `
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal @typePolicy(keyFields: "id") {
      id: ID!
    }

    type Dog implements Animal @typePolicy(keyFields: "id") {
      id: ID!
      species: String!
      owner: String
    }
    `;

    it("should set _apolloKeyFields property", () => {
      const schema: GraphQLSchema = loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ]);

      const type = schema.getTypeMap()["Dog"] as ObjectWithMeta;
      expect(type._apolloKeyFields).toHaveLength(1);
      expect(type._apolloKeyFields).toContain("id");
    });
  });

  describe("on object extension", () => {
    const schemaSDL: string = `
    type Query {
      allCircles: [Circle!]
    }

    type Circle {
      radius: Int!
    }

    extend type Circle @typePolicy(keyFields: "radius")
    `;

    it("should set _apolloKeyFields property", () => {
      const schema: GraphQLSchema = loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ]);

      const type = schema.getTypeMap()["Circle"] as ObjectWithMeta;
      expect(type._apolloKeyFields).toHaveLength(1);
      expect(type._apolloKeyFields).toContain("radius");
    });
  });

  describe("on interface extension", () => {
    const schemaSDL: string = `
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: ID!
    }

    type Dog implements Animal {
      id: ID!
      species: String!
    }

    extend interface Animal @typePolicy(keyFields: "id")
    `;

    it("should set _apolloKeyFields property", () => {
      const schema: GraphQLSchema = loadSchemaFromSources([
        new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
      ]);

      const type = schema.getTypeMap()["Dog"] as ObjectWithMeta;
      expect(type._apolloKeyFields).toHaveLength(1);
      expect(type._apolloKeyFields).toContain("id");
    });
  });
});

describe("given SDL with invalid typePolicy", () => {
  describe("with malformed keyFields", () => {
    const schemaSDL: string = `
    type Query {
      allRectangles: [Rectangle!]
    }

    type Rectangle @typePolicy(keyFields: " width") {
      width: Int!
      height: Int!
    }
    `;

    it("should throw", () => {
      expect(() =>
        loadSchemaFromSources([
          new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
        ])
      ).toThrow(GraphQLError);
    });
  });

  describe("with missing field on object", () => {
    const schemaSDL: string = `
    type Query {
      allRectangles: [Rectangle!]
    }

    type Rectangle @typePolicy(keyFields: "radius") {
      width: Int!
      height: Int!
    }
    `;

    it("should throw", () => {
      expect(() =>
        loadSchemaFromSources([
          new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
        ])
      ).toThrow(GraphQLError);
    });
  });

  describe("with non-scalar field on object", () => {
    const schemaSDL: string = `
    type Query {
      allRectangles: [Rectangle!]
    }

    type Size {
      width: Int!
      height: Int!
    }

    type Rectangle @typePolicy(keyFields: "size") {
      size: Size!
    }
    `;

    it("should throw", () => {
      expect(() =>
        loadSchemaFromSources([
          new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
        ])
      ).toThrow(GraphQLError);
    });
  });

  describe("with nullable field", () => {
    const schemaSDL: string = `
    type Query {
      allRectangles: [Rectangle!]
    }

    type Rectangle @typePolicy(keyFields: "width height") {
      width: Int!
      height: Int
    }
    `;

    it("should throw", () => {
      expect(() =>
        loadSchemaFromSources([
          new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
        ])
      ).toThrow(GraphQLError);
    });
  });

  describe("with missing field on interface", () => {
    const schemaSDL: string = `
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal @typePolicy(keyFields: "id") {
      species: String!
    }

    type Dog implements Animal {
      id: ID!
      species: String!
    }
    `;

    it("should throw", () => {
      expect(() =>
        loadSchemaFromSources([
          new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
        ])
      ).toThrow(GraphQLError);
    });
  });

  describe("with missing field on object extension", () => {
    const schemaSDL: string = `
    type Query {
      allCircles: [Circle!]
    }

    type Circle {
      radius: Int!
    }

    extend type Circle @typePolicy(keyFields: "width")
    `;
    it("should throw", () => {
      expect(() =>
        loadSchemaFromSources([
          new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
        ])
      ).toThrow(GraphQLError);
    });
  });

  describe("with missing field on interface extension", () => {
    const schemaSDL: string = `
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    type Dog implements Animal {
      id: ID!
      species: String!
    }

    extend interface Animal @typePolicy(keyFields: "id")
    `;

    it("should throw", () => {
      expect(() =>
        loadSchemaFromSources([
          new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
        ])
      ).toThrow(GraphQLError);
    });
  });

  describe("with conflicting interfaces", () => {
    const schemaSDL: string = `
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal @typePolicy(keyFields: "id") {
      id: ID!
    }

    interface Domesticated @typePolicy(keyFields: "id owner") {
      id: ID!
      owner: String
    }

    type Dog implements Animal & Domesticated {
      id: ID!
      species: String!
      owner: String
    }
    `;

    it("should throw", () => {
      expect(() =>
        loadSchemaFromSources([
          new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
        ])
      ).toThrow(GraphQLError);
    });
  });

  describe("with policy on both interface and type", () => {
    const schemaSDL: string = `
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal @typePolicy(keyFields: "id") {
      id: ID!
    }

    type Dog implements Animal @typePolicy(keyFields: "id owner") {
      id: ID!
      species: String!
      owner: String
    }
    `;

    it("should throw", () => {
      expect(() =>
        loadSchemaFromSources([
          new Source(schemaSDL, "Test Schema", { line: 1, column: 1 }),
        ])
      ).toThrow(GraphQLError);
    });
  });
});
