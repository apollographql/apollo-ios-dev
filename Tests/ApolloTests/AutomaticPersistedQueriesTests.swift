import XCTest
@testable import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

class AutomaticPersistedQueriesTests: XCTestCase {

  private static let endpoint = TestURL.mockServer.url

  // MARK: - Mocks
  class HeroNameSelectionSet: MockSelectionSet {
    override class var __selections: [Selection] {[
      .field("hero", Hero.self, arguments: ["episode": .variable("episode")])
    ]}

    var hero: Hero? { __data["hero"] }

    class Hero: MockSelectionSet {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("name", String.self),
      ]}

      var name: String { __data["name"] }
    }
  }

  fileprivate enum MockEnum: String, EnumType {
    case NEWHOPE
    case JEDI
    case EMPIRE
  }

  fileprivate class MockHeroNameQuery: MockQuery<HeroNameSelectionSet> {
    override class var operationDocument: OperationDocument {
      .init(
        operationIdentifier: "f6e76545cd03aa21368d9969cb39447f6e836a16717823281803778e7805d671",
        definition: .init("MockHeroNameQuery - Operation Definition")
      )
    }

    var episode: GraphQLNullable<MockEnum> {
      didSet {
        self.__variables = ["episode": episode]
      }
    }

    init(episode: GraphQLNullable<MockEnum> = .none) {
      self.episode = episode
      super.init()
      self.__variables = ["episode": episode]
    }
  }

  fileprivate class APQMockMutation: MockMutation<MockSelectionSet> {
    override class var operationDocument: OperationDocument {
      .init(
        operationIdentifier: "4a1250de93ebcb5cad5870acf15001112bf27bb963e8709555b5ff67a1405374",
        definition: .init("APQMockMutation - Operation Definition")
      )
    }
  }

  // MARK: - Helper Methods

  private func validatePostBody<O: GraphQLOperation>(
    with request: URLRequest,
    operation: O,
    queryDocument: Bool = false,
    persistedQuery: Bool = false,
    fileID: String = #fileID,
    file: Nimble.FileString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) throws {
    let location = SourceLocation(fileID: fileID, filePath: file, line: line, column: column)
    guard
      let httpBody = request.httpBody,
      let jsonBody = try? JSONSerializationFormat.deserialize(data: httpBody) as JSONObject else {
      fail(
        "httpBody invalid",
        location: location
      )
      return
    }
    
    let queryString = jsonBody["query"] as? String
    if queryDocument {
      expect(file: file, line: line, queryString)
      .to(equal(O.definition?.queryDocument))
    }
    
    if let query = operation as? MockHeroNameQuery{
      if let variables = jsonBody["variables"] as? JSONObject {

        if let episode = query.episode.rawValue {
          expect(file: file, line: line, variables["episode"] as? String)
            .to(equal(episode))
        } else {
          expect(file: file, line: line, variables["episode"] as? String).to(beNil())
        }

      } else {
        fail(
          "variables should not be nil",
          location: location
        )
      }
    }
    
    let ext = jsonBody["extensions"] as? JSONObject
    if persistedQuery {
      guard let ext = ext else {
        fail(
          "extensions json data should not be nil",
          location: location
        )
        return
      }
      
      guard let persistedQuery = ext["persistedQuery"] as? JSONObject else {
        fail(
          "persistedQuery is missing",
          location: location
        )
        return
      }

      guard let version = persistedQuery["version"] as? Int else {
        fail(
          "version is missing",
          location: location
        )
        return
      }

      guard let sha256Hash = persistedQuery["sha256Hash"] as? String else {
        fail(
          "sha256Hash is missing",
          location: location
        )
        return
      }


      expect(file: file, line: line, version).to(equal(1))

      expect(file: file, line: line, sha256Hash).to(equal(O.operationIdentifier))

    } else {
      expect(file: file, line: line, ext).to(beNil())
    }
  }
  
  private func validateUrlParams(
    with request: URLRequest,
    query: MockHeroNameQuery,
    queryDocument: Bool = false,
    persistedQuery: Bool = false,
    fileID: String = #fileID,
    file: Nimble.FileString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) throws {
    let location = SourceLocation(fileID: fileID, filePath: file, line: line, column: column)
    guard let url = request.url else {
      fail(
        "URL not valid",
        location: location
      )
      return
    }

    let queryString = url.queryItemDictionary?["query"]
    if queryDocument {
      expect(file: file, line: line, queryString)
        .to(equal(MockHeroNameQuery.definition?.queryDocument))

    } else {
      expect(file: file, line: line, queryString).to(beNil())

    }
    
    if let variables = url.queryItemDictionary?["variables"] {
      let expectation = expect(file: file, line: line, variables)
      switch query.episode {
      case let .some(episode):
        expectation.to(equal("{\"episode\":\"\(episode.rawValue)\"}"))

      case .none:
        #warning("TODO: write test to test this case actually happens")
        expectation.to(equal("{}"))

      case .null:
        expectation.to(equal("{\"episode\":null}"))
      }
    } else {
      fail(
        "variables should not be nil",
        location: location
      )
    }
    
    let ext = url.queryItemDictionary?["extensions"]
    if persistedQuery {
      guard
        let ext = ext,
        let data = ext.data(using: .utf8),
        let jsonBody = try? JSONSerializationFormat.deserialize(data: data) as JSONObject
        else {
        fail(
          "extensions json data should not be nil",
          location: location
        )
        return
      }
      
      guard let persistedQuery = jsonBody["persistedQuery"] as? JSONObject else {
        fail(
          "persistedQuery is missing",
          location: location
        )
        return
      }

      guard let sha256Hash = persistedQuery["sha256Hash"] as? String else {
        fail(
          "sha256Hash is missing",
          location: location
        )
        return
      }

      guard let version = persistedQuery["version"] as? Int else {
        fail(
          "version is missing",
          location: location
        )
        return
      }
      
      expect(file: file, line: line, version).to(equal(1))

      expect(file: file, line: line, sha256Hash).to(equal(MockHeroNameQuery.operationIdentifier))

    } else {
      expect(file: file, line: line, ext).to(beNil())
    }
  }

  
  // MARK: - Tests
  
  func testRequestBody() throws {
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint)
    
    let expectation = self.expectation(description: "Query sent")
    let query = MockHeroNameQuery()
    var lastRequest: URLRequest?
    let _ = network.send(operation: query) { _ in
      lastRequest = mockClient.lastRequest
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 1)
    
    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")
    
    try self.validatePostBody(with: request,
                              operation: query,
                              queryDocument: true)
  }
  
  func testRequestBodyWithVariable() throws {
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint)
    
    let expectation = self.expectation(description: "Query sent")
    let query = MockHeroNameQuery(episode: .some(.JEDI))
    var lastRequest: URLRequest?
    let _ = network.send(operation: query) { _ in
      lastRequest = mockClient.lastRequest
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 1)
    
    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")
    
    try validatePostBody(with: request,
                         operation: query,
                         queryDocument: true)
  }
  
  
  func testRequestBodyForAPQsWithVariable() throws {
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint,
                                               autoPersistQueries: true)
    
    let expectation = self.expectation(description: "Query sent")
    let query = MockHeroNameQuery(episode: .some(.EMPIRE))
    var lastRequest: URLRequest?
    let _ = network.send(operation: query) { _ in
      lastRequest = mockClient.lastRequest
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 1)
    
    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")
    
    try self.validatePostBody(with: request,
                              operation: query,
                              persistedQuery: true)
  }
  
  func testMutationRequestBodyForAPQs() throws {
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint,
                                               autoPersistQueries: true)
    
    let expectation = self.expectation(description: "Mutation sent")
    let mutation = APQMockMutation()
    var lastRequest: URLRequest?
    let _ = network.send(operation: mutation) { _ in
      lastRequest = mockClient.lastRequest
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 1)
    
    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")

    try self.validatePostBody(with: request,
                              operation: mutation,
                              persistedQuery: true)
  }
  
  func testQueryStringForAPQsUseGetMethod() throws {
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint,
                                               autoPersistQueries: true,
                                               useGETForPersistedQueryRetry: true)

    let expectation = self.expectation(description: "Query sent")
    let query = MockHeroNameQuery()
    var lastRequest: URLRequest?
    let _ = network.send(operation: query) { _ in
      lastRequest = mockClient.lastRequest
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 1)
    
    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    
    try self.validateUrlParams(with: request,
                               query: query,
                               persistedQuery: true)
  }
  
  func testQueryStringForAPQsUseGetMethodWithVariable() throws {
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint,
                                               autoPersistQueries: true,
                                               useGETForPersistedQueryRetry: true)
    
    let expectation = self.expectation(description: "Query sent")
    let query = MockHeroNameQuery(episode: .some(.EMPIRE))
    var lastRequest: URLRequest?
    let _ = network.send(operation: query) { _ in
      lastRequest = mockClient.lastRequest
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 1)
    
    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "GET")
    
    try self.validateUrlParams(with: request,
                               query: query,
                               persistedQuery: true)
  }
  
  func testUseGETForQueriesRequest() throws {
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint,
                                               additionalHeaders: ["Authorization": "Bearer 1234"],
                                               useGETForQueries: true)
    
    let expectation = self.expectation(description: "Query sent")
    let query = MockHeroNameQuery()
    var lastRequest: URLRequest?
    let _ = network.send(operation: query) { _ in
      lastRequest = mockClient.lastRequest
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 1)
    
    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.allHTTPHeaderFields!["Authorization"], "Bearer 1234")
    
    try self.validateUrlParams(with: request,
                               query: query,
                               queryDocument: true)
  }
  
  func testNotUseGETForQueriesRequest() throws {
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint)
    
    let expectation = self.expectation(description: "Query sent")
    let query = MockHeroNameQuery()
    var lastRequest: URLRequest?
    let _ = network.send(operation: query) { _ in
      lastRequest = mockClient.lastRequest
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 1)
    
    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")
    
    try self.validatePostBody(with: request,
                              operation: query,
                              queryDocument: true)
  }
  
  func testNotUseGETForQueriesAPQsRequest() throws {
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint,
                                               autoPersistQueries: true)
    
    let expectation = self.expectation(description: "Query sent")
    let query = MockHeroNameQuery(episode: .some(.EMPIRE))
    var lastRequest: URLRequest?
    let _ = network.send(operation: query) { _ in
      lastRequest = mockClient.lastRequest
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 1)
    
    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")
    
    try self.validatePostBody(with: request,
                              operation: query,
                              persistedQuery: true)
  }
  
  func testUseGETForQueriesAPQsRequest() throws {
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint,
                                               autoPersistQueries: true,
                                               useGETForQueries: true)
    
    let expectation = self.expectation(description: "Query sent")
    let query = MockHeroNameQuery(episode: .some(.EMPIRE))
    var lastRequest: URLRequest?
    let _ = network.send(operation: query) { _ in
      lastRequest = mockClient.lastRequest
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 1)
    
    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "GET")
    
    try self.validateUrlParams(with: request,
                               query: query,
                               persistedQuery: true)
  }
  
  func testNotUseGETForQueriesAPQsGETRequest() throws {
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint,
                                               autoPersistQueries: true,
                                               useGETForPersistedQueryRetry: true)
    
    let expectation = self.expectation(description: "Query sent")
    let query = MockHeroNameQuery(episode: .some(.EMPIRE))
    var lastRequest: URLRequest?
    let _ = network.send(operation: query) { _ in
      lastRequest = mockClient.lastRequest
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: 2)
    
    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "GET")
    
    try self.validateUrlParams(with: request,
                               query: query,
                               persistedQuery: true)
  }

  // MARK: Persisted Query Retrying Tests

  func test__retryPersistedQuery__givenOperation_automaticallyPersisted_PersistedQueryNotFoundResponseError_retriesQueryWithFullDocument() throws {
    // given
    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint,
                                               autoPersistQueries: true)

    let query = MockHeroNameQuery(episode: .some(.EMPIRE))

    mockClient.response = HTTPURLResponse(url: TestURL.mockServer.url,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)

    mockClient.data = try JSONSerialization.data(
      withJSONObject: ["errors": [["message": "PersistedQueryNotFound"]]]
    )

    // when
    let _ = network.send(operation: query) { _ in }

    // then
    expect(mockClient.requestCount).toEventually(equal(2))
  }

  func test__retryPersistedQuery__givenOperation_persistedOperationsOnly_PersistedQueryNotFoundResponseError_doesNotRetryAndThrows_persistedQueryNotFoundForPersistedOnlyQuery_error() throws {
    // given
    class MockPersistedOnlyQuery: MockHeroNameQuery {
      override class var operationDocument: OperationDocument {
        .init(operationIdentifier: "12345")
      }
    }

    let mockClient = MockURLSessionClient()
    let store = ApolloStore()
    let provider = DefaultInterceptorProvider(client: mockClient, store: store)
    let network = RequestChainNetworkTransport(interceptorProvider: provider,
                                               endpointURL: Self.endpoint,
                                               autoPersistQueries: true)

    let query = MockPersistedOnlyQuery(episode: .some(.EMPIRE))

    mockClient.response = HTTPURLResponse(url: TestURL.mockServer.url,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)

    mockClient.data = try JSONSerialization.data(
      withJSONObject: ["errors": [["message": "PersistedQueryNotFound"]]]
    )

    let expectation = self.expectation(description: "Query failed")

    // when
    let _ = network.send(operation: query) { result in
      // then
      switch result {
      case .success:
        fail("Expected failure result")
      case .failure(let error):
        let expectedError = AutomaticPersistedQueryInterceptor.APQError
          .persistedQueryNotFoundForPersistedOnlyQuery(operationName: "MockOperationName")
        expect(error as? AutomaticPersistedQueryInterceptor.APQError).to(equal(expectedError))
        
        expectation.fulfill()
      }
    }

    self.wait(for: [expectation], timeout: 2)
  }
}
