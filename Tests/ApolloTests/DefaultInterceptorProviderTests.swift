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
    class GivenSelectionSet: MockSelectionSet {
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
    class GivenSelectionSet: MockSelectionSet {
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

    client.fetch(query: MockQuery<GivenSelectionSet>()) { result in
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

  func test__interceptors__givenOperationWithoutDeferredFragments_shouldUseJSONParsingInterceptor() throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
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

    // when
    let actual = DefaultInterceptorProvider(client: URLSessionClient(), store: client.store)
      .interceptors(for: MockQuery<GivenSelectionSet>())

    // then
    XCTAssertTrue(actual.contains { interceptor in
      interceptor is JSONResponseParsingInterceptor
    })
    XCTAssertFalse(actual.contains { interceptor in
      interceptor is IncrementalJSONResponseParsingInterceptor
    })
  }

  func test__interceptors__givenOperationWithDeferredFragments_shouldUseIncrementalJSONParsingInterceptor() throws {
    // given
    class DeferredQuery: MockQuery<DeferredQuery.Animal> {
      class Animal: AbstractMockSelectionSet<Animal.Fragments, MockSchemaMetadata> {
        override class var __selections: [Selection] {[
          .deferred(DeferredName.self, label: "deferredName"),
        ]}

        struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredName = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredName: DeferredName?
        }

        class DeferredName: MockTypeCase {
          override class var __selections: [Selection] {[
            .field("name", String.self),
          ]}
        }
      }

      override class var deferredFragments: [DeferredFragmentIdentifier : any SelectionSet.Type]? {[
        DeferredFragmentIdentifier(label: "deferredName", fieldPath: []): Animal.DeferredName.self,
      ]}
    }

    // when
    let actual = DefaultInterceptorProvider(client: URLSessionClient(), store: client.store)
      .interceptors(for: DeferredQuery())

    // then
    XCTAssertTrue(actual.contains { interceptor in
      interceptor is IncrementalJSONResponseParsingInterceptor
    })
    XCTAssertFalse(actual.contains { interceptor in
      interceptor is JSONResponseParsingInterceptor
    })
  }
}
