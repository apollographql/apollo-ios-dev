@_spi(Execution) @_spi(Unsafe) @_spi(Internal) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import XCTest

@testable @_spi(Internal) import Apollo
@testable import Nimble

#warning("TODO: Test if cache returns result, then server returns failed result, APQ retry still occurs")
class AutomaticPersistedQueriesTests: XCTestCase, MockResponseProvider {

  private static let endpoint = TestURL.mockServer.url

  var mockSession: MockURLSession!
  var store: ApolloStore!

  override func setUp() async throws {
    try await super.setUp()
    self.mockSession = MockURLSession(responseProvider: Self.self)
    self.store = ApolloStore(cache: NoCache())
  }

  override func tearDown() async throws {
    await Self.cleanUpRequestHandlers()
    self.mockSession = nil
    self.store = nil
    try await super.tearDown()
  }

  // MARK: - Mocks
  final class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
    override class var __selections: [Selection] {
      [
        .field("hero", Hero.self, arguments: ["episode": .variable("episode")])
      ]
    }

    var hero: Hero? { __data["hero"] }

    final class Hero: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("name", String.self),
        ]
      }

      var name: String { __data["name"] }
    }
  }

  fileprivate enum MockEnum: String, EnumType {
    case NEWHOPE
    case JEDI
    case EMPIRE
  }

  fileprivate class MockHeroNameQuery: MockQuery<HeroNameSelectionSet>, @unchecked Sendable {
    override class var operationDocument: OperationDocument {
      .init(
        operationIdentifier: "f6e76545cd03aa21368d9969cb39447f6e836a16717823281803778e7805d671",
        definition: .init("MockHeroNameQuery - Operation Definition")
      )
    }

    nonisolated(unsafe) var episode: GraphQLNullable<MockEnum> {
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

  fileprivate final class APQMockMutation: MockMutation<MockSelectionSet>, @unchecked Sendable {
    override class var operationDocument: OperationDocument {
      .init(
        operationIdentifier: "4a1250de93ebcb5cad5870acf15001112bf27bb963e8709555b5ff67a1405374",
        definition: .init("APQMockMutation - Operation Definition")
      )
    }
  }

  private static func mockResponseData() -> Data {
    """
    {
      "data": {
        "hero": {
          "__typename": "Hero",
          "name": "Luke"
        }
      }
    }
    """.data(using: .utf8)!
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
    let httpBody: Data?

    if let bodyStream = request.httpBodyStream {
      httpBody = try Data(reading: bodyStream)
    } else {
      httpBody = request.httpBody
    }

    guard
      let httpBody = httpBody,
      let jsonBody = try? JSONSerializationFormat.deserialize(data: httpBody) as JSONObject
    else {
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

    if let query = operation as? MockHeroNameQuery {
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
    }
  }

  // MARK: - Tests

  func testRequestBody() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint
    )

    let query = MockHeroNameQuery()
    nonisolated(unsafe) var lastRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) {
      lastRequest = $0
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let request = try XCTUnwrap(lastRequest, "last request should not be nil")

    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")

    try self.validatePostBody(
      with: request,
      operation: query,
      queryDocument: true
    )
  }

  func testRequestBodyWithVariable() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint
    )

    let query = MockHeroNameQuery(episode: .some(.JEDI))
    nonisolated(unsafe) var lastRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) {
      lastRequest = $0
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")

    try validatePostBody(
      with: request,
      operation: query,
      queryDocument: true
    )
  }

  func testRequestBodyForAPQsWithVariable() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      apqConfig: .init(autoPersistQueries: true)
    )

    let query = MockHeroNameQuery(episode: .some(.EMPIRE))
    nonisolated(unsafe) var lastRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) {
      lastRequest = $0
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let request = try XCTUnwrap(lastRequest, "last request should not be nil")

    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")

    try self.validatePostBody(
      with: request,
      operation: query,
      persistedQuery: true
    )
  }

  func testMutationRequestBodyForAPQs() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      apqConfig: .init(autoPersistQueries: true)
    )

    let mutation = APQMockMutation()
    nonisolated(unsafe) var lastRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) {
      lastRequest = $0
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await network.send(
      mutation: mutation,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let request = try XCTUnwrap(lastRequest, "last request should not be nil")

    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")

    try self.validatePostBody(
      with: request,
      operation: mutation,
      persistedQuery: true
    )
  }

  func testQueryStringForAPQsUseGetMethod() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      apqConfig: .init(autoPersistQueries: true, useGETForPersistedQueryRetry: true)
    )

    let query = MockHeroNameQuery()
    nonisolated(unsafe) var lastRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) {
      lastRequest = $0
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let request = try XCTUnwrap(lastRequest, "last request should not be nil")
    XCTAssertEqual(request.url?.host, network.endpointURL.host)

    try self.validateUrlParams(
      with: request,
      query: query,
      persistedQuery: true
    )
  }

  func testQueryStringForAPQsUseGetMethodWithVariable() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      apqConfig: .init(autoPersistQueries: true, useGETForPersistedQueryRetry: true)
    )

    let query = MockHeroNameQuery(episode: .some(.EMPIRE))
    nonisolated(unsafe) var lastRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) {
      lastRequest = $0
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let request = try XCTUnwrap(lastRequest, "last request should not be nil")

    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "GET")

    try self.validateUrlParams(
      with: request,
      query: query,
      persistedQuery: true
    )
  }

  func testUseGETForQueriesRequest() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      additionalHeaders: ["Authorization": "Bearer 1234"],
      useGETForQueries: true
    )

    let query = MockHeroNameQuery()
    nonisolated(unsafe) var lastRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) {
      lastRequest = $0
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let request = try XCTUnwrap(lastRequest, "last request should not be nil")

    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.allHTTPHeaderFields!["Authorization"], "Bearer 1234")

    try self.validateUrlParams(
      with: request,
      query: query,
      queryDocument: true
    )
  }

  func testNotUseGETForQueriesRequest() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      useGETForQueries: false
    )

    let query = MockHeroNameQuery()
    nonisolated(unsafe) var lastRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) {
      lastRequest = $0
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let request = try XCTUnwrap(lastRequest, "last request should not be nil")

    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")

    try self.validatePostBody(
      with: request,
      operation: query,
      queryDocument: true
    )
  }

  func testNotUseGETForQueriesAPQsRequest() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      apqConfig: .init(autoPersistQueries: true),
      useGETForQueries: false
    )

    let query = MockHeroNameQuery(episode: .some(.EMPIRE))
    nonisolated(unsafe) var lastRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) {
      lastRequest = $0
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let request = try XCTUnwrap(lastRequest, "last request should not be nil")

    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "POST")

    try self.validatePostBody(
      with: request,
      operation: query,
      persistedQuery: true
    )
  }

  func testUseGETForQueriesAPQsRequest() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      apqConfig: .init(autoPersistQueries: true, useGETForPersistedQueryRetry: true),
      useGETForQueries: true
    )

    let query = MockHeroNameQuery(episode: .some(.EMPIRE))
    nonisolated(unsafe) var lastRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) {
      lastRequest = $0
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let request = try XCTUnwrap(lastRequest, "last request should not be nil")

    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "GET")

    try self.validateUrlParams(
      with: request,
      query: query,
      persistedQuery: true
    )
  }

  func testNotUseGETForQueriesAPQsGETRequest() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      apqConfig: .init(autoPersistQueries: true, useGETForPersistedQueryRetry: true),
      useGETForQueries: false
    )

    let query = MockHeroNameQuery(episode: .some(.EMPIRE))
    nonisolated(unsafe) var lastRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) {
      lastRequest = $0
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let request = try XCTUnwrap(lastRequest, "last request should not be nil")

    XCTAssertEqual(request.url?.host, network.endpointURL.host)
    XCTAssertEqual(request.httpMethod, "GET")

    try self.validateUrlParams(
      with: request,
      query: query,
      persistedQuery: true
    )
  }

  // MARK: Persisted Query Retrying Tests

  func
    test__retryPersistedQuery__givenOperation_automaticallyPersisted_PersistedQueryNotFoundResponseError_retriesQueryWithFullDocument()
    async throws
  {
    // given
    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      apqConfig: .init(autoPersistQueries: true),
    )

    let query = MockHeroNameQuery(episode: .some(.EMPIRE))

    nonisolated(unsafe) var requests: [URLRequest] = []

    await Self.registerRequestHandler(for: Self.endpoint) { request in
      requests.append(request)

      let response = HTTPURLResponse(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      if requests.count == 1 {
        let data = try JSONSerialization.data(
          withJSONObject: ["errors": [["message": "PersistedQueryNotFound"]]]
        )
        return (response, data)
      } else {
        return (response, Self.mockResponseData())
      }
    }

    // when
    _ = try await network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    // then
    expect(requests.count).to(equal(2))

    try self.validatePostBody(
      with: requests[0],
      operation: query,
      queryDocument: false,
      persistedQuery: true
    )

    try self.validatePostBody(
      with: requests[1],
      operation: query,
      queryDocument: true,
      persistedQuery: true
    )
  }

  func
    test__retryPersistedQuery__givenOperation_persistedOperationsOnly_PersistedQueryNotFoundResponseError_doesNotRetryAndThrows_persistedQueryNotFoundForPersistedOnlyQuery_error()
    async throws
  {
    // given
    final class MockPersistedOnlyQuery: MockHeroNameQuery, @unchecked Sendable {
      override class var operationDocument: OperationDocument {
        .init(operationIdentifier: "12345")
      }
    }

    let network = RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      apqConfig: .init(autoPersistQueries: true),
    )    

    let query = MockPersistedOnlyQuery(episode: .some(.EMPIRE))

    await Self.registerRequestHandler(for: Self.endpoint) { _ in
      let response = HTTPURLResponse(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      let data = try JSONSerialization.data(
        withJSONObject: ["errors": [["message": "PersistedQueryNotFound"]]]
      )
      return (response, data)
    }

    await expect {
      // when
      _ = try await network.send(
        query: query,
        fetchBehavior: .NetworkOnly,
        requestConfiguration: RequestConfiguration(writeResultsToCache: false)
      ).getAllValues()

      //then
    }.to(
      throwError { error in
        let expectedError = AutomaticPersistedQueryInterceptor.APQError
          .persistedQueryNotFoundForPersistedOnlyQuery(operationName: "MockOperationName")
        expect(error as? AutomaticPersistedQueryInterceptor.APQError).to(equal(expectedError))
      }
    )
  }
}

fileprivate extension Data {
  init(reading input: InputStream) throws {
    self.init()
    input.open()
    defer {
      input.close()
    }

    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer {
      buffer.deallocate()
    }
    while input.hasBytesAvailable {
      let read = input.read(buffer, maxLength: bufferSize)
      if read < 0 {
        //Stream error occured
        throw input.streamError!
      } else if read == 0 {
        //EOF
        break
      }
      self.append(buffer, count: read)
    }
  }
}
