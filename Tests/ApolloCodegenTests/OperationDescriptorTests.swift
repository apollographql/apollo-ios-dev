import Foundation
import XCTest
import Nimble
import OrderedCollections
import GraphQLCompiler
@testable import IR
import Utilities
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class OperationDescriptorTests: XCTestCase {
  var schemaSDL: String!
  var document: String!
  var ir: IRBuilder!
  var subject: OperationDescriptor!

  override func setUp() {
    super.setUp()
  }

  override func tearDown() {
    subject = nil
    schemaSDL = nil
    document = nil
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

    var operation: CompilationResult.OperationDefinition
    if let operationName = operationName {
      operation = try XCTUnwrap(ir.compilationResult.operations.first {$0.name == operationName})
    } else {
      operation = try XCTUnwrap(ir.compilationResult.operations.first)
    }

    subject = OperationDescriptor(operation)
  }

  // MARK: - Tests

  @available(macOS 13.0, *)
  func test__rawSourceText__givenOperationWithDeeplyNestedFragmentsNotInAlphabeticalOrder__hasReferencedFragmentsInSameOrderAsBuiltOperation() async throws {
    // given
    schemaSDL = """
    type Query {
      name: String!
    }
    """

    document =
    """
    query NameQuery {
      ...Fragment4
      ...Fragment1
    }

    fragment Fragment4 on Query {
      name
      ...Fragment3
    }

    fragment Fragment3 on Query {
      name
      ...Fragment2
    }

    fragment Fragment2 on Query {
      name
    }

    fragment Fragment1 on Query {
      name
      ...Fragment5
    }

    fragment Fragment5 on Query {
      name
    }
    """

    try await getOperation(named: "NameQuery")

    // when
    let operationDescriptorReferencedFragments = subject.rawSourceText
      .matches(of: /fragment (\S*)\s/)
      .map(\.output.1.description)

    let operation = await ir.build(operation: subject.underlyingDefinition)
    let builtOperationReferencedFragments = operation.referencedFragments.map(\.name)

    // then
    expect(operationDescriptorReferencedFragments).to(equal(builtOperationReferencedFragments))
  }
}
