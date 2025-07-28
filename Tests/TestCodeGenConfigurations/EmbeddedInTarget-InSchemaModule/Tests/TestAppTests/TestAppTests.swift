import ApolloTestSupport
import XCTest

@testable import Apollo
@testable import TestApp

final class TestAppTests: XCTestCase {
  func testCacheKeyResolution() async throws {
    let store = ApolloStore()

    let data =
      [
        "data": [
          "allAnimals": [
            [
              "__typename": "Dog",
              "id": "1",
              "skinCovering": "Fur",
              "species": "Canine",
              "houseDetails": "Single Level Ranch",
            ]
          ]
        ]
      ] as JSONObject

    let parser = JSONResponseParser(
      response: HTTPURLResponse(),
      operationVariables: [:],
      includeCacheRecords: true
    )

    let result: ParsedResult<AnimalKingdomAPI.DogQuery> = try await parser.parseSingleResponse(body: data)
    let records = result.cacheRecords

    try await store.publish(records: records!)

    try await store.withinReadTransaction { transaction in
      let dog = try! await transaction.readObject(
        ofType: AnimalKingdomAPI.DogQuery.Data.AllAnimal.self,
        withKey: "Dog:1"
      )

      XCTAssertEqual(dog.id, "1")
    }
  }

  func test_mockObject_initialization() throws {
    // given
    let mockDog: Mock<Dog> = Mock(id: "100")

    // then
    XCTAssertEqual(mockDog.id, "100")
  }
}

final class MockNetworkTransport: NetworkTransport {

  func send<Query: GraphQLQuery>(
    query: Query,
    fetchBehavior: FetchBehavior,
    requestConfiguration: RequestConfiguration
  ) throws -> AsyncThrowingStream<GraphQLResponse<Query>, any Error> {
    return .init {
      return nil
    }
  }

  func send<Mutation: GraphQLMutation>(
    mutation: Mutation,
    requestConfiguration: RequestConfiguration
  ) throws -> AsyncThrowingStream<GraphQLResponse<Mutation>, any Error> {
    return .init {
      return nil
    }
  }
  
}
