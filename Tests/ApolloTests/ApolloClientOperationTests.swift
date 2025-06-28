import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

final class ApolloClientOperationTests: XCTestCase {

  var cache: MockCache!
  var server: MockGraphQLServer!
  var client: ApolloClient!
  var store: ApolloStore { client.store }

  override func setUpWithError() throws {
    try super.setUpWithError()

    self.cache = MockCache()
    self.server = MockGraphQLServer()
    let store = ApolloStore(cache: self.cache)
    self.client = ApolloClient(
      networkTransport: MockNetworkTransport(mockServer: self.server, store: store),
      store: store
    )
  }

  override func tearDownWithError() throws {
    self.cache = nil
    self.server = nil
    self.client = nil

    try super.tearDownWithError()
  }

  class MockCache: InMemoryNormalizedCache {
    var publishedRecordSets: [RecordSet] = []
    override func merge(records newRecords: RecordSet) throws -> Set<CacheKey> {
      publishedRecordSets.append(newRecords)
      return try super.merge(records: newRecords)
    }
  }

  // given
  class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
    override class var __selections: [Selection] {
      [
        .field("createReview", CreateReview.self)
      ]
    }

    class CreateReview: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("stars", Int.self),
          .field("commentary", String?.self),
        ]
      }
    }
  }

  let jsonObject: JSONObject = [
    "data": [
      "createReview": [
        "__typename": "Review",
        "stars": 3,
        "commentary": "",
      ] as JSONValue
    ] as JSONValue
  ]

  func test__performMutation_givenPublishResultToStore_true_publishResultsToStore() async throws {
    let mutation = MockMutation<GivenSelectionSet>()

    let serverRequestExpectation = await server.expect(MockMutation<GivenSelectionSet>.self) { _ in
      self.jsonObject
    }

    // when
    _ = try await self.client.perform(
      mutation: mutation,
      requestConfiguration: RequestConfiguration(writeResultsToCache: true),
    )

    await fulfillment(of: [serverRequestExpectation], timeout: 0.2)

    // then
    expect(self.cache.publishedRecordSets.count).to(equal(1))

    let actual = self.cache.publishedRecordSets[0]
    expect(actual["MUTATION_ROOT"]).to(
      equal(
        Record(
          key: "MUTATION_ROOT",
          [
            "createReview": CacheReference("MUTATION_ROOT.createReview")
          ]
        )
      )
    )
    expect(actual["MUTATION_ROOT.createReview"]).to(
      equal(
        Record(
          key: "MUTATION_ROOT.createReview",
          [
            "__typename": "Review",
            "stars": 3,
            "commentary": "",
          ]
        )
      )
    )
  }

  func test__performMutation_givenPublishResultToStore_false_doesNotPublishResultsToStore() async throws {
    let mutation = MockMutation<GivenSelectionSet>()

    let serverRequestExpectation = await server.expect(MockMutation<GivenSelectionSet>.self) { _ in
      self.jsonObject
    }

    // when
    _ = try await self.client.perform(
      mutation: mutation,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false),
    )

    await fulfillment(of: [serverRequestExpectation], timeout: 0.2)

    // then
    expect(self.cache.publishedRecordSets).to(beEmpty())
  }
}
