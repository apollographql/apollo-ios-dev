import XCTest
import Nimble
import GraphQLCompiler
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class LegacyAPQOperationManifestTemplateTests: XCTestCase {
  var subject: LegacyAPQOperationManifestTemplate!
  var operationIdentiferFactory: OperationIdentifierFactory!

  override func setUp() {
    super.setUp()

    subject = LegacyAPQOperationManifestTemplate()
    operationIdentiferFactory = OperationIdentifierFactory()
  }

  override func tearDown() {
    subject = nil
    operationIdentiferFactory = nil

    super.tearDown()
  }

  // MARK: Render tests

  func test__render__givenSingleOperation_shouldOutputJSONFormat() async throws {
    // given
    let operation = CompilationResult.OperationDefinition.mock(
      name: "TestQuery",
      type: .query,
      source: """
        query TestQuery {
          test
        }
        """
    )

    let expected = """
      {
        "8ed9fcbb8ef3c853ad0ecdc920eb8216608bd7c3b32258744e9289ec0372eb30" : {
          "name": "TestQuery",
          "source": "query TestQuery { test }"
        }
      }
      """

    let operations = [
      OperationManifestTemplate.OperationManifestItem(
        operation: OperationDescriptor(operation),
        identifier: try await self.operationIdentiferFactory.identifier(for: operation)
      )
    ]

    // when
    let rendered = subject.render(operations: operations)

    expect(rendered).to(equal(expected))
  }

  func test__render__givenMultipleOperations_shouldOutputJSONFormat() async throws {
    // given
    let operations = try await [
      CompilationResult.OperationDefinition.mock(
        name: "TestQuery",
        type: .query,
        source: """
        query TestQuery {
          test
        }
        """
      ),
      CompilationResult.OperationDefinition.mock(
        name: "TestMutation",
        type: .mutation,
        source: """
        mutation TestMutation {
          update {
            result
          }
        }
        """
      ),
      CompilationResult.OperationDefinition.mock(
        name: "TestSubscription",
        type: .subscription,
        source: """
        subscription TestSubscription {
          watched
        }
        """
      )
    ].asyncMap { [operationIdentiferFactory] in
      OperationManifestTemplate.OperationManifestItem(
        operation: OperationDescriptor($0),
        identifier: try await operationIdentiferFactory!.identifier(for: $0)
      )
    }

    let expected = """
      {
        "8ed9fcbb8ef3c853ad0ecdc920eb8216608bd7c3b32258744e9289ec0372eb30" : {
          "name": "TestQuery",
          "source": "query TestQuery { test }"
        },
        "551253009bea9350463d15e24660e8a935abc858cd161623234fb9523b0c0717" : {
          "name": "TestMutation",
          "source": "mutation TestMutation { update { result } }"
        },
        "9b56a2829263b4d81b4eb9865470a6971c8e40e126e2ff92db51f15d0a4cb7ba" : {
          "name": "TestSubscription",
          "source": "subscription TestSubscription { watched }"
        }
      }
      """

    // when
    let rendered = subject.render(operations: operations)

    expect(rendered).to(equal(expected))
  }

  func test__render__givenReferencedFragments_shouldOutputJSONFormat() async throws {
    // given
    let operations = try await [
      CompilationResult.OperationDefinition.mock(
        name: "Friends",
        type: .query,
        source: """
        query Friends {
          friends {
            ...Name
          }
        }
        """,
        referencedFragments: [
          .mock(
            "Name",
            type: .mock(),
            source: """
            fragment Name on Friend {
              name
            }
            """
          )
        ]
      )
    ].asyncMap { [operationIdentiferFactory] in
      OperationManifestTemplate.OperationManifestItem(
        operation: OperationDescriptor($0),
        identifier: try await operationIdentiferFactory!.identifier(for: $0)
      )
    }

    let expected = #"""
      {
        "efc7785ac9768b2be96e061911b97c9c898df41561dda36d9435e94994910f67" : {
          "name": "Friends",
          "source": "query Friends { friends { ...Name } }\nfragment Name on Friend { name }"
        }
      }
      """#

    // when
    let rendered = subject.render(operations: operations)

    expect(rendered).to(equal(expected))
  }
}

