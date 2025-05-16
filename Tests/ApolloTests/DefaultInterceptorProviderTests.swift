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
    let networkTransport = MockNetworkTransport(server: mockServer, store: store)
    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  override func tearDown() {
    client = nil
    mockServer = nil
    
    super.tearDown()
  }
  
  func testLoading() {
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

    let expectation = mockServer.expect(MockQuery<GivenSelectionSet>.self) { _ in
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

    self.wait(for: [expectation], timeout: 10)
  }

  func testInitialLoadFromNetworkAndSecondaryLoadFromCache() {
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

    let initialLoadExpectation = mockServer.expect(MockQuery<GivenSelectionSet>.self) { _ in
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

    self.wait(for: [initialLoadExpectation, fetchCompleteExpectation], timeout: 10)

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

    self.wait(for: [secondLoadExpectation], timeout: 10)
  }


}
