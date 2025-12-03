@_spi(Execution) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable @_spi(Execution) import Apollo

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

  static let jsonObject: JSONObject = [
    "data": [
      "createReview": [
        "__typename": "Review",
        "stars": 3,
        "commentary": "",
      ] as JSONValue
    ] as JSONValue
  ]

  // MARK: - Cancellation Tests

  func test__fetch__givenSingleResponse_cancelledBeforeResultReturned_throwsCancellationError() async throws {
    let query = MockQuery<MockSelectionSet>()

    let task = Task { [client] in
      try await client.fetch(query: query, cachePolicy: .networkOnly)
    }

    task.cancel()

    switch await task.result {
      case .success:
      XCTFail("Expected task to fail with a CancellationError")
    case .failure(let error):
      XCTAssertTrue(error is CancellationError)
    }
  }

  func test__performMutation__givenSingleResponse_cancelledBeforeResultReturned_throwsCancellationError() async throws {
    let mutation = MockMutation<MockSelectionSet>()

    let task = Task { [client] in
      try await client.perform(mutation: mutation)
    }

    task.cancel()

    switch await task.result {
      case .success:
      XCTFail("Expected task to fail with a CancellationError")
    case .failure(let error):
      XCTAssertTrue(error is CancellationError)
    }
  }

  func test__upload__givenSingleResponse_cancelledBeforeResultReturned_throwsCancellationError() async throws {
    let query = MockQuery<MockSelectionSet>()

    let task = Task { [client] in
      try await client.upload(operation: query, files: [])
    }

    task.cancel()

    switch await task.result {
      case .success:
      XCTFail("Expected task to fail with a CancellationError")
    case .failure(let error):
      XCTAssertTrue(error is CancellationError)
    }
  }

  // MARK: - Mutation Tests

  func test__performMutation_givenPublishResultToStore_true_publishResultsToStore() async throws {
    let mutation = MockMutation<GivenSelectionSet>()

    let serverRequestExpectation = await server.expect(MockMutation<GivenSelectionSet>.self) { @Sendable _ in
      Self.jsonObject
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

    let serverRequestExpectation = await server.expect(MockMutation<GivenSelectionSet>.self) { @Sendable _ in
      Self.jsonObject
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
