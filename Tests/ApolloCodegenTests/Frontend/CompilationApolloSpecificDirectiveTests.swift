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

    let compilationResult = try await compileFrontend()

    let operation = try XCTUnwrap(compilationResult.operations.first)
    expect(operation.source).toNot(contain("@import"))
  }

  // MARK: moduleImports Tests

  func test__moduleImports__givenQueryWithImportDirective_hasModuleImports() async throws {
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

    let compilationResult = try await compileFrontend()

    let operation = try XCTUnwrap(compilationResult.operations.first)
    expect(operation.moduleImports).to(equal(["MyModuleName"]))
  }

  func test__moduleImports__givenQueryWithImportDirectives_notAlphabetized_hasModuleImportsAlphabetized() async throws {
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
      }
      """

    document = """
      query Test @import(module: "ModuleB") @import(module: "ModuleA") {
        allAnimals {
          species
        }
      }
      """

    let compilationResult = try await compileFrontend()

    let operation = try XCTUnwrap(compilationResult.operations.first)
    expect(operation.moduleImports).to(equal([
      "ModuleA",
      "ModuleB"
    ]))
  }

  func test__moduleImports__givenQueryAndFragmentWithImportDirectives_notAlphabetized_hasModuleImportsAlphabetized() async throws {
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
      }
      """

    document = """
      query Test @import(module: "ModuleC") @import(module: "ModuleA") {
        ...Animals
      }

      fragment Animals on Query @import(module: "ModuleD") @import(module: "ModuleB") {
        allAnimals {
          species
        }
      }
      """

    let compilationResult = try await compileFrontend()

    let operation = try XCTUnwrap(compilationResult.operations.first)
    let AnimalsFragment = try XCTUnwrap(compilationResult.fragments.first)

    expect(operation.moduleImports).to(equal([
      "ModuleA",
      "ModuleB",
      "ModuleC",
      "ModuleD"
    ]))

    expect(AnimalsFragment.moduleImports).to(equal([
      "ModuleB",
      "ModuleD"
    ]))
  }

  func test__moduleImports__givenQueryAndFragmentsWithDuplicateImportDirectives_hasModuleImportsDeduplicated() async throws {
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
      }
      """

    document = """
      query Test @import(module: "ModuleA") @import(module: "ModuleB") @import(module: "ModuleC") {
        ...Animals
      }

      fragment Animals on Query @import(module: "ModuleB") @import(module: "ModuleC") {
        allAnimals {
          species
        }
      }
      """

    let compilationResult = try await compileFrontend()

    let operation = try XCTUnwrap(compilationResult.operations.first)
    let AnimalsFragment = try XCTUnwrap(compilationResult.fragments.first)

    expect(operation.moduleImports).to(equal([
      "ModuleA",
      "ModuleB",
      "ModuleC",
    ]))

    expect(AnimalsFragment.moduleImports).to(equal([
      "ModuleB",
      "ModuleC"
    ]))
  }

  func test__moduleImports__givenQueryAndMultipleFragmentsWithImportDirectives__hasModuleImports() async throws {
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
      }
      """

    document = """
      query Test @import(module: "ModuleC") @import(module: "ModuleA") {
        ...Animals
        ...Animals2
      }

      fragment Animals on Query @import(module: "ModuleD") {
        allAnimals {
          species
        }
      }

      fragment Animals2 on Query @import(module: "ModuleB") {
        allAnimals {
          species
        }
      }
      """

    let compilationResult = try await compileFrontend()

    let operation = try XCTUnwrap(compilationResult.operations.first)
    let AnimalsFragment = try XCTUnwrap(compilationResult[fragment: "Animals"])
    let AnimalsFragment2 = try XCTUnwrap(compilationResult[fragment: "Animals2"])

    expect(operation.moduleImports).to(equal([
      "ModuleA",
      "ModuleB",
      "ModuleC",
      "ModuleD"
    ]))

    expect(AnimalsFragment.moduleImports).to(equal([
      "ModuleD"
    ]))

    expect(AnimalsFragment2.moduleImports).to(equal([
      "ModuleB"      
    ]))
  }

}
