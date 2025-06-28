import XCTest
import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

class DefaultInterceptorProviderTests: XCTestCase {

  var client: ApolloClient!
  var mockServer: MockGraphQLServer!

  static let mockData: JSONObject = [
    "data": [
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid"
      ]
    ]
  ]

  override func setUp() {
    mockServer = MockGraphQLServer()
    let store = ApolloStore()
    let networkTransport = MockNetworkTransport(mockServer: mockServer, store: store)
    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  override func tearDown() {
    client = nil
    mockServer = nil
    
    super.tearDown()
  }
  
  func testLoading() async {
    // given
    final class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      final class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let expectation = await mockServer.expect(MockQuery<GivenSelectionSet>.self) { _ in
      DefaultInterceptorProviderTests.mockData
    }

    client.fetch(query: MockQuery<GivenSelectionSet>()) { result in
      switch result {
      case .success(let graphQLResult):
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertEqual(graphQLResult.data?.hero?.name, "R2-D2")
      case .failure(let error):
        XCTFail("Unexpected error: \(error)")
      }
    }

    await fulfillment(of: [expectation])
  }

  func testInitialLoadFromNetworkAndSecondaryLoadFromCache() async {
    // given
    final class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      final class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let initialLoadExpectation = await mockServer.expect(MockQuery<GivenSelectionSet>.self) { _ in
      DefaultInterceptorProviderTests.mockData
    }
    initialLoadExpectation.assertForOverFulfill = false
    let fetchCompleteExpectation = self.expectation(description: "fetch complete")

    client.fetch(query: MockQuery<GivenSelectionSet>()) { result in
      defer { fetchCompleteExpectation.fulfill() }
      switch result {
      case .success(let graphQLResult):
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertEqual(graphQLResult.data?.hero?.name, "R2-D2")
      case .failure(let error):
        XCTFail("Unexpected error: \(error)")
      }
    }

    await fulfillment(of: [initialLoadExpectation, fetchCompleteExpectation])

    let secondLoadExpectation = self.expectation(description: "loaded with default client")

    client.fetch(query: MockQuery<GivenSelectionSet>(), cachePolicy: .returnCacheDataElseFetch) { result in
      switch result {
      case .success(let graphQLResult):
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertEqual(graphQLResult.data?.hero?.name, "R2-D2")
      case .failure(let error):
        XCTFail("Unexpected error: \(error)")

      }
      secondLoadExpectation.fulfill()
    }

    await fulfillment(of: [secondLoadExpectation], timeout: 10)
  }


}
