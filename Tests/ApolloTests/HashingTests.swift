import XCTest
import Nimble
import ApolloAPI
import ApolloInternalTestHelpers

final class HashingTests: XCTestCase {

  class SimpleMockSelectionSet: MockSelectionSet {
    override class var __selections: [Selection] { [
      .field("hero", Hero.self)
    ]}

    class Hero: MockSelectionSet {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("name", String.self)
      ]}
    }
  }

  func test__hash__givenOperationsWithoutVariables_shouldHaveUniqueHashValues() throws {
    class QueryOne: GraphQLQuery {
      typealias Data = SimpleMockSelectionSet

      static var operationDocument: ApolloAPI.OperationDocument = .init(
        definition: .init(
          #"query QueryOne { }"#
        ))


      static var operationName: String = "QueryOne"
    }

    class QueryTwo: GraphQLQuery {
      typealias Data = SimpleMockSelectionSet

      static var operationDocument: ApolloAPI.OperationDocument = .init(
        definition: .init(
          #"query QueryTwo { }"#
        ))


      static var operationName: String = "QueryTwo"
    }

    let hashOne = QueryOne().hashValue
    let hashTwo = QueryTwo().hashValue

    expect(hashOne).notTo(equal(hashTwo))
  }

}
