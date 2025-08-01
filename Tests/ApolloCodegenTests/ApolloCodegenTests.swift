import XCTest
import ApolloInternalTestHelpers
@testable import ApolloCodegenInternalTestHelpers
@testable import ApolloCodegenLib
import IR
import GraphQLCompiler
import Nimble

class ApolloCodegenTests: XCTestCase {
  private var directoryURL: URL { testFileManager.directoryURL }
  private var testFileManager: TestIsolatedFileManager!

  override func setUpWithError() throws {
    try super.setUpWithError()
    testFileManager = try testIsolatedFileManager()
  }

  override func tearDownWithError() throws {
    testFileManager = nil
    try super.tearDownWithError()
  }

  // MARK: Helpers

  private let schemaData: Data = {
    """
    type Query {
      books: [Book!]!
      authors: [Author!]!
    }

    type Mutation {
      books: [Book!]!
      authors: [Author!]!
    }

    type Subscription {
      books: [Book!]!
      authors: [Author!]!
    }

    type Book {
      title: String!
      author: Author!
    }

    type Author {
      id: ID!
      name: String!
      books: [Book!]!
    }
    """
  }().data(using: .utf8)!

  /// Creates a file in the test directory.
  ///
  /// - Parameters:
  ///   - data: File content
  ///   - filename: Target name of the file. This should not include any path information
  ///
  /// - Returns:
  ///    - The full path of the created file.
  @discardableResult
  private func createFile(
    containing data: Data,
    named filename: String,
    inDirectory directory: String? = nil
  ) throws -> String {
    return try self.testFileManager.createFile(
      containing: data,
      named: filename,
      inDirectory: directory
    )
  }

  @discardableResult
  private func createFile(
    body: @autoclosure () -> String = "Test File",
    filename: String,
    inDirectory directory: String? = nil
  ) throws -> String {
    return try self.testFileManager.createFile(
      body: body(),
      named: filename,
      inDirectory: directory
    )
  }

  @discardableResult
  private func createOperationFile(
    type: CompilationResult.OperationType,
    named operationName: String,
    filename: String,
    inDirectory directory: String? = nil
  ) throws -> String {
    let query: String =
      """
      \(type.rawValue) \(operationName) {
        books {
          title
        }
      }
      """
    return try createFile(body: query, filename: filename, inDirectory: directory)
  }

  // MARK: CompilationResult Tests

  func test_compileResults_givenOperation_withGraphQLErrors_shouldThrow() async throws {
    // given
    let schemaPath = try createFile(containing: schemaData, named: "schema.graphqls")

    let operationData: Data =
      """
      query getBooks {
        books {
          title
          name
        }
      }
      """.data(using: .utf8)!
    try createFile(containing: operationData, named: "operation.graphql")

    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(input: .init(
      schemaPath: schemaPath,
      operationSearchPaths: [directoryURL.appendingPathComponent("*.graphql").path]
    )), rootURL: nil)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    // with
    //
    // Fetching `books.name` will cause a GraphQL validation error because `name`
    // is not a property of the `Book` type.

    // then
    await expect { try await subject.compileGraphQLResult() }
      .to(throwError { error in
        guard case let ApolloCodegen.Error.graphQLSourceValidationFailure(lines) = error else {
          fail("Expected .graphQLSourceValidationFailure, got .\(error)")
          return
        }
        expect(lines).notTo(beEmpty())
      })
  }

  func test_compileResults_givenOperations_withNoErrors_shouldReturn() async throws {
    // given
    let schemaPath = try createFile(containing: schemaData, named: "schema.graphqls")

    let booksData: Data =
      """
      query getBooks {
        books {
          title
        }
      }
      """.data(using: .utf8)!
    try createFile(containing: booksData, named: "books-operation.graphql")

    let authorsData: Data =
      """
      query getAuthors {
        authors {
          name
        }
      }
      """.data(using: .utf8)!
    try createFile(containing: authorsData, named: "authors-operation.graphql")

    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(input: .init(
      schemaPath: schemaPath,
      operationSearchPaths: [directoryURL.appendingPathComponent("*.graphql").path]
    )), rootURL: nil)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    // then
    await expect { try await subject.compileGraphQLResult().operations }.to(haveCount(2))
  }

  func test_compileResults_givenIDScalarIsReferenced_referencedTypesShouldIncludeScalar() async throws {
    // given
    try createFile(containing: schemaData, named: "schema.graphqls", inDirectory: "CustomRoot")

    try createFile(
      body: """
      query getAuthors {
        authors {
          id
          name
        }
      }
      """,
      filename: "TestQuery.graphql")

    let rootURL = directoryURL.appendingPathComponent("CustomRoot")

    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(input: .init(
      schemaSearchPaths: ["./**/*.graphqls"],
      operationSearchPaths: [directoryURL.appendingPathComponent("*.graphql").path]
    )), rootURL: rootURL)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let actual = try await subject.compileGraphQLResult()

    // then
    expect(actual.operations).to(haveCount(1))
    expect(actual.referencedTypes).to(haveCount(4))
    expect(actual.referencedTypes).to(contain(GraphQLScalarType.mock(name: "ID")))
  }

  func test_compileResults_givenRelativeSearchPath_relativeToRootURL_hasOperations_shouldReturnOperationsRelativeToRoot() async throws {
    // given
    let schemaPath = try createFile(containing: schemaData, named: "schema.graphqls")

    let rootURL = directoryURL.appendingPathComponent("CustomRoot")

    let booksData: Data =
      """
      query getBooks {
        books {
          title
        }
      }
      """.data(using: .utf8)!
    try createFile(containing: booksData, named: "books-operation.graphql", inDirectory: "CustomRoot")

    let authorsData: Data =
      """
      query getAuthors {
        authors {
          name
        }
      }
      """.data(using: .utf8)!
    try createFile(containing: authorsData, named: "authors-operation.graphql")

    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(input: .init(
      schemaPath: schemaPath,
      operationSearchPaths: ["./**/*.graphql"]
    )), rootURL: rootURL)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let actual = try await subject.compileGraphQLResult().operations

    // then
    expect(actual).to(haveCount(1))
    expect(actual.first?.name).to(equal("getBooks"))
  }

  func test_compileResults_givenRelativeSchemaSearchPath_relativeToRootURL_shouldReturnSchemaRelativeToRoot() async throws {
    // given
    try createFile(
      body: """
      type QueryTwo {
        string: String!
      }
      """,
      filename: "schema1.graphqls")

    try createFile(containing: schemaData, named: "schema.graphqls", inDirectory: "CustomRoot")

    try createFile(
      body: """
      query getAuthors {
        authors {
          name
        }
      }
      """,
      filename: "TestQuery.graphql")

    let rootURL = directoryURL.appendingPathComponent("CustomRoot")

    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(input: .init(
      schemaSearchPaths: ["./**/*.graphqls"],
      operationSearchPaths: [directoryURL.appendingPathComponent("*.graphql").path]
    )), rootURL: rootURL)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let actual = try await subject.compileGraphQLResult()

    // then
    expect(actual.operations).to(haveCount(1))
    expect(actual.referencedTypes).to(haveCount(3))
  }

  func test__compileResults__givenMultipleSchemaFiles_withDependentTypes_compilesResult() async throws {
    // given
    try createFile(
      body: """
      type Query {
        books: [Book!]!
        authors: [Author!]!
      }
      """,
      filename: "schema1.graphqls")

    try createFile(
      body: """
      type Book {
        title: String!
        author: Author!
      }

      type Author {
        name: String!
        books: [Book!]!
      }
      """,
      filename: "schema2.graphqls")

    try createFile(
      body: """
      query getAuthors {
        authors {
          name
        }
      }
      """,
      filename: "TestQuery.graphql")

    // when
    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(input: .init(
      schemaSearchPaths: [directoryURL.appendingPathComponent("schema*.graphqls").path],
      operationSearchPaths: [directoryURL.appendingPathComponent("*.graphql").path]
    )), rootURL: nil)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    // then
    await expect { try await subject.compileGraphQLResult().referencedTypes.count }.to(equal(3))
  }

  func test__compileResults__givenMultipleSchemaFiles_withDifferentRootTypes_compilesResult() async throws {
    // given
    try createFile(
      body: """
      type Query {
        string: String!
      }
      """,
      filename: "schema1.graphqls")

    try createFile(
      body: """
      type Subscription {
        bool: Boolean!
      }
      """,
      filename: "schema2.graphqls")

    try createFile(
      body: """
      query TestQuery {
        string
      }
      """,
      filename: "TestQuery.graphql")

    try createFile(
      body: """
      subscription TestSubscription {
        bool
      }
      """,
      filename: "TestSubscription.graphql")

    // when
    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(input: .init(
      schemaSearchPaths: [directoryURL.appendingPathComponent("schema*.graphqls").path],
      operationSearchPaths: [directoryURL.appendingPathComponent("*.graphql").path]
    )), rootURL: nil)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let result = try await subject.compileGraphQLResult()

    // then
    expect(result.operations.count).to(equal(2))
  }

  func test__compileResults__givenMultipleSchemaFiles_withSchemaTypeExtension_compilesResultWithExtension() async throws {
    // given
    try createFile(
      body: """
      type Query {
        string: String!
      }
      """,
      filename: "schema1.graphqls")

    try createFile(
      body: """
      extend type Query {
        bool: Boolean!
      }
      """,
      filename: "schemaExtension.graphqls")

    try createFile(
      body: """
      query TestQuery {
        string
        bool
      }
      """,
      filename: "TestQuery.graphql")

    // when
    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(input: .init(
      schemaSearchPaths: [directoryURL.appendingPathComponent("schema*.graphqls").path],
      operationSearchPaths: [directoryURL.appendingPathComponent("*.graphql").path]
    )), rootURL: nil)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let result = try await subject.compileGraphQLResult()

    // then
    expect(result.operations.count).to(equal(1))
  }

  func test__compileResults__givenMultipleSchemaFilesWith_introspectionJSONSchema_withSchemaTypeExtension_compilesResultWithExtension() async throws {
    // given
    let introspectionJSON = try String(
      contentsOf: ApolloCodegenInternalTestHelpers.Resources.StarWars.JSONSchema
    )

    try createFile(body: introspectionJSON, filename: "schemaJSON.json")

    try createFile(
      body: """
      extend type Query {
        testExtensionField: Boolean!
      }
      """,
      filename: "schemaExtension.graphqls")

    try createFile(
      body: """
      query TestQuery {
        testExtensionField
      }
      """,
      filename: "TestQuery.graphql")

    // when
    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(input: .init(
      schemaSearchPaths: [
        directoryURL.appendingPathComponent("schema*.graphqls").path,
        directoryURL.appendingPathComponent("schema*.json").path,
      ],
      operationSearchPaths: [directoryURL.appendingPathComponent("*.graphql").path]
    )), rootURL: nil)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let result = try await subject.compileGraphQLResult()

    // then
    expect(result.operations.count).to(equal(1))
  }

  func test__compileResults__givenMultipleIntrospectionJSONSchemaFiles_throwsError() async throws {
    // given
    let introspectionJSON = try String(
      contentsOf: ApolloCodegenInternalTestHelpers.Resources.StarWars.JSONSchema
    )

    try createFile(body: introspectionJSON, filename: "schemaJSON1.json")
    try createFile(body: introspectionJSON, filename: "schemaJSON2.json")

    // when
    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(input: .init(
      schemaSearchPaths: [
        directoryURL.appendingPathComponent("schema*.graphqls").path,
        directoryURL.appendingPathComponent("schema*.json").path,
      ],
      operationSearchPaths: [directoryURL.appendingPathComponent("*.graphql").path]
    )), rootURL: nil)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    // then
    await expect { try await subject.compileGraphQLResult() }.to(throwError())
  }

  func test__compileResults__givenSchemaSearchPath_withNoMatches_throwsError() async throws {
    // given
    let config = ApolloCodegen.ConfigurationContext(config: .mock(
      input: .init(schemaPath: directoryURL.appendingPathComponent("file_does_not_exist").path)))

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    // then
    await expect { try await subject.compileGraphQLResult() }
      .to(throwError(ApolloCodegen.Error.cannotLoadSchema))
  }

  func test__compileResults__givenSchemaSearchPaths_withMixedMatches_doesNotThrowError() async throws {
    // given
    let schemaPath = try createFile(containing: schemaData, named: "schema.graphqls")

    let operationPath = try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: "TestQuery.graphql"
    )

    let config = ApolloCodegen.ConfigurationContext(config: .mock(
      input: .init(
        schemaSearchPaths: [
          schemaPath,
          directoryURL.appendingPathComponent("file_does_not_exist").path
        ],
        operationSearchPaths: [operationPath]
      )))

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    // then
    await expect { try await subject.compileGraphQLResult() }.notTo(throwError())
  }

  func test__compileResults__givenOperationSearchPath_withNoMatches_throwsError() async throws {
    // given
    let schemaPath = try createFile(containing: schemaData, named: "schema.graphqls")

    let config = ApolloCodegen.ConfigurationContext(config: .mock(
      input: .init(
        schemaPath: schemaPath,
        operationSearchPaths: [directoryURL.appendingPathComponent("file_does_not_exist").path])
    ))

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    // then
    await expect { try await subject.compileGraphQLResult() }
      .to(throwError(ApolloCodegen.Error.cannotLoadOperations))
  }

  func test__compileResults__givenOperationSearchPaths_withMixedMatches_doesNotThrowError() async throws {
    // given
    let schemaPath = try createFile(containing: schemaData, named: "schema.graphqls")

    let operationPath = try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: "TestQuery.graphql"
    )

    let config = ApolloCodegen.ConfigurationContext(config: .mock(
      input: .init(
        schemaPath: schemaPath,
        operationSearchPaths: [
          operationPath,
          directoryURL.appendingPathComponent("file_does_not_exist").path
        ])))

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    // then
    await expect { try await subject.compileGraphQLResult() }.notTo(throwError())
  }

  // MARK: File Generator Tests

  func test_fileGenerators_givenSchemaAndMultipleOperationDocuments_operations_inSchemaModule_shouldGenerateSchemaAndOperationsFiles() async throws {
    // given
    let schemaPath = ApolloCodegenInternalTestHelpers.Resources.AnimalKingdom.Schema.path
    let operationsPath = ApolloCodegenInternalTestHelpers.Resources.url
      .appendingPathComponent("animalkingdom-graphql")
      .appendingPathComponent("*.graphql").path

    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(
      schemaNamespace: "AnimalKingdomAPI",
      input: .init(
        schemaPath: schemaPath,
        operationSearchPaths: [operationsPath]
      ),
      output: .mock(
        moduleType: .swiftPackage(),
        operations: .inSchemaModule,
        path: directoryURL.path
      )
    ), rootURL: nil)


    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let fileManager = MockApolloFileManager(strict: false)

    let filePathStore = ApolloFileManager.WrittenFiles()
    let concurrentTasks = ConcurrentTaskContainer()

    fileManager.mock(closure: .createFile({ path, data, attributes in
      concurrentTasks.dispatch {
        await filePathStore.addWrittenFile(path: path)
      }
      return true
    }))

    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("Sources/Schema/SchemaMetadata.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/SchemaConfiguration.swift").path,

      directoryURL.appendingPathComponent("Sources/Schema/Enums/SkinCovering.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Interfaces/Pet.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Interfaces/Animal.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Interfaces/WarmBlooded.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Interfaces/HousePet.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/Schema/Enums/SkinCovering.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Enums/RelativeSize.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/Schema/Unions/ClassroomPet.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/Schema/InputObjects/PetSearchInput.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/InputObjects/PetAdoptionInput.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/InputObjects/PetSearchFilters.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/InputObjects/MeasurementsInput.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/Schema/Objects/Height.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Query.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Cat.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Human.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Bird.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Rat.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/PetRock.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Fish.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Crocodile.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Mutation.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Dog.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/Schema/CustomScalars/CustomDate.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/CustomScalars/Object.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/CustomScalars/ID.swift").path,

      directoryURL.appendingPathComponent("Sources/Operations/Queries/AllAnimalsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Queries/AllAnimalsIncludeSkipQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Queries/ClassroomPetsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Queries/DogQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Queries/PetSearchQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Queries/FindPetQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Mutations/PetAdoptionMutation.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/Fragments/PetDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Fragments/DogFragment.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Fragments/ClassroomPetDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Fragments/HeightInMeters.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Fragments/WarmBloodedDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Fragments/CrocodileFragment.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/LocalCacheMutations/AllAnimalsLocalCacheMutation.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/LocalCacheMutations/PetDetailsMutation.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/LocalCacheMutations/PetSearchLocalCacheMutation.graphql.swift").path,

      directoryURL.appendingPathComponent("Package.swift").path,
    ]

    // when
    let compilationResult = try await subject.compileGraphQLResult()

    let ir = IRBuilder(compilationResult: compilationResult)

    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )
    await concurrentTasks.waitForAllTasks()
    let filePaths = await filePathStore.value

    // then
    expect(filePaths).to(equal(expectedPaths))
    expect(fileManager.allClosuresCalled).to(beTrue())
  }

  func test_fileGenerators_givenSchemaAndMultipleOperationDocuments_operations_absolute_shouldGenerateSchemaAndOperationsFiles() async throws {
    // given
    let schemaPath = ApolloCodegenInternalTestHelpers.Resources.AnimalKingdom.Schema.path
    let operationsPath = ApolloCodegenInternalTestHelpers.Resources.url
      .appendingPathComponent("animalkingdom-graphql")
      .appendingPathComponent("*.graphql").path

    let operationsOutputURL = directoryURL.appendingPathComponent("AbsoluteSources")

    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(
      schemaNamespace: "AnimalKingdomAPI",
      input: .init(
        schemaPath: schemaPath,
        operationSearchPaths: [operationsPath]
      ),
      output: .mock(
        moduleType: .swiftPackage(),
        operations: .absolute(path: operationsOutputURL.path),
        path: directoryURL.path
      )
    ), rootURL: nil)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let fileManager = MockApolloFileManager(strict: false)

    let filePathStore = ApolloFileManager.WrittenFiles()
    let concurrentTasks = ConcurrentTaskContainer()

    fileManager.mock(closure: .createFile({ path, data, attributes in
      concurrentTasks.dispatch {
        await filePathStore.addWrittenFile(path: path)
      }
      return true
    }))

    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("Sources/SchemaMetadata.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaConfiguration.swift").path,

      directoryURL.appendingPathComponent("Sources/Enums/SkinCovering.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Interfaces/Pet.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Interfaces/Animal.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Interfaces/WarmBlooded.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Interfaces/HousePet.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Enums/SkinCovering.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Enums/RelativeSize.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Unions/ClassroomPet.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/InputObjects/PetAdoptionInput.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/InputObjects/PetSearchFilters.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/InputObjects/PetSearchInput.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/InputObjects/MeasurementsInput.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Height.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Query.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Cat.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Human.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Bird.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Rat.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/PetRock.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Fish.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Crocodile.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Mutation.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Dog.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/CustomScalars/CustomDate.swift").path,
      directoryURL.appendingPathComponent("Sources/CustomScalars/Object.swift").path,
      directoryURL.appendingPathComponent("Sources/CustomScalars/ID.swift").path,

      operationsOutputURL.appendingPathComponent("Queries/AllAnimalsQuery.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("Queries/DogQuery.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("Queries/AllAnimalsIncludeSkipQuery.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("Queries/ClassroomPetsQuery.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("Queries/PetSearchQuery.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("Queries/FindPetQuery.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("Mutations/PetAdoptionMutation.graphql.swift").path,

      operationsOutputURL.appendingPathComponent("Fragments/PetDetails.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("Fragments/DogFragment.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("Fragments/ClassroomPetDetails.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("Fragments/HeightInMeters.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("Fragments/WarmBloodedDetails.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("Fragments/CrocodileFragment.graphql.swift").path,

      operationsOutputURL.appendingPathComponent("LocalCacheMutations/AllAnimalsLocalCacheMutation.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("LocalCacheMutations/PetDetailsMutation.graphql.swift").path,
      operationsOutputURL.appendingPathComponent("LocalCacheMutations/PetSearchLocalCacheMutation.graphql.swift").path,

      directoryURL.appendingPathComponent("Package.swift").path,
    ]

    // when
    let compilationResult = try await subject.compileGraphQLResult()

    let ir = IRBuilder(compilationResult: compilationResult)

    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )
    await concurrentTasks.waitForAllTasks()
    let filePaths = await filePathStore.value

    // then
    expect(filePaths).to(equal(expectedPaths))
    expect(fileManager.allClosuresCalled).to(beTrue())
  }

  func test_fileGenerators_givenSchemaAndOperationDocuments_whenAppendingFileSuffix_shouldGenerateSchemaFilenamesWithSuffix() async throws {
    // given
    let schemaPath = ApolloCodegenInternalTestHelpers.Resources.AnimalKingdom.Schema.path
    let operationsPath = ApolloCodegenInternalTestHelpers.Resources.url
      .appendingPathComponent("animalkingdom-graphql")
      .appendingPathComponent("*.graphql").path

    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(
      schemaNamespace: "AnimalKingdomAPI",
      input: .init(
        schemaPath: schemaPath,
        operationSearchPaths: [operationsPath]
      ),
      output: .mock(
        moduleType: .swiftPackage(),
        operations: .inSchemaModule,
        path: directoryURL.path
      ),
      options: .init(appendSchemaTypeFilenameSuffix: true)
    ), rootURL: nil)


    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let fileManager = MockApolloFileManager(strict: false)

    let filePathStore = ApolloFileManager.WrittenFiles()
    let concurrentTasks = ConcurrentTaskContainer()

    fileManager.mock(closure: .createFile({ path, data, attributes in
      concurrentTasks.dispatch {
        await filePathStore.addWrittenFile(path: path)
      }
      return true
    }))

    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("Sources/Schema/SchemaMetadata.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/SchemaConfiguration.swift").path,

      directoryURL.appendingPathComponent("Sources/Schema/Enums/SkinCovering.enum.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Enums/SkinCovering.enum.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Enums/RelativeSize.enum.graphql.swift").path,
      
      directoryURL.appendingPathComponent("Sources/Schema/Interfaces/Pet.interface.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Interfaces/Animal.interface.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Interfaces/WarmBlooded.interface.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Interfaces/HousePet.interface.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/Schema/Unions/ClassroomPet.union.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/Schema/InputObjects/PetSearchInput.inputObject.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/InputObjects/PetAdoptionInput.inputObject.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/InputObjects/PetSearchFilters.inputObject.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/InputObjects/MeasurementsInput.inputObject.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/Schema/Objects/Height.object.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Query.object.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Cat.object.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Human.object.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Bird.object.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Rat.object.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/PetRock.object.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Fish.object.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Crocodile.object.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Mutation.object.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/Objects/Dog.object.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/Schema/CustomScalars/CustomDate.scalar.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/CustomScalars/Object.scalar.swift").path,
      directoryURL.appendingPathComponent("Sources/Schema/CustomScalars/ID.scalar.swift").path,

      directoryURL.appendingPathComponent("Sources/Operations/Queries/AllAnimalsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Queries/AllAnimalsIncludeSkipQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Queries/ClassroomPetsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Queries/DogQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Queries/PetSearchQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Queries/FindPetQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Operations/Mutations/PetAdoptionMutation.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/Fragments/PetDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Fragments/DogFragment.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Fragments/ClassroomPetDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Fragments/HeightInMeters.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Fragments/WarmBloodedDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Fragments/CrocodileFragment.graphql.swift").path,

      directoryURL.appendingPathComponent("Sources/LocalCacheMutations/AllAnimalsLocalCacheMutation.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/LocalCacheMutations/PetDetailsMutation.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/LocalCacheMutations/PetSearchLocalCacheMutation.graphql.swift").path,

      directoryURL.appendingPathComponent("Package.swift").path,
    ]

    // when
    let compilationResult = try await subject.compileGraphQLResult()

    let ir = IRBuilder(compilationResult: compilationResult)

    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )
    await concurrentTasks.waitForAllTasks()
    let filePaths = await filePathStore.value

    // then
    expect(filePaths).to(equal(expectedPaths))
    expect(fileManager.allClosuresCalled).to(beTrue())
  }

  func test_fileGenerators_givenTestMockOutput_absolutePath_shouldGenerateTestMocks() async throws {
    // given
    let schemaPath = ApolloCodegenInternalTestHelpers.Resources.AnimalKingdom.Schema.path
    let operationsPath = ApolloCodegenInternalTestHelpers.Resources.url
      .appendingPathComponent("animalkingdom-graphql")
      .appendingPathComponent("**/*.graphql").path

    let config =  ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration(
      schemaNamespace: "AnimalKingdomAPI",
      input: .init(schemaPath: schemaPath, operationSearchPaths: [operationsPath]),
      output: .init(
        schemaTypes: .init(path: directoryURL.path,
                           moduleType: .swiftPackage()),
        operations: .inSchemaModule,
        testMocks: .absolute(path: directoryURL.appendingPathComponent("TestMocks").path)
      )
    ), rootURL: nil)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let fileManager = MockApolloFileManager(strict: false)

    let filePathStore = ApolloFileManager.WrittenFiles()
    let concurrentTasks = ConcurrentTaskContainer()

    fileManager.mock(closure: .createFile({ path, data, attributes in
      if path.contains("/TestMocks/") {
        concurrentTasks.dispatch {
          await filePathStore.addWrittenFile(path: path)
        }
      }
      return true
    }))

    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("TestMocks/Height+Mock.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/Query+Mock.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/Cat+Mock.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/Human+Mock.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/Bird+Mock.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/Rat+Mock.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/PetRock+Mock.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/Mutation+Mock.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/Dog+Mock.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/Fish+Mock.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/Crocodile+Mock.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/MockObject+Unions.graphql.swift").path,
      directoryURL.appendingPathComponent("TestMocks/MockObject+Interfaces.graphql.swift").path,
    ]

    // when
    let compilationResult = try await subject.compileGraphQLResult()

    let ir = IRBuilder(compilationResult: compilationResult)

    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )
    await concurrentTasks.waitForAllTasks()
    let filePaths = await filePathStore.value

    // then
    expect(filePaths).to(equal(expectedPaths))
    expect(fileManager.allClosuresCalled).to(beTrue())
  }

  // MARK: Custom Root URL Tests

  func test_fileGenerators_givenCustomRootDirectoryPath_operations_inSchemaModule__shouldGenerateFilesWithCustomRootPath() async throws {
    // given
    let schemaPath = ApolloCodegenInternalTestHelpers.Resources.AnimalKingdom.Schema.path
    let operationsPath = ApolloCodegenInternalTestHelpers.Resources.url
      .appendingPathComponent("animalkingdom-graphql")
      .appendingPathComponent("*.graphql").path

    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(
      schemaNamespace: "AnimalKingdomAPI",
      input: .init(
        schemaPath: schemaPath,
        operationSearchPaths: [operationsPath]
      ),
      output: .mock(
        moduleType: .swiftPackage(),
        operations: .inSchemaModule,
        path: "./RelativePath"
      )
    ), rootURL: directoryURL)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let fileManager = MockApolloFileManager(strict: false)

    let filePathStore = ApolloFileManager.WrittenFiles()
    let concurrentTasks = ConcurrentTaskContainer()

    fileManager.mock(closure: .createFile({ path, data, attributes in
      concurrentTasks.dispatch {
        await filePathStore.addWrittenFile(path: path)
      }
      return true
    }))

    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/SchemaMetadata.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/SchemaConfiguration.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Enums/SkinCovering.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Interfaces/Pet.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Interfaces/Animal.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Interfaces/WarmBlooded.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Interfaces/HousePet.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Enums/SkinCovering.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Enums/RelativeSize.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Unions/ClassroomPet.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/InputObjects/PetAdoptionInput.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/InputObjects/PetSearchFilters.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/InputObjects/PetSearchInput.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/InputObjects/MeasurementsInput.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Objects/Height.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Objects/Query.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Objects/Cat.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Objects/Human.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Objects/Bird.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Objects/Rat.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Objects/PetRock.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Objects/Fish.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Objects/Crocodile.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Objects/Mutation.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/Objects/Dog.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/CustomScalars/CustomDate.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/CustomScalars/Object.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Schema/CustomScalars/ID.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Operations/Queries/AllAnimalsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Operations/Queries/DogQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Operations/Queries/AllAnimalsIncludeSkipQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Operations/Queries/ClassroomPetsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Operations/Queries/FindPetQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Operations/Queries/PetSearchQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Operations/Queries/PetSearchQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Operations/Mutations/PetAdoptionMutation.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Fragments/PetDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Fragments/DogFragment.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Fragments/ClassroomPetDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Fragments/HeightInMeters.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Fragments/WarmBloodedDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Fragments/CrocodileFragment.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/LocalCacheMutations/AllAnimalsLocalCacheMutation.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/LocalCacheMutations/PetDetailsMutation.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/LocalCacheMutations/PetSearchLocalCacheMutation.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Package.swift").path,
    ]

    // when
    let compilationResult = try await subject.compileGraphQLResult()

    let ir = IRBuilder(compilationResult: compilationResult)

    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )
    await concurrentTasks.waitForAllTasks()
    let filePaths = await filePathStore.value

    // then
    expect(filePaths).to(equal(expectedPaths))
    expect(fileManager.allClosuresCalled).to(beTrue())
  }

  func test_fileGenerators_givenCustomRootDirectoryPath_operations_absolute__shouldGenerateFilesWithCustomRootPath() async throws {
    // given
    let schemaPath = ApolloCodegenInternalTestHelpers.Resources.AnimalKingdom.Schema.path
    let operationsPath = ApolloCodegenInternalTestHelpers.Resources.url
      .appendingPathComponent("animalkingdom-graphql")
      .appendingPathComponent("*.graphql").path

    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(
      schemaNamespace: "AnimalKingdomAPI",
      input: .init(
        schemaPath: schemaPath,
        operationSearchPaths: [operationsPath]
      ),
      output: .mock(
        moduleType: .swiftPackage(),
        operations: .absolute(path: "./RelativeOperations"),
        path: "./RelativePath"
      )
    ), rootURL: directoryURL)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let fileManager = MockApolloFileManager(strict: false)

    let filePathStore = ApolloFileManager.WrittenFiles()
    let concurrentTasks = ConcurrentTaskContainer()

    fileManager.mock(closure: .createFile({ path, data, attributes in
      concurrentTasks.dispatch {
        await filePathStore.addWrittenFile(path: path)
      }
      return true
    }))

    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("RelativePath/Sources/SchemaMetadata.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/SchemaConfiguration.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Enums/SkinCovering.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Interfaces/Pet.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Interfaces/Animal.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Interfaces/WarmBlooded.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Interfaces/HousePet.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Enums/SkinCovering.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Enums/RelativeSize.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Unions/ClassroomPet.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/InputObjects/PetAdoptionInput.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/InputObjects/PetSearchFilters.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/InputObjects/PetSearchInput.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/InputObjects/MeasurementsInput.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/Objects/Height.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Objects/Query.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Objects/Cat.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Objects/Human.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Objects/Bird.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Objects/Rat.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Objects/PetRock.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Objects/Fish.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Objects/Crocodile.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Objects/Mutation.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/Objects/Dog.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Sources/CustomScalars/CustomDate.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/CustomScalars/Object.swift").path,
      directoryURL.appendingPathComponent("RelativePath/Sources/CustomScalars/ID.swift").path,

      directoryURL.appendingPathComponent("RelativeOperations/Queries/AllAnimalsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Queries/DogQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Queries/AllAnimalsIncludeSkipQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Queries/ClassroomPetsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Queries/FindPetQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Queries/PetSearchQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Queries/PetSearchQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Mutations/PetAdoptionMutation.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativeOperations/Fragments/PetDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Fragments/DogFragment.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Fragments/ClassroomPetDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Fragments/HeightInMeters.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Fragments/WarmBloodedDetails.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/Fragments/CrocodileFragment.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativeOperations/LocalCacheMutations/AllAnimalsLocalCacheMutation.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/LocalCacheMutations/PetDetailsMutation.graphql.swift").path,
      directoryURL.appendingPathComponent("RelativeOperations/LocalCacheMutations/PetSearchLocalCacheMutation.graphql.swift").path,

      directoryURL.appendingPathComponent("RelativePath/Package.swift").path,
    ]

    // when
    let compilationResult = try await subject.compileGraphQLResult()

    let ir = IRBuilder(compilationResult: compilationResult)

    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )
    await concurrentTasks.waitForAllTasks()
    let filePaths = await filePathStore.value

    // then
    expect(filePaths).to(equal(expectedPaths))
    expect(fileManager.allClosuresCalled).to(beTrue())
  }

  // MARK: Old File Deletion Tests

  func test__fileDeletion__givenPruneGeneratedFiles_false__doesNotDeleteUnusedGeneratedFiles() async throws {
    // given
    try createFile(containing: schemaData, named: "schema.graphqls")

    try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: "TestQuery.graphql"
    )

    let testFile = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: "SchemaModule"
    )
    let testInSourcesFile = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "SchemaModule/Sources"
    )
    let testInOtherFolderFile = try createFile(
      filename: "TestGeneratedC.graphql.swift",
      inDirectory: "SchemaModule/OtherFolder"
    )

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        operations: .inSchemaModule
      ),
      options: .init(pruneGeneratedFiles: false)
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(atPath: testFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInSourcesFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInOtherFolderFile)).to(beTrue())
  }

  func test__fileDeletion__givenGeneratedFilesExist_InSchemaModuleDirectory_deletesOnlyGeneratedFiles() async throws {
    // given
    try createFile(containing: schemaData, named: "schema.graphqls")

    try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: "TestQuery.graphql"
    )

    let testFile = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: "SchemaModule"
    )
    let testInSourcesFile = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "SchemaModule/Sources"
    )
    let testInOtherFolderFile = try createFile(
      filename: "TestGeneratedC.graphql.swift",
      inDirectory: "SchemaModule/OtherFolder"
    )

    let testUserFile = try createFile(
      filename: "TestUserFileA.swift",
      inDirectory: "SchemaModule"
    )
    let testInSourcesUserFile = try createFile(
      filename: "TestUserFileB.swift",
      inDirectory: "SchemaModule/Sources"
    )
    let testInOtherFolderUserFile = try createFile(
      filename: "TestUserFileC.swift",
      inDirectory: "SchemaModule/OtherFolder"
    )

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        operations: .inSchemaModule
      )
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(atPath: testFile)).to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInSourcesFile)).to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInOtherFolderFile)).to(beFalse())

    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInSourcesUserFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInOtherFolderUserFile)).to(beTrue())
  }

  func test__fileDeletion__givenGeneratedFilesExist_InOperationAbsoluteDirectory_deletesOnlyGeneratedFiles() async throws {
    // given
    let absolutePath = "OperationPath"
    try createFile(containing: schemaData, named: "schema.graphqls")

    try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: "TestQuery.graphql"
    )

    let testFile = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: absolutePath
    )
    let testInChildFile = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "\(absolutePath)/Child"
    )

    let testUserFile = try createFile(
      filename: "TestFileA.swift",
      inDirectory: absolutePath
    )
    let testInChildUserFile = try createFile(
      filename: "TestFileB.swift",
      inDirectory: "\(absolutePath)/Child"
    )

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        operations: .absolute(path: "OperationPath")
      )
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(atPath: testFile)).to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInChildFile)).to(beFalse())

    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInChildUserFile)).to(beTrue())
  }

  func test__fileDeletion__givenGeneratedFilesExist_InOperationRelativeDirectories_deletesOnlyRelativeGeneratedFilesInOperationSearchPaths() async throws {
    // given
    try createFile(containing: schemaData, named: "schema.graphqls")

    try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: "TestQuery.graphql",
      inDirectory: "code"
    )

    let testGeneratedFileInRootPath = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: "code"
    )
    let testGeneratedFileInChildPath = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "code/child"
    )
    let testGeneratedFileInNestedChildPath = try createFile(
      filename: "TestGeneratedC.graphql.swift",
      inDirectory: "code/one/two"
    )

    let testGeneratedFileNotInRelativePath = try createFile(
      filename: "TestGeneratedD.graphql.swift",
      inDirectory: nil
    )
    let testGeneratedFileNotInRelativeChildPath = try createFile(
      filename: "TestGeneratedE.graphql.swift",
      inDirectory: "other/child"
    )

    let testUserFileInRootPath = try createFile(
      filename: "TestUserFileA.swift",
      inDirectory: "code"
    )
    let testUserFileInChildPath = try createFile(
      filename: "TestUserFileB.swift",
      inDirectory: "code/child"
    )
    let testUserFileInNestedChildPath = try createFile(
      filename: "TestUserFileC.swift",
      inDirectory: "code/one/two"
    )

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["code/**/*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        operations: .relative(subpath: nil)
      )
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInRootPath)).to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInChildPath)).to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInNestedChildPath)).to(beFalse())

    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativePath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativeChildPath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInRootPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInChildPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInNestedChildPath)).to(beTrue())
  }

  func test__fileDeletion__givenGeneratedFilesExist_InOperationRelativeDirectories_operationSearchPathWithoutDirectories_deletesOnlyRelativeGeneratedFilesInOperationSearchPaths() async throws {
    // given
    try createFile(containing: schemaData, named: "schema.graphqls")

    try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: "code.graphql"
    )

    let testGeneratedFileInRootPath = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: "code"
    )
    let testGeneratedFileInChildPath = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "code/child"
    )
    let testGeneratedFileInNestedChildPath = try createFile(
      filename: "TestGeneratedC.graphql.swift",
      inDirectory: "code/one/two"
    )

    let testGeneratedFileNotInRelativePath = try createFile(
      filename: "TestGeneratedD.graphql.swift",
      inDirectory: nil
    )
    let testGeneratedFileNotInRelativeChildPath = try createFile(
      filename: "TestGeneratedE.graphql.swift",
      inDirectory: "other/child"
    )

    let testUserFileInRootPath = try createFile(
      filename: "TestUserFileA.swift",
      inDirectory: "code"
    )
    let testUserFileInChildPath = try createFile(
      filename: "TestUserFileB.swift",
      inDirectory: "code/child"
    )
    let testUserFileInNestedChildPath = try createFile(
      filename: "TestUserFileC.swift",
      inDirectory: "code/one/two"
    )

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["code.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        operations: .relative(subpath: nil)
      )
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInRootPath)).to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInChildPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInNestedChildPath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativePath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativeChildPath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInRootPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInChildPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInNestedChildPath)).to(beTrue())
  }

  func test__fileDeletion__inOperationRelativeDirectory__whenSymlinkIsUsed() async throws {
    // given
    try createFile(containing: schemaData, named: "schema.graphqls")

    let schemaDirectory = "SchemaModule"
    let codeDirectory = "code"
    let relativeSubPath = "Operations"
    let operationFilename = "TestQuery.graphql"

    try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: operationFilename,
      inDirectory: codeDirectory
    )

    let symLinkURL = directoryURL.appendingPathComponent("/\(codeDirectory)/\(relativeSubPath)/")
    let symLinkDestURL = directoryURL.appendingPathComponent("\(schemaDirectory)/Sources/Operations/")
    let fileValidationPath = symLinkDestURL.appendingPathComponent("\(operationFilename).swift").path

    //setup symlink folder
    try testFileManager.fileManager.createDirectory(at: symLinkDestURL, withIntermediateDirectories: true)
    try testFileManager.fileManager.createSymbolicLink(at: symLinkURL, withDestinationURL: symLinkDestURL)

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["code/**/*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: schemaDirectory,
                           moduleType: .swiftPackage()),
        operations: .relative(subpath: relativeSubPath)
      ),
      options: .init(
        pruneGeneratedFiles: true
      )
    )

    // then

    // running codegen multiple times to validate symlink related file creation/deletion bug
    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)
    expect(ApolloFileManager.default.doesFileExist(atPath: fileValidationPath)).to(beTrue())

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)
    expect(ApolloFileManager.default.doesFileExist(atPath: fileValidationPath)).to(beTrue())

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)
    expect(ApolloFileManager.default.doesFileExist(atPath: fileValidationPath)).to(beTrue())

  }

  func test__fileDeletion__givenGeneratedFilesExist_InOperationRelativeDirectoriesWithSubPath_deletesOnlyRelativeGeneratedFilesInOperationSearchPaths() async throws {
    // given
    try createFile(containing: schemaData, named: "schema.graphqls")

    let testGeneratedFileInRootPath = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: "code"
    )
    let testGeneratedFileInChildPath = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "code/child"
    )
    let testGeneratedFileInNestedChildPath = try createFile(
      filename: "TestGeneratedC.graphql.swift",
      inDirectory: "code/one/two"
    )

    let testGeneratedFileNotInRelativePath = try createFile(
      filename: "TestGeneratedD.graphql.swift",
      inDirectory: nil
    )
    let testGeneratedFileNotInRelativeChildPath = try createFile(
      filename: "TestGeneratedE.graphql.swift",
      inDirectory: "other/child"
    )

    let testGeneratedFileInRootPathSubpath = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: "code/subpath"
    )
    let testGeneratedFileInChildPathSubpath = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "code/child/subpath"
    )
    let testGeneratedFileInNestedChildPathSubpath = try createFile(
      filename: "TestGeneratedC.graphql.swift",
      inDirectory: "code/one/two/subpath"
    )

    let testGeneratedFileNotInRelativePathSubpath = try createFile(
      filename: "TestGeneratedD.graphql.swift",
      inDirectory: "subpath"
    )
    let testGeneratedFileNotInRelativeChildPathSubpath = try createFile(
      filename: "TestGeneratedE.graphql.swift",
      inDirectory: "other/child/subpath"
    )

    let testUserFileInRootPath = try createOperationFile(
      type: .query,
      named: "OperationA",
      filename: "TestUserFileOperationA.graphql",
      inDirectory: "code"
    )
    let testUserFileInChildPath = try createOperationFile(
      type: .query,
      named: "OperationB",
      filename: "TestUserFileOperationB.graphql",
      inDirectory: "code/child"
    )
    let testUserFileInNestedChildPath = try createOperationFile(
      type: .query,
      named: "OperationC",
      filename: "TestUserFileOperationC.graphql",
      inDirectory: "code/one/two"
    )

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["code/**/*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        operations: .relative(subpath: "subpath")
      )
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInRootPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInChildPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInNestedChildPath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativePath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativeChildPath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInRootPathSubpath)).to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInChildPathSubpath)).to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInNestedChildPathSubpath)).to(beFalse())

    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativePathSubpath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativeChildPathSubpath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInRootPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInChildPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInNestedChildPath)).to(beTrue())
  }

  func test__fileDeletion__givenGeneratedFilesExist_InOperationRelativeDirectoriesWithSubPath_operationSearchPathWithNoDirectories_deletesOnlyRelativeGeneratedFilesInOperationSearchPaths() async throws {
    // given
    try createFile(containing: schemaData, named: "schema.graphqls")

    try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: "code.graphql"
    )

    let testGeneratedFileInRootPath = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: "code"
    )
    let testGeneratedFileInChildPath = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "code/child"
    )
    let testGeneratedFileInNestedChildPath = try createFile(
      filename: "TestGeneratedC.graphql.swift",
      inDirectory: "code/one/two"
    )

    let testGeneratedFileNotInRelativePath = try createFile(
      filename: "TestGeneratedD.graphql.swift",
      inDirectory: nil
    )
    let testGeneratedFileNotInRelativeChildPath = try createFile(
      filename: "TestGeneratedE.graphql.swift",
      inDirectory: "other/child"
    )

    let testGeneratedFileInRootPathSubpath = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: "code/subpath"
    )
    let testGeneratedFileInChildPathSubpath = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "code/child/subpath"
    )
    let testGeneratedFileInNestedChildPathSubpath = try createFile(
      filename: "TestGeneratedC.graphql.swift",
      inDirectory: "code/one/two/subpath"
    )

    let testGeneratedFileNotInRelativePathSubpath = try createFile(
      filename: "TestGeneratedD.graphql.swift",
      inDirectory: "subpath"
    )
    let testGeneratedFileNotInRelativeChildPathSubpath = try createFile(
      filename: "TestGeneratedE.graphql.swift",
      inDirectory: "other/child/subpath"
    )

    let testUserFileInRootPath = try createOperationFile(
      type: .query,
      named: "OperationA",
      filename: "TestUserFileOperationA.graphql",
      inDirectory: "code"
    )
    let testUserFileInChildPath = try createOperationFile(
      type: .query,
      named: "OperationB",
      filename: "TestUserFileOperationB.graphql",
      inDirectory: "code/child"
    )
    let testUserFileInNestedChildPath = try createOperationFile(
      type: .query,
      named: "OperationC",
      filename: "TestUserFileOperationC.graphql",
      inDirectory: "code/one/two"
    )

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["code.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        operations: .relative(subpath: "subpath")
      )
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInRootPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInChildPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInNestedChildPath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativePath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativeChildPath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInRootPathSubpath)).to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInChildPathSubpath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInNestedChildPathSubpath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativePathSubpath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativeChildPathSubpath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInRootPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInChildPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInNestedChildPath)).to(beTrue())
  }

  func test__fileDeletion__givenGeneratedFilesExist_InOperationRelativeDirectoriesWithSubPath_operationSearchPathWithoutGlobstar_deletesOnlyRelativeGeneratedFilesInOperationSearchPaths() async throws {
    // given
    try createFile(containing: schemaData, named: "schema.graphqls")

    let testGeneratedFileInRootPath = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: "code"
    )
    let testGeneratedFileInChildPath = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "code/child"
    )
    let testGeneratedFileInNestedChildPath = try createFile(
      filename: "TestGeneratedC.graphql.swift",
      inDirectory: "code/child/A"
    )

    let testGeneratedFileNotInRelativePath = try createFile(
      filename: "TestGeneratedD.graphql.swift",
      inDirectory: nil
    )
    let testGeneratedFileNotInRelativeChildPath = try createFile(
      filename: "TestGeneratedE.graphql.swift",
      inDirectory: "other/child"
    )

    let testGeneratedFileInRootPathSubpath = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: "code/subpath"
    )
    let testGeneratedFileInChildPathSubpath = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "code/child/subpath"
    )
    let testGeneratedFileInNestedChildPathSubpath = try createFile(
      filename: "TestGeneratedC.graphql.swift",
      inDirectory: "code/child/next/subpath"
    )

    let testGeneratedFileNotInRelativePathSubpath = try createFile(
      filename: "TestGeneratedD.graphql.swift",
      inDirectory: "subpath"
    )
    let testGeneratedFileNotInRelativeChildPathSubpath = try createFile(
      filename: "TestGeneratedE.graphql.swift",
      inDirectory: "other/child/subpath"
    )

    let testUserFileInRootPath = try createOperationFile(
      type: .query,
      named: "OperationA",
      filename: "TestUserFileOperationA.graphql",
      inDirectory: "code"
    )
    let testUserFileInChildPath = try createOperationFile(
      type: .query,
      named: "OperationB",
      filename: "TestUserFileOperationB.graphql",
      inDirectory: "code/child"
    )
    let testUserFileInNestedChildPath = try createOperationFile(
      type: .query,
      named: "OperationC",
      filename: "TestUserFileOperationC.graphql",
      inDirectory: "code/child/next"
    )

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["code/child/*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        operations: .relative(subpath: "subpath")
      )
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInRootPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInChildPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInNestedChildPath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativePath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativeChildPath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInRootPathSubpath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInChildPathSubpath)).to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileInNestedChildPathSubpath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativePathSubpath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testGeneratedFileNotInRelativeChildPathSubpath)).to(beTrue())

    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInRootPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInChildPath)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFileInNestedChildPath)).to(beTrue())
  }

  func test__fileDeletion__givenGeneratedTestMockFilesExist_InAbsoluteDirectory_deletesOnlyGeneratedFiles() async throws {
    // given
    let absolutePath = "TestMocksPath"
    try createFile(containing: schemaData, named: "schema.graphqls")

    try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: "TestQuery.graphql"
    )

    let testFile = try createFile(
      filename: "TestGeneratedA.graphql.swift",
      inDirectory: absolutePath
    )
    let testInChildFile = try createFile(
      filename: "TestGeneratedB.graphql.swift",
      inDirectory: "\(absolutePath)/Child"
    )

    let testUserFile = try createFile(
      filename: "TestFileA.swift",
      inDirectory: absolutePath
    )
    let testInChildUserFile = try createFile(
      filename: "TestFileB.swift",
      inDirectory: "\(absolutePath)/Child"
    )

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        operations: .inSchemaModule,
        testMocks: .absolute(path: absolutePath)
      )
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(atPath: testFile)).to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInChildFile)).to(beFalse())

    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInChildUserFile)).to(beTrue())
  }

  func test__fileDeletion__givenGeneratedTestMockFilesExist_InSwiftPackageDirectory_deletesOnlyGeneratedFiles() async throws {
    // given
    try createFile(containing: schemaData, named: "schema.graphqls")

    try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: "TestQuery.graphql"
    )

    let testInTestMocksFolderFile = try createFile(
      filename: "TestGeneratedD.graphql.swift",
      inDirectory: "SchemaModule/TestMocks"
    )

    let testUserFile = try createFile(
      filename: "TestUserFileA.swift",
      inDirectory: "SchemaModule"
    )
    let testInSourcesUserFile = try createFile(
      filename: "TestUserFileB.swift",
      inDirectory: "SchemaModule/Sources"
    )
    let testInOtherFolderUserFile = try createFile(
      filename: "TestUserFileC.swift",
      inDirectory: "SchemaModule/OtherFolder"
    )
    let testInTestMocksFolderUserFile = try createFile(
      filename: "TestUserFileD.swift",
      inDirectory: "SchemaModule/TestMocks"
    )

    // when
    let config = ApolloCodegenConfiguration.mock(
      schemaNamespace: "TestSchema",
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        testMocks: .swiftPackage()
      )
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(atPath: testInTestMocksFolderFile)).to(beFalse())

    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInSourcesUserFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInOtherFolderUserFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInTestMocksFolderUserFile)).to(beTrue())
  }

  func test__fileDeletion__givenGeneratedTestMockFilesExist_InSwiftPackageWithCustomTargetNameDirectory_deletesOnlyGeneratedFiles() async throws {
    // given
    let testMockTargetName = "ApolloTestTarget"
    try createFile(containing: schemaData, named: "schema.graphqls")

    try createOperationFile(
      type: .query,
      named: "TestQuery",
      filename: "TestQuery.graphql"
    )

    let testInTestMocksFolderFile = try createFile(
      filename: "TestGeneratedD.graphql.swift",
      inDirectory: "SchemaModule/\(testMockTargetName)"
    )

    let testUserFile = try createFile(
      filename: "TestUserFileA.swift",
      inDirectory: "SchemaModule"
    )
    let testInSourcesUserFile = try createFile(
      filename: "TestUserFileB.swift",
      inDirectory: "SchemaModule/Sources"
    )
    let testInOtherFolderUserFile = try createFile(
      filename: "TestUserFileC.swift",
      inDirectory: "SchemaModule/OtherFolder"
    )
    let testInTestMocksFolderUserFile = try createFile(
      filename: "TestUserFileD.swift",
      inDirectory: "SchemaModule/\(testMockTargetName)"
    )

    // when
    let config = ApolloCodegenConfiguration.mock(
      schemaNamespace: "TestSchema",
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        testMocks: .swiftPackage(targetName: testMockTargetName)
      )
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(atPath: testInTestMocksFolderFile)).to(beFalse())

    expect(ApolloFileManager.default.doesFileExist(atPath: testUserFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInSourcesUserFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInOtherFolderUserFile)).to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(atPath: testInTestMocksFolderUserFile)).to(beTrue())
  }

  // MARK: Suffix Renaming Tests

  func test__fileRenaming__givenGeneratedPreSuffixFilesExist_withAppendSchemaFilenameSuffix_true_shouldRenameFileWithSuffix() async throws {
    // given
    try createFile(
      containing: """
      type Query {
        allBooks: [Book!]!
      }
      
      scalar CustomDate
      
      type Book {
        publishedDate: CustomDate!
        author: Author!
      }
      
      type Author {
        name: String!
      }
      """.asData,
      named: "schema.graphqls"
    )

    try createFile(
      containing: """
      query AllBooks {
        allBooks {
          publishedDate
          author {
            name
          }
        }
      }
      """.asData,
      named: "AllBooksQuery.graphql"
    )

    // Create the pre-suffixed generated file and validate that it exists
    let customScalarsDirectory = "SchemaModule/Sources/Schema/CustomScalars"
    let preSuffixFilename = "CustomDate.swift"

    try createFile(filename: preSuffixFilename, inDirectory: customScalarsDirectory)

    expect(ApolloFileManager.default.doesFileExist(
      atPath: self.directoryURL.relativePath + "/\(customScalarsDirectory)/\(preSuffixFilename)"))
    .to(beTrue())

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule", moduleType: .swiftPackage()),
        operations: .inSchemaModule
      ),
      options: .init(
        appendSchemaTypeFilenameSuffix: true
      )
    ) 

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(
      atPath: self.directoryURL.relativePath + "/\(customScalarsDirectory)/CustomDate.scalar.swift"))
    .to(beTrue())
    expect(ApolloFileManager.default.doesFileExist(
      atPath: self.directoryURL.relativePath + "/\(customScalarsDirectory)/\(preSuffixFilename)"))
    .to(beFalse())
  }

  func test__fileRenaming__givenGeneratedPreSuffixFilesExist_withAppendSchemaFilenameSuffix_false_shouldNotRenameFile() async throws {
    // given
    try createFile(
      containing: """
      type Query {
        allBooks: [Book!]!
      }
      
      scalar CustomDate
      
      type Book {
        publishedDate: CustomDate!
        author: Author!
      }
      
      type Author {
        name: String!
      }
      """.asData,
      named: "schema.graphqls"
    )

    try createFile(
      containing: """
      query AllBooks {
        allBooks {
          publishedDate
          author {
            name
          }
        }
      }
      """.asData,
      named: "AllBooksQuery.graphql"
    )

    // Create the pre-suffixed generated file and validate that it exists
    let customScalarsDirectory = "SchemaModule/Sources/Schema/CustomScalars"
    let preSuffixFilename = "CustomDate.swift"

    try createFile(filename: preSuffixFilename, inDirectory: customScalarsDirectory)

    expect(ApolloFileManager.default.doesFileExist(
      atPath: self.directoryURL.relativePath + "/\(customScalarsDirectory)/\(preSuffixFilename)"))
    .to(beTrue())

    // when
    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule", moduleType: .swiftPackage()),
        operations: .inSchemaModule
      ),
      options: .init(
        appendSchemaTypeFilenameSuffix: false
      )
    )

    try await ApolloCodegen.build(with: config, withRootURL: directoryURL)

    // then
    expect(ApolloFileManager.default.doesFileExist(
      atPath: self.directoryURL.relativePath + "/\(customScalarsDirectory)/CustomDate.scalar.swift"))
    .to(beFalse())
    expect(ApolloFileManager.default.doesFileExist(
      atPath: self.directoryURL.relativePath + "/\(customScalarsDirectory)/\(preSuffixFilename)"))
    .to(beTrue())
  }

  // MARK: Validation Tests

  func test_validation_givenTestMockConfiguration_asSwiftPackage_withSchemaTypesModule_asEmbeddedInTarget_shouldThrow() throws {
    // given
    let config = ApolloCodegenConfiguration.mock(
      input: .init(schemaPath: "path"),
      output: .mock(
        moduleType: .embeddedInTarget(name: "ModuleTarget"),
        testMocks: .swiftPackage(targetName: nil)
      )
    )

    // then
    expect(try ApolloCodegen._validate(config: config))
      .to(throwError(ApolloCodegen.Error.testMocksInvalidSwiftPackageConfiguration))
  }

  func test_validation_givenTestMockConfiguration_asSwiftPackage_withSchemaTypesModule_asOther_shouldThrow() throws {
    // given
    let config = ApolloCodegenConfiguration.mock(
      input: .init(schemaPath: "path"),
      output: .mock(
        moduleType: .other,
        testMocks: .swiftPackage(targetName: nil)
      )
    )

    // then
    expect(try ApolloCodegen._validate(config: config))
      .to(throwError(ApolloCodegen.Error.testMocksInvalidSwiftPackageConfiguration))
  }

  func test_validation_givenTestMockConfiguration_asSwiftPackage_withSchemaTypesModule_asSwiftPackage_shouldNotThrow() throws {
    // given
    let config = ApolloCodegenConfiguration.mock(
      input: .init(schemaPath: "path.graphqls")
    )

    // then
    expect(try ApolloCodegen._validate(config: config))
      .notTo(throwError())
  }

  func test_validation_givenOperationSearchPathWithoutFileExtensionComponent_shouldThrow() throws {
    // given
    let config = ApolloCodegenConfiguration.mock(
      input: .init(schemaPath: "path.graphqls", operationSearchPaths: ["operations/*"])
    )

    // then
    expect(try ApolloCodegen._validate(config: config))
      .to(throwError(ApolloCodegen.Error.inputSearchPathInvalid(path: "operations/*")))
  }

  func test_validation_givenOperationSearchPathEndingInPeriod_shouldThrow() throws {
    // given
    let config = ApolloCodegenConfiguration.mock(
      input: .init(schemaPath: "path.graphqls", operationSearchPaths: ["operations/*."])
    )

    // then
    expect(try ApolloCodegen._validate(config: config))
      .to(throwError(ApolloCodegen.Error.inputSearchPathInvalid(path: "operations/*.")))
  }

  func test_validation_givenSchemaSearchPathWithoutFileExtensionComponent_shouldThrow() throws {
    // given
    let config = ApolloCodegenConfiguration.mock(
      input: .init(schemaSearchPaths: ["schema/*"])
    )

    // then
    expect(try ApolloCodegen._validate(config: config))
      .to(throwError(ApolloCodegen.Error.inputSearchPathInvalid(path: "schema/*")))
  }

  func test_validation_givenSchemaSearchPathEndingInPeriod_shouldThrow() throws {
    // given
    let config = ApolloCodegenConfiguration.mock(
      input: .init(schemaSearchPaths: ["schema/*."])
    )

    // then
    expect(try ApolloCodegen._validate(config: config))
      .to(throwError(ApolloCodegen.Error.inputSearchPathInvalid(path: "schema/*.")))
  }

  let conflictingSchemaNames = ["rocket", "Rocket"]

  func test__validation__givenSchemaName_matchingObjectName_shouldThrow() throws {
    // given
    let object = GraphQLObjectType.mock("Rocket")
    let compilationResult = CompilationResult.mock(referencedTypes: [object])

    // then
    for name in conflictingSchemaNames {
      let configContext = ApolloCodegen.ConfigurationContext(config: .mock(
        schemaNamespace: name
      ), rootURL: nil)

      expect(try configContext.validate(compilationResult))
        .to(throwError(ApolloCodegen.Error.schemaNameConflict(name: configContext.schemaNamespace)))
    }
  }

  func test__validation__givenSchemaName_matchingInterfaceName_shouldThrow() throws {
    // given
    let interface = GraphQLInterfaceType.mock("Rocket")
    let compilationResult = CompilationResult.mock(referencedTypes: [interface])

    // then
    for name in conflictingSchemaNames {
      let configContext = ApolloCodegen.ConfigurationContext(config: .mock(
        schemaNamespace: name
      ), rootURL: nil)

      expect(try configContext.validate(compilationResult))
        .to(throwError(ApolloCodegen.Error.schemaNameConflict(name: configContext.schemaNamespace)))
    }
  }

  func test__validation__givenSchemaName_matchingUnionName_shouldThrow() throws {
    // given
    let union = GraphQLUnionType.mock("Rocket")
    let compilationResult = CompilationResult.mock(referencedTypes: [union])

    // then
    for name in conflictingSchemaNames {
      let configContext = ApolloCodegen.ConfigurationContext(config: .mock(
        schemaNamespace: name
      ), rootURL: nil)

      expect(try configContext.validate(compilationResult))
        .to(throwError(ApolloCodegen.Error.schemaNameConflict(name: configContext.schemaNamespace)))
    }
  }

  func test__validation__givenSchemaName_matchingEnumName_shouldThrow() throws {
    // given
    let `enum` = GraphQLEnumType.mock(name: "Rocket", values: ["one", "two"])
    let compilationResult = CompilationResult.mock(referencedTypes: [`enum`])

    // then
    for name in conflictingSchemaNames {
      let configContext = ApolloCodegen.ConfigurationContext(config: .mock(
        schemaNamespace: name
      ), rootURL: nil)

      expect(try configContext.validate(compilationResult))
        .to(throwError(ApolloCodegen.Error.schemaNameConflict(name: configContext.schemaNamespace)))
    }
  }

  func test__validation__givenSchemaName_matchingInputObjectName_shouldThrow() throws {
    // given
    let inputObject = GraphQLInputObjectType.mock("Rocket")
    let compilationResult = CompilationResult.mock(referencedTypes: [inputObject])

    // then
    for name in conflictingSchemaNames {
      let configContext = ApolloCodegen.ConfigurationContext(config: .mock(
        schemaNamespace: name
      ), rootURL: nil)

      expect(try configContext.validate(compilationResult))
        .to(throwError(ApolloCodegen.Error.schemaNameConflict(name: configContext.schemaNamespace)))
    }
  }

  func test__validation__givenSchemaName_matchingCustomScalarName_shouldThrow() throws {
    // given
    let customScalar = GraphQLScalarType.mock(name: "Rocket")
    let compilationResult = CompilationResult.mock(referencedTypes: [customScalar])

    // then
    for name in conflictingSchemaNames {
      let configContext = ApolloCodegen.ConfigurationContext(config: .mock(
        schemaNamespace: name
      ), rootURL: nil)

      expect(try configContext.validate(compilationResult))
        .to(throwError(ApolloCodegen.Error.schemaNameConflict(name: configContext.schemaNamespace)))
    }
  }

  func test__validation__givenSchemaName_matchingFragmentDefinitionName_shouldThrow() throws {
    // given
    let fragmentDefinition = CompilationResult.FragmentDefinition.mock(
      "Rocket",
      type: .mock("MockType"))
    let compilationResult = CompilationResult.mock(fragments: [fragmentDefinition])

    // then
    for name in conflictingSchemaNames {
      let configContext = ApolloCodegen.ConfigurationContext(config: .mock(
        schemaNamespace: name
      ), rootURL: nil)

      expect(try configContext.validate(compilationResult))
        .to(throwError(ApolloCodegen.Error.schemaNameConflict(name: configContext.schemaNamespace)))
    }
  }

  func test__validation__givenSchemaName_matchingDisallowedSchemaNamespaceName_shouldThrow() throws {
    // given
    let disallowedNames = ["schema", "Schema", "ApolloAPI", "apolloapi"]

    // when
    for name in disallowedNames {
      let config = ApolloCodegenConfiguration.mock(schemaNamespace: name)

      // then
      expect(try ApolloCodegen._validate(config: config))
        .to(throwError(ApolloCodegen.Error.schemaNameConflict(name: config.schemaNamespace)))
    }
  }

  func test__validation__givenTargetName_matchingDisallowedTargetName_shouldThrow() throws {
    // given
    let disallowedNames = ["apollo", "Apollo", "apolloapi", "ApolloAPI"]

    // when
    for name in disallowedNames {
      let config = ApolloCodegenConfiguration.mock(
        output: .mock(
          moduleType: .embeddedInTarget(name: name)
        )
      )

      // then
      expect(try ApolloCodegen._validate(config: config))
        .to(throwError(ApolloCodegen.Error.targetNameConflict(name: name)))
    }
  }

  func test__validation__givenEmptySchemaName_shouldThrow() throws {
    let config = ApolloCodegenConfiguration.mock(schemaNamespace: "")

    // then
    expect(try ApolloCodegen._validate(config: config))
      .to(throwError(ApolloCodegen.Error.invalidSchemaName("", message: "")))
  }

  func test__validation__givenWhitespaceOnlySchemaName_shouldThrow() throws {
    let config = ApolloCodegenConfiguration.mock(schemaNamespace: " ")

    // then
    expect(try ApolloCodegen._validate(config: config))
      .to(throwError(ApolloCodegen.Error.invalidSchemaName(" ", message: "")))
  }

  func test__validation__givenSchemaNameContainingWhitespace_shouldThrow() throws {
    let config = ApolloCodegenConfiguration.mock(schemaNamespace: "My Schema")

    // then
    expect(try ApolloCodegen._validate(config: config))
      .to(throwError(ApolloCodegen.Error.invalidSchemaName("My Schema", message: "")))
  }

  func test__validation__givenUniqueSchemaName_shouldNotThrow() throws {
    // given
    let object = GraphQLObjectType.mock("MockObject")
    let interface = GraphQLInterfaceType.mock("MockInterface")
    let union = GraphQLUnionType.mock("MockUnion")
    let `enum` = GraphQLEnumType.mock(name: "MockEnum", values: ["one", "two"])
    let inputObject = GraphQLInputObjectType.mock("MockInputObject")
    let customScalar = GraphQLScalarType.mock(name: "MockCustomScalar")
    let fragmentDefinition = CompilationResult.FragmentDefinition.mock(
      "MockFragmentDefinition",
      type: .mock("MockType"))

    let compilationResult = CompilationResult.mock(
      referencedTypes: [
        object,
        interface,
        union,
        `enum`,
        inputObject,
        customScalar
      ],
      fragments: [fragmentDefinition]
    )

    // then
    let configContext = ApolloCodegen.ConfigurationContext(config: .mock(
      schemaNamespace: "MySchema"
    ), rootURL: nil)

    expect(try configContext.validate(compilationResult)).notTo(throwError())
  }

  func test__validation__givenSchemaTypesModule_swiftPackageManager_withCocoapodsCompatibleImportStatements_true_shouldThrow() throws {
    // given
    let config = ApolloCodegenConfiguration.mock(
      .swiftPackage(),
      options: .init(cocoapodsCompatibleImportStatements: true)
    )

    // then
    expect(try ApolloCodegen._validate(config: config))
      .to(throwError(ApolloCodegen.Error.invalidConfiguration(message: """
        cocoapodsCompatibleImportStatements cannot be set to 'true' when the output schema types \
        module type is Swift Package Manager. Change the cocoapodsCompatibleImportStatements \
        value to 'false' to resolve the conflict.
        """)))
  }

  func test__validation__givenSchemaTypesModule_swiftPackageManager_withCocoapodsCompatibleImportStatements_false_shouldNotThrow() throws {
    // given
    let config = ApolloCodegenConfiguration.mock(
      .swiftPackage(),
      options: .init(cocoapodsCompatibleImportStatements: false)
    )

    // then
    expect(try ApolloCodegen._validate(config: config)).notTo(throwError())
  }

  func test__validation__givenSchemaTypesModule_embeddedInTarget_withCocoapodsCompatibleImportStatements_true_shouldNotThrow() throws {
    // given
    let config = ApolloCodegenConfiguration.mock(
      .embeddedInTarget(name: "TestTarget"),
      options: .init(cocoapodsCompatibleImportStatements: true)
    )

    // then
    expect(try ApolloCodegen._validate(config: config)).notTo(throwError())
  }

  func test__validation__givenSchemaTypesModule_other_withCocoapodsCompatibleImportStatements_true_shouldNotThrow() throws {
    // given
    let config = ApolloCodegenConfiguration.mock(
      .other,
      options: .init(cocoapodsCompatibleImportStatements: true)
    )

    // then
    expect(try ApolloCodegen._validate(config: config)).notTo(throwError())
  }

  func test__validation__selectionSet_typeConflicts_shouldThrowError() async throws {
    let schemaDefData: Data = {
      """
      type Query {
        user: User
      }

      type User {
        containers: [Container]
      }

      type Container {
        value: Value
        values: [Value]
      }

      type Value {
        propertyA: String!
        propertyB: String!
        propertyC: String!
        propertyD: String!
      }
      """
    }().data(using: .utf8)!

    let operationData: Data =
      """
      query ConflictingQuery {
          user {
              containers {
                  value {
                      propertyA
                      propertyB
                      propertyC
                      propertyD
                  }

                  values {
                      propertyA
                      propertyC
                  }
              }
          }
      }
      """.data(using: .utf8)!

    try createFile(containing: schemaDefData, named: "schema.graphqls")
    try createFile(containing: operationData, named: "operation.graphql")

    let config = ApolloCodegenConfiguration.mock(
      input: .init(
        schemaSearchPaths: ["schema*.graphqls"],
        operationSearchPaths: ["*.graphql"]
      ),
      output: .init(
        schemaTypes: .init(path: "SchemaModule",
                           moduleType: .swiftPackage()),
        operations: .inSchemaModule
      )
    )

    await expect {
      try await ApolloCodegen.build(with: config, withRootURL: self.directoryURL)
    }
    .to(throwError { error in
      guard let error = error as? ApolloCodegen.NonFatalErrors else {
        fail("Expected NonFatalErrors, got .\(error)")
        return
      }
      expect(error.errorsByFile.count).to(equal(1))

      guard let conflictingQueryErrors = error.errorsByFile["ConflictingQuery"],
            case let .typeNameConflict(name, conflictingName, containingObject) = conflictingQueryErrors.first else {
        fail("Expected .typeNameConflict, got .\(error)")
        return
      }

      expect(conflictingQueryErrors.count).to(equal(1))
      expect(name).to(equal("value"))
      expect(conflictingName).to(equal("values"))
      expect(containingObject).to(equal("ConflictingQuery.Data.User.Container"))
    })
  }

  func test__validation__givenFieldMerging_notAll_andSelectionSetInitializers_enabled_shouldThrowError() throws {
    // given
    let fieldMergingOptions: [ApolloCodegenConfiguration.FieldMerging] = [
      .none,
      .ancestors,
      .namedFragments,
      .siblings,
      [.ancestors, .namedFragments],
      [.siblings, .ancestors],
      [.siblings, .namedFragments]
    ]
    let initializerOptions: [ApolloCodegenConfiguration.SelectionSetInitializers] = [
      .all,      
      .operations,
      .namedFragments,
      .fragment(named: "TestFragment"),
      [.operations, .namedFragments]
    ]

    for fieldMergingOption in fieldMergingOptions {
      for initializerOption in initializerOptions {

        let config = ApolloCodegenConfiguration.mock(
          .other,
          options: .init(
            selectionSetInitializers: initializerOption
          ),
          experimentalFeatures: .init(
            fieldMerging: fieldMergingOption
          )
        )

        // then
        expect(try ApolloCodegen._validate(config: config))
          .to(throwError(ApolloCodegen.Error.fieldMergingIncompatibility))
      }
    }
  }

  // MARK: Path Match Exclusion Tests

  func test__match__givenFilesInSpecialExcludedPaths_shouldNotReturnExcludedPaths() throws {
    // given
    try createFile(filename: "included.file")

    try createFile(filename: "excludedBuildFolder.file", inDirectory: ".build")
    try createFile(filename: "excludedBuildSubfolderOne.file", inDirectory: ".build/subfolder")
    try createFile(filename: "excludedBuildSubfolderTwo.file", inDirectory: ".build/subfolder/two")
    try createFile(filename: "excludedNestedOneBuildFolder.file", inDirectory: "nested/.build")
    try createFile(filename: "excludedNestedTwoBuildFolder.file", inDirectory: "nested/two/.build")

    try createFile(filename: "excludedSwiftpmFolder.file", inDirectory: ".swiftpm")
    try createFile(filename: "excludedSwiftpmSubfolderOne.file", inDirectory: ".swiftpm/subfolder")
    try createFile(filename: "excludedSwiftpmSubfolderTwo.file", inDirectory: ".swiftpm/subfolder/two")
    try createFile(filename: "excludedNestedOneSwiftpmFolder.file", inDirectory: "nested/.swiftpm")
    try createFile(filename: "excludedNestedTwoSwiftpmFolder.file", inDirectory: "nested/two/.swiftpm")

    try createFile(filename: "excludedPodsFolder.file", inDirectory: ".Pods")
    try createFile(filename: "excludedPodsSubfolderOne.file", inDirectory: ".Pods/subfolder")
    try createFile(filename: "excludedPodsSubfolderTwo.file", inDirectory: ".Pods/subfolder/two")
    try createFile(filename: "excludedNestedOnePodsFolder.file", inDirectory: "nested/.Pods")
    try createFile(filename: "excludedNestedTwoPodsFolder.file", inDirectory: "nested/two/.Pods")

    // when
    let matches = try ApolloCodegen.match(
      searchPaths: ["\(directoryURL.path)/**/*.file"],
      relativeTo: nil)

    // then
    expect(matches.count).to(equal(1))
    expect(matches.contains(where: { $0.contains(".build") })).to(beFalse())
    expect(matches.contains(where: { $0.contains(".swiftpm") })).to(beFalse())
    expect(matches.contains(where: { $0.contains(".Pods") })).to(beFalse())
  }

  func test__match__givenFilesInSpecialExcludedPaths_usingRelativeDirectory_shouldNotReturnExcludedPaths() throws {
    // given
    try createFile(filename: "included.file")

    try createFile(filename: "excludedBuildFolder.file", inDirectory: ".build")
    try createFile(filename: "excludedBuildSubfolderOne.file", inDirectory: ".build/subfolder")
    try createFile(filename: "excludedBuildSubfolderTwo.file", inDirectory: ".build/subfolder/two")
    try createFile(filename: "excludedNestedOneBuildFolder.file", inDirectory: "nested/.build")
    try createFile(filename: "excludedNestedTwoBuildFolder.file", inDirectory: "nested/two/.build")

    try createFile(filename: "excludedSwiftpmFolder.file", inDirectory: ".swiftpm")
    try createFile(filename: "excludedSwiftpmSubfolderOne.file", inDirectory: ".swiftpm/subfolder")
    try createFile(filename: "excludedSwiftpmSubfolderTwo.file", inDirectory: ".swiftpm/subfolder/two")
    try createFile(filename: "excludedNestedOneSwiftpmFolder.file", inDirectory: "nested/.swiftpm")
    try createFile(filename: "excludedNestedTwoSwiftpmFolder.file", inDirectory: "nested/two/.swiftpm")

    try createFile(filename: "excludedPodsFolder.file", inDirectory: ".Pods")
    try createFile(filename: "excludedPodsSubfolderOne.file", inDirectory: ".Pods/subfolder")
    try createFile(filename: "excludedPodsSubfolderTwo.file", inDirectory: ".Pods/subfolder/two")
    try createFile(filename: "excludedNestedOnePodsFolder.file", inDirectory: "nested/.Pods")
    try createFile(filename: "excludedNestedTwoPodsFolder.file", inDirectory: "nested/two/.Pods")

    // when
    let matches = try ApolloCodegen.match(
      searchPaths: ["**/*.file"],
      relativeTo: directoryURL)

    // then
    expect(matches.count).to(equal(1))
    expect(matches.contains(where: { $0.contains(".build") })).to(beFalse())
    expect(matches.contains(where: { $0.contains(".swiftpm") })).to(beFalse())
    expect(matches.contains(where: { $0.contains(".Pods") })).to(beFalse())
  }
  
  // MARK: - Schema Customization Tests
  
  func test_typeNames_givenSchemaCustomization_shouldGenerateCustomTypeNames() async throws {
    // given
    let schemaPath = ApolloCodegenInternalTestHelpers.Resources.AnimalKingdom.Schema.path
    let operationsPath = ApolloCodegenInternalTestHelpers.Resources.url
      .appendingPathComponent("animalkingdom-graphql")
      .appendingPathComponent("**/*.graphql").path

    let config =  ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration(
      schemaNamespace: "AnimalKingdomAPI",
      input: .init(schemaPath: schemaPath, operationSearchPaths: [operationsPath]),
      output: .init(
        schemaTypes: .init(path: directoryURL.path,
                           moduleType: .swiftPackage()),
        operations: .inSchemaModule
      ),
      options: .init(
        schemaCustomization: .init(
                  customTypeNames: [
                    "Crocodile": .type(name: "CustomCrocodile"), // Object
                    "Animal": .type(name: "CustomAnimal"), // Interface
                    "ClassroomPet": .type(name: "CustomClassroomPet"), // Union
                    "Date": .type(name: "CustomDate"), // Custom Scalar
                    "SkinCovering": .enum( // Enum
                      name: "CustomSkinCovering",
                      cases: [
                        "HAIR": "CUSTOMHAIR"
                      ]
                    ),
                    "PetSearchFilters": .inputObject( // Input Object
                      name: "CustomPetSearchFilters",
                      fields: [
                        "size": "customSize"
                      ]
                    )
                  ]
                )
      )
    ), rootURL: nil)

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    // when
    let compilationResult = try await subject.compileGraphQLResult()

    let ir = IRBuilder(compilationResult: compilationResult)
    
    subject.processSchemaCustomizations(ir: ir)
    
    for objType in ir.schema.referencedTypes.objects {
      if objType.name.schemaName == "Crocodile" {
        expect(objType.name.customName).to(equal("CustomCrocodile"))
        break
      }
    }
    
    for interfaceType in ir.schema.referencedTypes.interfaces {
      if interfaceType.name.schemaName == "Animal" {
        expect(interfaceType.name.customName).to(equal("CustomAnimal"))
        break
      }
    }
    
    for unionType in ir.schema.referencedTypes.unions {
      if unionType.name.schemaName == "ClassroomPet" {
        expect(unionType.name.customName).to(equal("CustomClassroomPet"))
        break
      }
    }
    
    for customScalarType in ir.schema.referencedTypes.customScalars {
      if customScalarType.name.schemaName == "Date" {
        expect(customScalarType.name.customName).to(equal("CustomDate"))
        break
      }
    }

    for enumType in ir.schema.referencedTypes.enums {
      if enumType.name.schemaName == "SkinCovering" {
        expect(enumType.name.customName).to(equal("CustomSkinCovering"))
        
        for enumCase in enumType.values {
          if enumCase.name.schemaName == "HAIR" {
            expect(enumCase.name.customName).to(equal("CUSTOMHAIR"))
          }
        }
        
        break
      }
    }
    
    for inputObjectType in ir.schema.referencedTypes.inputObjects {
      if inputObjectType.name.schemaName == "PetSearchFilters" {
        expect(inputObjectType.name.customName).to(equal("CustomPetSearchFilters"))
        
        for inputField in inputObjectType.fields.values {
          if inputField.name.schemaName == "size" {
            expect(inputField.name.customName).to(equal("customSize"))
          }
        }
        
        break
      }
    }

  }

  // MARK: - Local Cache Mutation + Field Merging Integration Tests
  //
  // These are integration tests because the codegen test wrapper infrastructure does not support overriding config
  // values during the test.

  func test__fileRendering__givenLocalCacheMutationQuery_whenSelectionSetInitializersEmpty_andFileMergingNone_shouldGenerateFullSelectionSetInitializers() async throws {
    // given
    try createFile(
      body: """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String
      }
      """,
      filename: "schema.graphqls"
    )

    try createFile(
      body: """
      query TestOperation @apollo_client_ios_localCacheMutation {
        allAnimals {
          species
        }
      }
      """,
      filename: "operation.graphql"
    )

    let fileManager = MockApolloFileManager(strict: false)
    let expectation = expectation(description: "Received local cache mutation file data.")

    fileManager.mock(closure: .createFile({ path, data, attributes in
      if path.hasSuffix("TestOperationLocalCacheMutation.graphql.swift") {
        expect(data?.asString).to(equalLineByLine("""
                init(
                  allAnimals: [AllAnimal]? = nil
                ) {
          """, atLine: 26, ignoringExtraLines: true))

        expectation.fulfill()
      }

      return true
    }))

    // when
    let config = ApolloCodegen.ConfigurationContext(
      config: ApolloCodegenConfiguration.mock(
        input: .init(
          schemaSearchPaths: [directoryURL.appendingPathComponent("schema.graphqls").path],
          operationSearchPaths: [directoryURL.appendingPathComponent("operation.graphql").path]
        ),
        // Apollo codegen should override the next two value to force the generation of selection set initializers
        // and perform all file merging for the local cache mutation.
        options: .init(selectionSetInitializers: []),
        experimentalFeatures: .init(fieldMerging: .none)
      ),
      rootURL: nil
    )

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let compilationResult = try await subject.compileGraphQLResult()
    let ir = IRBuilder(compilationResult: compilationResult)

    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )

    // then
    expect(fileManager.allClosuresCalled).to(beTrue())

    await fulfillment(of: [expectation], timeout: 1)
  }

  func test__fileRendering__givenLocalCacheMutationFragment_whenSelectionSetInitializersEmpty_andFileMergingNone_shouldGenerateFullSelectionSetInitializers() async throws {
    // given
    try createFile(
      body: """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String
      }
      """,
      filename: "schema.graphqls"
    )

    try createFile(
      body: """
      query TestOperation {
        allAnimals {
          ...PredatorFragment
        }
      }
      
      fragment PredatorFragment on Animal @apollo_client_ios_localCacheMutation {
        species
      }
      """,
      filename: "operation.graphql"
    )

    let fileManager = MockApolloFileManager(strict: false)
    let expectation = expectation(description: "Received local cache mutation file data.")

    fileManager.mock(closure: .createFile({ path, data, attributes in
      if path.hasSuffix("PredatorFragment.graphql.swift") {
        expect(data?.asString).to(equalLineByLine("""
              init(
                __typename: String,
                species: String? = nil
              ) {
          """, atLine: 26, ignoringExtraLines: true))

        expectation.fulfill()
      }

      return true
    }))

    // when
    let config = ApolloCodegen.ConfigurationContext(
      config: ApolloCodegenConfiguration.mock(
        input: .init(
          schemaSearchPaths: [directoryURL.appendingPathComponent("schema.graphqls").path],
          operationSearchPaths: [directoryURL.appendingPathComponent("operation.graphql").path]
        ),
        // Apollo codegen should override the next two value to force the generation of selection set initializers
        // and perform all file merging for the local cache mutation.
        options: .init(selectionSetInitializers: []),
        experimentalFeatures: .init(fieldMerging: .none)
      ),
      rootURL: nil
    )

    let subject = ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )

    let compilationResult = try await subject.compileGraphQLResult()
    let ir = IRBuilder(compilationResult: compilationResult)

    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )

    // then
    expect(fileManager.allClosuresCalled).to(beTrue())

    await fulfillment(of: [expectation], timeout: 1)
  }

}
