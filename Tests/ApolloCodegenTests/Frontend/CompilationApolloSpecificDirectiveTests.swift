import XCTest
import Nimble
import GraphQLCompiler
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers
@testable import ApolloCodegenLib

class CompilationApolloSpecificDirectiveTests: XCTestCase {

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

  func useStarWarsSchema() throws {
    schemaJSON = try String(
      contentsOf: ApolloCodegenInternalTestHelpers.Resources.StarWars.JSONSchema
    )
  }

  // MARK: @apollo_client_ios_localCacheMutation Tests

  /// Tests that we automatically add the local cache mutation directive to the schema
  /// during codegen.
  func test__compile__givenSchemaSDL_queryWithLocalCacheMutationDirective_notInSchema_hasDirective() async throws {
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
      }
      """

    document = """
      query Test @apollo_client_ios_localCacheMutation {
        allAnimals {
          species
        }
      }
      """

    let expectedDirectives: [CompilationResult.Directive] = [
      .mock("apollo_client_ios_localCacheMutation")
    ]

    let compilationResult = try await compileFrontend()


    let operation = try XCTUnwrap(compilationResult.operations.first)
    expect(operation.directives).to(equal(expectedDirectives))
  }

  /// Tests that we automatically add the local cache mutation directive to the schema
  /// during codegen.
  func test__compile__givenSchemaJSON_queryWithLocalCacheMutationDirective_notInSchema_hasDirective() async throws {
    try useStarWarsSchema()

    document = """
      query HeroAndFriendsNames($id: ID) @apollo_client_ios_localCacheMutation {
        human(id: $id) {
          name
          mass
          appearsIn
        }
      }
      """

    let expectedDirectives: [CompilationResult.Directive] = [
      .mock("apollo_client_ios_localCacheMutation")
    ]

    let compilationResult = try await compileFrontend()


    let operation = try XCTUnwrap(compilationResult.operations.first)
    expect(operation.directives).to(equal(expectedDirectives))
  }

  func test__compile__givenQueryWithLocalCacheMutationDirective_stripsDirectiveFromSource() async throws {
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
      }
      """

    document = """
      query Test @apollo_client_ios_localCacheMutation {
        allAnimals {
          species
        }
      }
      """

    let expectedDirectives: [CompilationResult.Directive] = [
      .mock("import", arguments: [.mock("module", value: .string("MyModuleName"))])
    ]

    let compilationResult = try await compileFrontend()


    let operation = try XCTUnwrap(compilationResult.operations.first)
    expect(operation.source).toNot(contain("@apollo_client_ios_localCacheMutation"))
  }

  // MARK: @import Tests

  /// Tests that we automatically add the import directive to the schema
  /// during codegen.
  func test__compile__givenSchemaSDL_queryWithImportDirective_notInSchema_hasDirective() async throws {
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
      }
      """

    document = """
      query Test @import(module: "MyModuleName") {
        allAnimals {
          species
        }
      }
      """

    let expectedDirectives: [CompilationResult.Directive] = [
      .mock("import", arguments: [.mock("module", value: .string("MyModuleName"))])
    ]

    let compilationResult = try await compileFrontend()


    let operation = try XCTUnwrap(compilationResult.operations.first)
    expect(operation.directives).to(equal(expectedDirectives))
  }

  /// Tests that we automatically add the import directive to the schema
  /// during codegen.
  func test__compile__givenSchemaJSON_queryWithImportDirective_notInSchema_hasDirective() async throws {
    try useStarWarsSchema()

    document = """
      query HeroAndFriendsNames($id: ID) @import(module: "MyModuleName") {
        human(id: $id) {
          name
          mass
          appearsIn
        }
      }
      """

    let expectedDirectives: [CompilationResult.Directive] = [
      .mock("import", arguments: [.mock("module", value: .string("MyModuleName"))])
    ]

    let compilationResult = try await compileFrontend()


    let operation = try XCTUnwrap(compilationResult.operations.first)
    expect(operation.directives).to(equal(expectedDirectives))
  }

  func test__compile__givenQueryWithImportDirective_stripsDirectiveFromSource() async throws {
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
      }
      """

    document = """
      query Test @import(module: "MyModuleName") {
        allAnimals {
          species
        }
      }
      """

    let expectedDirectives: [CompilationResult.Directive] = [
      .mock("import", arguments: [.mock("module", value: .string("MyModuleName"))])
    ]

    let compilationResult = try await compileFrontend()


    let operation = try XCTUnwrap(compilationResult.operations.first)
    expect(operation.source).toNot(contain("@import"))
  }

}
