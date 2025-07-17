import XCTest
import ApolloCodegenInternalTestHelpers
import ApolloInternalTestHelpers
@testable import ApolloCodegenLib
import Nimble
import IR

final class ApolloCodegenConfiguration_ReduceGeneratedSchemaTypesTests: XCTestCase {
  private var directoryURL: URL { testFileManager.directoryURL }
  private var testFileManager: TestIsolatedFileManager!
  
  override func setUp() async throws {
    try await super.setUp()
    testFileManager = try testIsolatedFileManager()
    try await createMockSchema()
  }

  override func tearDown() async throws {
    testFileManager = nil
    try await super.tearDown()
  }
  
  private func createSubject(
    reduceGeneratedSchemaTypes: Bool = true
  ) -> ApolloCodegen {
    let config = ApolloCodegen.ConfigurationContext(
      config: ApolloCodegenConfiguration.mock(
        schemaNamespace: "AnimalKingdomAPI",
        input: .init(
          schemaPath: directoryURL.appendingPathComponent("**/*.graphqls").path,
          operationSearchPaths: [directoryURL.appendingPathComponent("**/*.graphql").path]
        ),
        output: .mock(
          moduleType: .swiftPackageManager,
          path: directoryURL.path
        ),
        options: .init(
          reduceGeneratedSchemaTypes: reduceGeneratedSchemaTypes
        )
      )
    )
    
    return ApolloCodegen(
      config: config,
      operationIdentifierFactory: OperationIdentifierFactory(),
      itemsToGenerate: .code
    )
  }
  
  // MARK: Mock File Setup
  
  private func createMockSchema() async throws {
    try await createFile(
      body: """
      type Query {
        allAnimals: [Animal]!
        allPetFood: [PetFood]!
        allPetBeds: [PetBed]!
      }
      
      interface Animal @typePolicy(keyFields: "id") {
        id: ID!
        species: String!
        name: String!
      }
      
      type Cat implements Animal {
        id: ID!
        species: String!
        name: String!
        ownerName: String!
      }
      
      type Dog implements Animal {
        id: ID!
        species: String!
        name: String!
        favoriteToy: String!
      }
      
      type Bird implements Animal {
        id: ID!
        species: String!
        name: String!
        laysEggs: Boolean!
      }
      
      interface PetFood {
        id: ID!
        name: String!
      }
      
      type CatFood implements PetFood @typePolicy(keyFields: "id") {
        id: ID!
        name: String!
        isDryFood: Boolean!
      }
      
      type DogFood implements PetFood @typePolicy(keyFields: "id") {
        id: ID!
        name: String!
        hasProtein: Boolean!
      }
      
      type BirdFood implements PetFood {
        id: ID!
        name: String!
        seedType: String!
      }
      
      interface PetBed {
        id: ID!
        name: String!
      }
      
      type CatBed implements PetBed {
        id: ID!
        name: String!
        type: String!
      }
      
      type DogBed implements PetBed {
        id: ID!
        name: String!
        material: String!
      }
      
      type BirdCage implements PetBed {
        id: ID!
        name: String!
        size: String!
      }
      """,
      filename: "schema.graphqls"
    )
  }
      
  @discardableResult
  private func createFile(
    body: @Sendable @autoclosure () -> String = "Test File",
    filename: String,
    inDirectory directory: String? = nil
  ) async throws -> String {
    return try await self.testFileManager.createFile(
      body: body(),
      named: filename,
      inDirectory: directory
    )
  }
  
  // MARK: - Tests
  
  func test_givenSchemaAndOperationDocuments_andInterfaceWithTypePolicy_reducingGeneratedSchemaTypes_generatesOnlyReferencedObjects() async throws {
    try await createFile(
      body: """
      query AllAnimalsQuery {
        allAnimals {
          id
          species
          name
          ... on Cat {
            ownerName
          }
        }
      }
      """,
      filename: "AllAnimalQuery.graphql"
    )
    
    let subject = createSubject()
    
    let fileManager = await MockApolloFileManager(strict: false)

    await fileManager.mock(closure: .createFile({ path, data, attributes in
      return true
    }))
    
    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("Package.swift").path,
      directoryURL.appendingPathComponent("AllAnimalsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/CustomScalars/ID.swift").path,
      directoryURL.appendingPathComponent("Sources/Interfaces/Animal.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Cat.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Query.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaConfiguration.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaMetadata.graphql.swift").path
    ]
    
    let compilationResult = try await subject.compileGraphQLResult()
    let ir = IRBuilder(compilationResult: compilationResult)
    
    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )

    let filePaths = await fileManager.writtenFiles

    expect(filePaths).to(equal(expectedPaths))
    await expect { await fileManager.allClosuresCalled }.to(beTrue())
  }
  
  func test_givenSchemaAndOperationDocuments_andInterfaceWithTypePolicy_generatesAllInterfaceObjects() async throws {
    try await createFile(
      body: """
      query AllAnimalsQuery {
        allAnimals {
          id
          species
          name
          ... on Cat {
            ownerName
          }
        }
      }
      """,
      filename: "AllAnimalQuery.graphql"
    )
    
    let subject = createSubject(reduceGeneratedSchemaTypes: false)
    
    let fileManager = await MockApolloFileManager(strict: false)

    await fileManager.mock(closure: .createFile({ path, data, attributes in
      return true
    }))
    
    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("Package.swift").path,
      directoryURL.appendingPathComponent("AllAnimalsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/CustomScalars/ID.swift").path,
      directoryURL.appendingPathComponent("Sources/Interfaces/Animal.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Bird.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Cat.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Dog.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Query.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaConfiguration.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaMetadata.graphql.swift").path
    ]
    
    let compilationResult = try await subject.compileGraphQLResult()
    let ir = IRBuilder(compilationResult: compilationResult)
    
    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )    
    let filePaths = await fileManager.writtenFiles

    expect(filePaths).to(equal(expectedPaths))
    await expect { await fileManager.allClosuresCalled }.to(beTrue())
  }
  
  func test_givenSchemaAndOperationDocuments_andTypesWithTypePolicy_reducingGeneratedSchemaTypes_generatesOnlyReferencedAndTypePolicyObjects() async throws {
    try await createFile(
      body: """
      query AllPetFoodQuery {
        allPetFood {
          id
          name
          ... on CatFood {
            isDryFood
          }
        }
      }
      """,
      filename: "AllPetFoodQuery.graphql"
    )
    
    let subject = createSubject()
    
    let fileManager = await MockApolloFileManager(strict: false)

    await fileManager.mock(closure: .createFile({ path, data, attributes in
      return true
    }))
    
    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("Package.swift").path,
      directoryURL.appendingPathComponent("AllPetFoodQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/CustomScalars/ID.swift").path,
      directoryURL.appendingPathComponent("Sources/Interfaces/PetFood.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/CatFood.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/DogFood.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Query.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaConfiguration.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaMetadata.graphql.swift").path
    ]
    
    let compilationResult = try await subject.compileGraphQLResult()
    let ir = IRBuilder(compilationResult: compilationResult)
    
    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )
    let filePaths = await fileManager.writtenFiles

    expect(filePaths).to(equal(expectedPaths))
    await expect { await fileManager.allClosuresCalled }.to(beTrue())
  }
  
  func test_givenSchemaAndOperationDocuments_andTypesWithTypePolicy_generatesInterfaceAndTypePolicyObjects() async throws {
    try await createFile(
      body: """
      query AllPetFoodQuery {
        allPetFood {
          id
          name
          ... on CatFood {
            isDryFood
          }
        }
      }
      """,
      filename: "AllPetFoodQuery.graphql"
    )
    
    let subject = createSubject(reduceGeneratedSchemaTypes: false)
    
    let fileManager = await MockApolloFileManager(strict: false)

    await fileManager.mock(closure: .createFile({ path, data, attributes in
      return true
    }))
    
    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("Package.swift").path,
      directoryURL.appendingPathComponent("AllPetFoodQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/CustomScalars/ID.swift").path,
      directoryURL.appendingPathComponent("Sources/Interfaces/PetFood.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/BirdFood.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/CatFood.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/DogFood.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Query.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaConfiguration.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaMetadata.graphql.swift").path
    ]
    
    let compilationResult = try await subject.compileGraphQLResult()
    let ir = IRBuilder(compilationResult: compilationResult)
    
    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )
    let filePaths = await fileManager.writtenFiles

    expect(filePaths).to(equal(expectedPaths))
    await expect { await fileManager.allClosuresCalled }.to(beTrue())
  }
  
  func test_givenSchemaAndOperationDocuments_andInterface_reducingGeneratedSchemaTypes_generatesOnlyReferencedObjects() async throws {
    try await createFile(
      body: """
      query AllPetBedsQuery {
        allPetBeds {
          id
          name
          ... on CatBed {
            type
          }
        }
      }
      """,
      filename: "AllPetBedsQuery.graphql"
    )
    
    let subject = createSubject()
    
    let fileManager = await MockApolloFileManager(strict: false)

    await fileManager.mock(closure: .createFile({ path, data, attributes in
      return true
    }))
    
    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("Package.swift").path,
      directoryURL.appendingPathComponent("AllPetBedsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/CustomScalars/ID.swift").path,
      directoryURL.appendingPathComponent("Sources/Interfaces/PetBed.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/CatBed.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Query.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaConfiguration.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaMetadata.graphql.swift").path
    ]
    
    let compilationResult = try await subject.compileGraphQLResult()
    let ir = IRBuilder(compilationResult: compilationResult)
    
    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )
    let filePaths = await fileManager.writtenFiles

    expect(filePaths).to(equal(expectedPaths))
    await expect { await fileManager.allClosuresCalled }.to(beTrue())
  }

  func test_givenSchemaAndOperationDocuments_andInterface_generatesAllInterfaceObjects() async throws {
    try await createFile(
      body: """
      query AllPetBedsQuery {
        allPetBeds {
          id
          name
          ... on CatBed {
            type
          }
        }
      }
      """,
      filename: "AllPetBedsQuery.graphql"
    )
    
    let subject = createSubject(reduceGeneratedSchemaTypes: false)
    
    let fileManager = await MockApolloFileManager(strict: false)

    await fileManager.mock(closure: .createFile({ path, data, attributes in
      return true
    }))
    
    let expectedPaths: Set<String> = [
      directoryURL.appendingPathComponent("Package.swift").path,
      directoryURL.appendingPathComponent("AllPetBedsQuery.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/CustomScalars/ID.swift").path,
      directoryURL.appendingPathComponent("Sources/Interfaces/PetBed.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/BirdCage.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/CatBed.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/DogBed.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/Objects/Query.graphql.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaConfiguration.swift").path,
      directoryURL.appendingPathComponent("Sources/SchemaMetadata.graphql.swift").path
    ]
    
    let compilationResult = try await subject.compileGraphQLResult()
    let ir = IRBuilder(compilationResult: compilationResult)
    
    try await subject.generateFiles(
      compilationResult: compilationResult,
      ir: ir,
      fileManager: fileManager
    )
    let filePaths = await fileManager.writtenFiles

    expect(filePaths).to(equal(expectedPaths))
    await expect { await fileManager.allClosuresCalled }.to(beTrue())
  }
  
}
