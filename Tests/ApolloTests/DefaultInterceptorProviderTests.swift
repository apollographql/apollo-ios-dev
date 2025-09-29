import XCTest
import Nimble
import Apollo
@_spi(Execution) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers

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
  
  func testLoading() async throws {
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

    let graphQLResult = try await client.fetch(query: MockQuery<GivenSelectionSet>())

    XCTAssertEqual(graphQLResult.source, .server)
    XCTAssertEqual(graphQLResult.data?.hero?.name, "R2-D2")

    await fulfillment(of: [expectation])
  }

  func testInitialLoadFromNetworkAndSecondaryLoadFromCache() async throws {
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

    let graphQLResult = try await client.fetch(query: MockQuery<GivenSelectionSet>())

    XCTAssertEqual(graphQLResult.source, .server)
    XCTAssertEqual(graphQLResult.data?.hero?.name, "R2-D2")

    await fulfillment(of: [initialLoadExpectation])

    let secondLoadResult = try await client.fetch(query: MockQuery<GivenSelectionSet>(), cachePolicy: .cacheFirst)

    XCTAssertEqual(secondLoadResult.source, .cache)
    XCTAssertEqual(secondLoadResult.data?.hero?.name, "R2-D2")
  }


}
