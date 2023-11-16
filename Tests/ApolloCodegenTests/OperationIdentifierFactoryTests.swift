import Foundation
import XCTest
import Nimble
import OrderedCollections
import GraphQLCompiler
@testable import IR
import Utilities
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class OperationIdentifierFactoryTests: XCTestCase {
  var schemaSDL: String!
  var document: String!
  var ir: IRBuilder!
  var operation: CompilationResult.OperationDefinition!
  var subject: OperationIdentifierFactory!

  override func setUp() {
    super.setUp()
    subject = OperationIdentifierFactory()
  }

  override func tearDown() {
    subject = nil
    schemaSDL = nil
    document = nil
    operation = nil
    ir = nil
    super.tearDown()
  }

  // MARK: - Helpers

  func getOperation(
    named operationName: String? = nil,
    fromJSONSchema json: Bool = false
  ) async throws {
    ir = json ?
    try await .mock(schemaJSON: schemaSDL, document: document) :
    try await .mock(schema: schemaSDL, document: document)

    if let operationName = operationName {
      operation = try XCTUnwrap(ir.compilationResult.operations.first {$0.name == operationName})
    } else {
      operation = try XCTUnwrap(ir.compilationResult.operations.first)
    }
  }

  // MARK: - Default Operation Identifier Computation Tests

  func test__identifierForOperation__givenOperationWithNoFragments__hasCorrectOperationIdentifier() async throws {
    // given
    document = try String(
      contentsOf: ApolloCodegenInternalTestHelpers.Resources.StarWars.GraphQLOperation(named: "HeroAndFriendsNames")
    )

    schemaSDL = try String(
      contentsOf: ApolloCodegenInternalTestHelpers.Resources.StarWars.JSONSchema)

    let expected = "1e36c3331171b74c012b86caa04fbb01062f37c61227655d9c0729a62c6f7285"
    try await getOperation(named: "HeroAndFriendsNames", fromJSONSchema: true)

    // when
    let actual = try await subject.identifier(for: operation)

    // then
    expect(actual).to(equal(expected))
  }

  func test__identifierForOperation__givenOperationWithFragment__hasCorrectOperationIdentifier() async throws {
    // given
    document = try String(
      contentsOf: ApolloCodegenInternalTestHelpers.Resources.StarWars.GraphQLOperation(named: "HeroAndFriendsNamesWithFragment")
    ) + "\n" + String(
      contentsOf: ApolloCodegenInternalTestHelpers.Resources.StarWars.GraphQLOperation(named: "HeroName")
    )

    schemaSDL = try String(
      contentsOf: ApolloCodegenInternalTestHelpers.Resources.StarWars.JSONSchema)

    let expected = "599cd7d91ede7a5508cdb26b424e3b8e99e6c2c5575b799f6090695289ff8e99"
    try await getOperation(named: "HeroAndFriendsNamesWithFragment", fromJSONSchema: true)

    // when
    let actual = try await subject.identifier(for: operation)

    // then
    expect(actual).to(equal(expected))
  }

}
