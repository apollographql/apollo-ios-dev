@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import XCTest
import Nimble

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
      networkTransport: MockNetworkTransport(server: self.server, store: store),
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
  class GivenSelectionSet: MockSelectionSet {
    override class var __selections: [Selection] { [
      .field("createReview", CreateReview.self)
    ] }

    class CreateReview: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("__typename", String.self),
        .field("stars", Int.self),
        .field("commentary", String?.self)
      ] }
    }
  }

  let jsonObject: JSONObject = [
    "data": [
      "createReview": [
        "__typename": "Review",
        "stars": 3,
        "commentary": ""
      ] as JSONValue
    ] as JSONValue
  ]

  func test__performMutation_givenPublishResultToStore_true_publishResultsToStore() throws {
    let mutation = MockMutation<GivenSelectionSet>()
    let resultObserver = self.makeResultObserver(for: mutation)

    let serverRequestExpectation = server.expect(MockMutation<GivenSelectionSet>.self) { _ in
      self.jsonObject
    }

    let performResultFromServerExpectation =
      resultObserver.expectation(description: "Mutation was successful") { result in
        switch (result) {
        case .success:
          break
        case let .failure(error):
          fail("Unexpected failure! \(error)")
        }
      }

    // when
    self.client.perform(mutation: mutation,
                        publishResultToStore: true,
                        resultHandler: resultObserver.handler)

    self.wait(for: [serverRequestExpectation, performResultFromServerExpectation], timeout: 0.2)

    // then
    expect(self.cache.publishedRecordSets.count).to(equal(1))

    let actual = self.cache.publishedRecordSets[0]
    expect(actual["MUTATION_ROOT"]).to(equal(
      Record(key: "MUTATION_ROOT", [
        "createReview": CacheReference("MUTATION_ROOT.createReview")
      ])
    ))
    expect(actual["MUTATION_ROOT.createReview"]).to(equal(
      Record(key: "MUTATION_ROOT.createReview", [
        "__typename": "Review",
        "stars": 3,
        "commentary": ""
      ])
    ))
  }

  func test__performMutation_givenPublishResultToStore_false_doesNotPublishResultsToStore() throws {
    let mutation = MockMutation<GivenSelectionSet>()
    let resultObserver = self.makeResultObserver(for: mutation)

    let serverRequestExpectation = server.expect(MockMutation<GivenSelectionSet>.self) { _ in
      self.jsonObject
    }

    let performResultFromServerExpectation =
      resultObserver.expectation(description: "Mutation was successful") { result in
        switch (result) {
        case .success:
          break
        case let .failure(error):
          fail("Unexpected failure! \(error)")
        }
      }

    // when
    self.client.perform(mutation: mutation,
                        publishResultToStore: false,
                        resultHandler: resultObserver.handler)

    self.wait(for: [serverRequestExpectation, performResultFromServerExpectation], timeout: 0.2)

    // then
    expect(self.cache.publishedRecordSets).to(beEmpty())
  }
}
