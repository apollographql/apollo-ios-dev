import XCTest
import Nimble
import ApolloCodegenInternalTestHelpers
@testable import ApolloCodegenLib
import IR

class OperationFileGeneratorTests: XCTestCase {
  var irOperation: IR.Operation!
  var subject: OperationFileGenerator!
  var operationDocument: String!

  override func setUp() {
    super.setUp()

    operationDocument = """
    query AllAnimals {
      animals {
        species
      }
    }
    """
  }

  override func tearDown() {
    subject = nil
    irOperation = nil
    operationDocument = nil
    super.tearDown()
  }

  // MARK: Test Helpers

  private func buildSubject() async throws {
    let schemaSDL = """
    type Animal {
      species: String
    }

    type Query {
      animals: [Animal]
    }
    """

    let ir = try await IRBuilder.mock(schema: schemaSDL, document: operationDocument)
    irOperation = await ir.build(operation: ir.compilationResult.operations[0])

    let config = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock())
    
    subject = OperationFileGenerator(irOperation: irOperation, operationIdentifier: nil, patternMatchedOutputOptions: nil, config: config)
  }

  // MARK: Property Tests

  func test__properties__shouldReturnTargetType_operation() async throws {
    // given
    try await buildSubject()

    let expected: FileTarget = .operation(irOperation.definition)

    // then
    expect(self.subject.target).to(equal(expected))
  }

  func test__properties__givenIrOperation_shouldReturnFileName_matchingOperationDefinitionName() async throws {
    // given
    try await buildSubject()

    // then
    expect(self.subject.fileName).to(equal("AllAnimalsQuery"))
  }

  func test__properties__givenIrOperation_shouldOverwrite() async throws {
    // given
    try await buildSubject()

    // then
    expect(self.subject.overwrite).to(beTrue())
  }

  func test__template__givenNotLocalCacheMutationOperation_shouldBeOperationTemplate() async throws {
    // given
    operationDocument = """
    query AllAnimals {
      animals {
        species
      }
    }
    """

    // when
    try await buildSubject()

    // then
    expect(self.subject.template).to(beAKindOf(OperationDefinitionTemplate.self))
  }

  func test__template__givenLocalCacheMutationOperation_shouldBeLocalCacheMutationOperationTemplate() async throws {
    // given
    operationDocument = """
    query AllAnimals @apollo_client_ios_localCacheMutation {
      animals {
        species
      }
    }
    """

    // when
    try await buildSubject()

    // then
    expect(self.subject.template).to(beAKindOf(LocalCacheMutationDefinitionTemplate.self))
  }
}
