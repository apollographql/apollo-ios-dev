import XCTest
import Nimble
import GraphQLCompiler
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers
@testable import ApolloCodegenLib

class CompilationTests: XCTestCase {

  var schemaSDL: String!
  var schemaJSON: String!
  var document: String!
  
  override func setUpWithError() throws {
    try super.setUpWithError()

  }

  override func tearDown() {
    schemaSDL = nil
    schemaJSON = nil
    document = nil

    super.tearDown()
  }

  // MARK: - Helpers

  func useStarWarsSchema() throws {
    schemaJSON = try String(
      contentsOf: ApolloCodegenInternalTestHelpers.Resources.StarWars.JSONSchema
    )
  }

  func compileFrontend(
    schemaNamespace: String = "TestSchema"
  ) async throws -> CompilationResult {
    let frontend = try await GraphQLJSFrontend()
    let config = ApolloCodegen.ConfigurationContext(config: .mock(schemaNamespace: schemaNamespace))

    if let schemaSDL = schemaSDL {
      return try await frontend.compile(
        schema: schemaSDL,
        document: document,
        config: config
      )
    } else if let schemaJSON = schemaJSON {
      return try await frontend.compile(
        schemaJSON: schemaJSON,
        document: document,
        config: config
      )
    } else {
      throw TestError("No Schema!")
    }
  }

  // MARK: - Tests
  
  func test__compile__givenSingleQuery() async throws {
    // given
    try useStarWarsSchema()

    document = """
      query HeroAndFriendsNames($episode: Episode) {
        hero(episode: $episode) {
          name
          friends {
            name
          }
        }
      }
      """

    let compilationResult = try await compileFrontend()
    
    let operation = try XCTUnwrap(compilationResult.operations.first)
    XCTAssertEqual(operation.name, "HeroAndFriendsNames")
    XCTAssertEqual(operation.operationType, .query)
    XCTAssertEqual(operation.rootType.name.schemaName, "Query")
    
    XCTAssertEqual(operation.variables[0].name, "episode")
    XCTAssertEqual(operation.variables[0].type.typeReference, "Episode")

    let heroField = try XCTUnwrap(operation.selectionSet.firstField(for: "hero"))
    XCTAssertEqual(heroField.name, "hero")
    XCTAssertEqual(heroField.type.typeReference, "Character")
    
    let episodeArgument = try XCTUnwrap(heroField.arguments?.first)
    XCTAssertEqual(episodeArgument.name, "episode")
    XCTAssertEqual(episodeArgument.value, .variable("episode"))

    let friendsField = try XCTUnwrap(heroField.selectionSet?.firstField(for: "friends"))
    XCTAssertEqual(friendsField.name, "friends")
    XCTAssertEqual(friendsField.type.typeReference, "[Character]")
    
    XCTAssertEqualUnordered(compilationResult.referencedTypes.map(\.name.schemaName),
                            ["Human", "Droid", "Query", "Episode", "Character", "String"])
  }

  func test__compile__givenOperationWithRecognizedDirective_hasDirective() async throws {
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    directive @testDirective on QUERY
    """

    document = """
    query Test @testDirective {
      allAnimals {
        species
      }
    }
    """

    let expectedDirectives: [CompilationResult.Directive] = [
      .mock("testDirective")
    ]

    let compilationResult = try await compileFrontend()


    let operation = try XCTUnwrap(compilationResult.operations.first)
    expect(operation.directives).to(equal(expectedDirectives))
  }

  func test__compile__givenInputObject_withListFieldWithDefaultValueEmptyArray() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals(list: TestInput!): [Animal!]!
    }

    input TestInput {
      listField: [String!] = []
    }

    interface Animal {
      species: String!
    }
    """

    document = """
    query ListInputTest($input: TestInput!) {
      allAnimals(list: $input) {
        species
      }
    }
    """

    // when
    let compilationResult = try await compileFrontend()

    let inputObject = try XCTUnwrap(
      compilationResult.referencedTypes.first { $0.name.schemaName == "TestInput"} as? GraphQLInputObjectType
    )
    let listField = try XCTUnwrap(inputObject.fields["listField"])
    let defaultValue = try XCTUnwrap(listField.defaultValue)

    // then
    expect(defaultValue).to(equal(GraphQLValue.list([])))
  }

  func test__compile__givenUniqueSchemaName_shouldNotThrow() async throws {
    // given
    schemaSDL = """
    type Query {
      animal(favourite: String!): Animal
    }

    interface Animal {
      id: ID!
      species: String!
      height: Height!
      predators: [Animal!]
      nonNullPredators: [Animal!]!
    }

    type Height {
      centimeters: Int!
      inches: Int!
    }
    """

    document = """
    query FavouriteAnimal($favourite: String!) {
      animal(favourite: $favourite) {
        id
        species
        height {
          centimeters
        }
        predators {
          species
        }
        nonNullPredators {
          species
        }
      }
    }
    """

    // then
    await expect { try await self.compileFrontend(schemaNamespace: "MySchema") }
      .toNot(throwError())
  }

  func test__compile__givenSchemaName_matchingScalarFieldAndInputValueName_shouldNotThrow() async throws {
    // given
    schemaSDL = """
    type Query {
      animal(species: String!): Animal
    }

    interface Animal {
      id: ID!
      species: String!
      height: Height!
      predators: [Animal!]
    }

    type Height {
      centimeters: Int!
      inches: Int!
    }
    """

    document = """
    query FavouriteAnimal($species: String!) {
      animal(species: $species) {
        species
      }
    }
    """

    // then
    await expect { try await self.compileFrontend(schemaNamespace: "species") }
      .toNot(throwError())
  }

  func test__compile__givenSchemaName_matchingEntityFieldName_shouldThrow() async throws {
    // given
    schemaSDL = """
    type Query {
      animal(favourite: String!): Animal
    }

    interface Animal {
      id: ID!
      species: String!
      height: Height!
      predators: [Animal!]
    }

    type Height {
      centimeters: Int!
      inches: Int!
    }
    """

    document = """
    query FavouriteAnimal($favourite: String!) {
      animal(favourite: $favourite) {
        species
        height {
          centimeters
        }
      }
    }
    """

    // then
    await expect { try await self.compileFrontend(schemaNamespace: "height") }
      .to(throwError { error in
        XCTAssertTrue(
          (error as! GraphQLCompiler.JavaScriptError).description.contains(
        """
        Schema name "height" conflicts with name of a generated object API. \
        Please choose a different schema name.
        """
          ))
      })
  }

  func test__compile__givenSingularSchemaName_matchingPluralizedNullableListFieldName_shouldThrow() async throws {
    // given
    schemaSDL = """
    type Query {
      animal(favourite: String!): Animal
    }

    interface Animal {
      id: ID!
      species: String!
      height: Height!
      predators: [Animal!]
    }

    type Height {
      centimeters: Int!
      inches: Int!
    }
    """

    document = """
    query FavouriteAnimal($favourite: String!) {
      animal(favourite: $favourite) {
        species
        predators {
          species
        }
      }
    }
    """

    // then
    await expect { try await self.compileFrontend(schemaNamespace: "predator") }
      .to(throwError { error in
        XCTAssertTrue(
          (error as! GraphQLCompiler.JavaScriptError).description.contains(
        """
        Schema name "predator" conflicts with name of a generated object API. \
        Please choose a different schema name.
        """
          ))
      })
  }

  func test__compile__givenSingularSchemaName_matchingPluralizedNonNullListFieldName_shouldThrow() async throws {
    // given
    schemaSDL = """
    type Query {
      animal(favourite: String!): Animal
    }

    interface Animal {
      id: ID!
      species: String!
      height: Height!
      predators: [Animal!]!
    }

    type Height {
      centimeters: Int!
      inches: Int!
    }
    """

    document = """
    query FavouriteAnimal($favourite: String!) {
      animal(favourite: $favourite) {
        species
        predators {
          species
        }
      }
    }
    """

    // then
    await expect { try await self.compileFrontend(schemaNamespace: "predator") }
      .to(throwError { error in
        XCTAssertTrue(
          (error as! GraphQLCompiler.JavaScriptError).description.contains(
        """
        Schema name "predator" conflicts with name of a generated object API. \
        Please choose a different schema name.
        """
          ))
      })
  }

  func test__compile__givenPluralizedSchemaName_matchingPluralizedNullableListFieldName_shouldNotThrow() async throws {
    // given
    schemaSDL = """
    type Query {
      animal(favourite: String!): Animal
    }

    interface Animal {
      id: ID!
      species: String!
      height: Height!
      predators: [Animal!]
    }

    type Height {
      centimeters: Int!
      inches: Int!
    }
    """

    document = """
    query FavouriteAnimal($favourite: String!) {
      animal(favourite: $favourite) {
        species
        predators {
          species
        }
      }
    }
    """

    // then
    await expect { try await self.compileFrontend(schemaNamespace: "predators") }
      .toNot(throwError())
  }

  func test__compile__givenPluralizedSchemaName_matchingPluralizedNonNullListFieldName_shouldNotThrow() async throws {
    // given
    schemaSDL = """
    type Query {
      animal(favourite: String!): Animal
    }

    interface Animal {
      id: ID!
      species: String!
      height: Height!
      predators: [Animal!]!
    }

    type Height {
      centimeters: Int!
      inches: Int!
    }
    """

    document = """
    query FavouriteAnimal($favourite: String!) {
      animal(favourite: $favourite) {
        species
        predators {
          species
        }
      }
    }
    """

    // then
    await expect { try await self.compileFrontend(schemaNamespace: "predators") }
      .toNot(throwError())
  }

}

fileprivate extension CompilationResult.SelectionSet {
  // This is a helper method that is really only suitable for testing because getting just the first
  // occurrence of a field is of limited use when generating code.
  func firstField(for responseKey: String) -> CompilationResult.Field? {
    for selection in selections {
      guard case let .field(field) = selection else {
        continue
      }
      
      if field.responseKey == responseKey {
        return field
      }
    }
    
    return nil
  }
}
