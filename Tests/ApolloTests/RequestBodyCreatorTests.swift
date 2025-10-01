@_spi(Execution) import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo
@testable @_spi(Execution)  @_spi(Internal) import ApolloAPI

class RequestBodyCreatorTests: XCTestCase {

  func create<Operation: GraphQLOperation>(
    with creator: any JSONRequestBodyCreator,
    for operation: Operation
  ) -> JSONEncodableDictionary {
    creator.requestBody(
      for: operation,
      sendQueryDocument: true,
      autoPersistQuery: false
    )
  }

  struct TestCustomRequestBodyCreator: JSONRequestBodyCreator {

    var stubbedRequestBody: JSONEncodableDictionary = ["TestCustomRequestBodyCreator": "TestBodyValue"]

    func requestBody<Operation: GraphQLOperation>(
      for operation: Operation,
      sendQueryDocument: Bool,
      autoPersistQuery: Bool
    ) -> JSONEncodableDictionary {
      stubbedRequestBody
    }
  }


  // MARK: - Tests

  func testRequestBodyWithApolloRequestBodyCreator() {
    // given
    class GivenMockOperation: MockQuery<MockSelectionSet>, @unchecked Sendable {
      override class var operationName: String { "Test Operation Name" }
      override class var operationDocument: OperationDocument {
        .init(definition: .init("Test Query Document"))
      }
    }

    let operation = GivenMockOperation()
    operation.__variables = ["TestVar": 123]

    let creator = DefaultRequestBodyCreator()

    // when
    let actual = self.create(with: creator, for: operation)

    // then
    expect(actual["operationName"]).to(equalJSONValue("Test Operation Name"))
    expect(actual["variables"]).to(equalJSONValue(["TestVar": 123]))
    expect(actual["query"]).to(equalJSONValue("Test Query Document"))
  }

  func testRequestBodyWithCustomRequestBodyCreator() {
    // given
    let creator = TestCustomRequestBodyCreator()
    let expected = creator.stubbedRequestBody

    // when
    let actual = self.create(with: creator, for: MockQuery.mock())

    // then
    expect(actual).to(equalJSONValue(expected))
  }

  func test_requestBody_withCustomScalarVariable_createsBodyWithEncodedJSONValueForVariable() {
    // given
    struct MockScalar: CustomScalarType, Hashable {
      let data: String
      init(_ data: String) {
        self.data = data
      }

      init(_jsonValue value: JSONValue) throws {
        data = value as! String
      }

      var _jsonValue: JSONValue { data }
    }

    class GivenMockOperation: MockQuery<MockSelectionSet>, @unchecked Sendable {
      override class var operationName: String { "Test Operation Name" }
      override class var operationDocument: OperationDocument {
        .init(definition: .init("Test Query Document"))
      }
    }

    let operation = GivenMockOperation()
    operation.__variables = ["TestVar": MockScalar("123")]

    let creator = DefaultRequestBodyCreator()

    // when
    let actual = self.create(with: creator, for: operation)

    // then
    expect(actual["operationName"]).to(equalJSONValue("Test Operation Name"))
    expect(actual["variables"]).to(equalJSONValue(["TestVar": "123"]))
    expect(actual["query"]).to(equalJSONValue("Test Query Document"))
  }
}
