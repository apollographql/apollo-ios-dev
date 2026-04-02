@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable @_spi(Execution) import Apollo

class RequestChainNetworkTransportTests: XCTestCase, MockResponseProvider {

  var session: MockURLSession!

  let serverUrl = TestURL.mockServer.url

  override func setUp() async throws {
    try await super.setUp()

    session = MockURLSession(responseProvider: Self.self)
  }

  override func tearDown() async throws {
    session = nil
    await Self.cleanUpRequestHandlers()

    try await super.tearDown()
  }

  // MARK: - Helpers

  struct MockProvider: InterceptorProvider {
    var interceptors: [any GraphQLInterceptor]

    func graphQLInterceptors<Operation>(for operation: Operation) -> [any GraphQLInterceptor] where Operation : GraphQLOperation {
      interceptors
    }
  }

  static func emptyResponseData() -> Data {
    return """
      {
        "data": {}
      }
      """.crlfFormattedData()
  }

  private class Hero: MockSelectionSet, @unchecked Sendable {
    typealias Schema = MockSchemaMetadata

    override class var __selections: [Selection] {
      [
        .field("__typename", String.self),
        .field("name", String.self),
      ]
    }

    var name: String { __data["name"] }
  }

  /// A control object that allows tests to yield multipart subscription events
  /// to a response stream managed by a `MultiResponseHandler`.
  ///
  /// Yields data formatted as multipart chunks with `boundary=graphql` and
  /// `subscriptionSpec=1.0`. Each `yieldEvent()` delivers one complete multipart
  /// part that the `AsyncHTTPResponseChunkSequence` will split at the boundary
  /// and pass to the `MultipartResponseSubscriptionParser`.
  ///
  /// Thread-safe: the continuation is set on a background thread (inside `MockURLProtocol`)
  /// and consumed from the test's main context.
  fileprivate class MultipartStreamControl: @unchecked Sendable {
    private let lock = NSLock()
    private var _continuation: AsyncThrowingStream<Data, any Error>.Continuation?

    /// Whether the response handler has been called and the continuation is available.
    var isReady: Bool {
      lock.withLock { _continuation != nil }
    }

    /// A single multipart subscription event.
    ///
    /// Format: `\r\n--graphql\r\n<part>\r\n--graphql`
    ///
    /// The `AsyncHTTPResponseChunkSequence` reads bytes and splits at the
    /// `\r\n--graphql` boundary. The first boundary yields an empty buffer (skipped),
    /// and the second boundary yields the part content as a chunk.
    private static let eventData: Data = {
      let part = "content-type: application/json\r\n\r\n{\"payload\":{\"data\":{}}}"
      return "\r\n--graphql\r\n\(part)\r\n--graphql".data(using: .utf8)!
    }()

    /// A multipart chunk containing a transport error.
    private static let errorEventData: Data = {
      let part = "content-type: application/json\r\n\r\n{\"errors\":[{\"message\":\"subscription error\"}]}"
      return "\r\n--graphql\r\n\(part)\r\n--graphql".data(using: .utf8)!
    }()

    func setContinuation(_ continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
      lock.withLock { _continuation = continuation }
    }

    func yieldEvent() {
      _ = lock.withLock { _continuation?.yield(Self.eventData) }
    }

    func yieldErrorEvent() {
      _ = lock.withLock { _continuation?.yield(Self.errorEventData) }
    }

    func finish() {
      lock.withLock { _continuation?.finish() }
    }
  }
  
  /// The multipart Content-Type header for subscription responses.
  private static let subscriptionContentType = [
    "Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"
  ]

  private func makeSubscriptionTransport(
    withStreamControl control: MultipartStreamControl
  ) async -> RequestChainNetworkTransport {
    await Self.registerRequestHandler(for: serverUrl) { [control] request in
      let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
      control.setContinuation(continuation)
      return (
        .mock(headerFields: RequestChainNetworkTransportTests.subscriptionContentType),
        stream
      )
    }

    return RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: MockProvider(interceptors: []),
      store: .mock(),
      endpointURL: serverUrl
    )
  }

  // MARK: - Tests

  func test_send_givenNoDataChunkReturned_throwsNoResultsError() async throws {
    await Self.registerRequestHandler(for: serverUrl) { request -> (HTTPURLResponse, Data?) in
      (.mock(), nil)
    }

    let transport = RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: MockProvider(interceptors: []),
      store: .mock(),
      endpointURL: serverUrl
    )

    let resultStream = try transport.send(
      query: MockQuery.mock(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    )

    await expect {
      try await resultStream.getAllValues()
    }.to(throwError(ApolloClient.Error.noResults))
  }

  // MARK: - Cancellation tests

  func test__cancellingTask__propogatesTaskCancellationToInterceptors() async throws {
    await Self.registerRequestHandler(for: serverUrl) { request in
      (
        .mock(),
        Self.emptyResponseData()
      )
    }

    let cancellationInterceptor = CancellationTestingInterceptor()
    let retryInterceptor = BlindRetryingTestInterceptor()

    let transport = RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: MockProvider(interceptors: [
        cancellationInterceptor,
        retryInterceptor,
      ]),
      store: .mock(),
      endpointURL: serverUrl
    )

    let task = Task {
      let responseStream = try transport.send(
        query: MockQuery.mock(),
        fetchBehavior: .NetworkOnly,
        requestConfiguration: RequestConfiguration(writeResultsToCache: false)
      )

      for try await _ in responseStream {
        fail("This should not have gone through")
      }
    }

    task.cancel()

    await expect(cancellationInterceptor.hasBeenCancelled).toEventually(beTrue())
  }

  // MARK: - Subscription State Tests

  func testSubscriptionState__shouldBePending__beforeFirstValue() async throws {
    let control = MultipartStreamControl()
    let transport = await makeSubscriptionTransport(withStreamControl: control)

    let subscriptionStream = try transport.send(
      subscription: MockSubscription.mock(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    )

    expect(subscriptionStream.state).to(equal(.pending))

    control.finish()
  }

  func testSubscriptionState__shouldBecomeActive__afterFirstValue() async throws {
    let control = MultipartStreamControl()
    let transport = await makeSubscriptionTransport(withStreamControl: control)

    let subscriptionStream = try transport.send(
      subscription: MockSubscription.mock(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    )

    await expect(control.isReady).toEventually(beTrue())
    control.yieldEvent()

    await expect(subscriptionStream.state).toEventually(equal(.active))

    control.finish()
  }

  func testSubscriptionState__shouldBeFinishedCompleted__afterNormalCompletion() async throws {
    let control = MultipartStreamControl()
    let transport = await makeSubscriptionTransport(withStreamControl: control)

    let subscriptionStream = try transport.send(
      subscription: MockSubscription.mock(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    )

    await expect(control.isReady).toEventually(beTrue())
    control.yieldEvent()
    control.finish()

    await expect(subscriptionStream.state).toEventually(equal(.finished(.completed)))
  }

  func testSubscriptionState__shouldBeFinishedError__afterError() async throws {
    let control = MultipartStreamControl()
    let transport = await makeSubscriptionTransport(withStreamControl: control)

    let subscriptionStream = try transport.send(
      subscription: MockSubscription.mock(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    )

    await expect(control.isReady).toEventually(beTrue())
    control.yieldEvent()
    await expect(subscriptionStream.state).toEventually(equal(.active))

    control.yieldErrorEvent()

    await expect(subscriptionStream.state).toEventually(equal(.finished(.error(URLError(.unknown)))))
  }

  func testSubscriptionState__shouldBeFinishedCancelled__whenTaskCancelled() async throws {
    let control = MultipartStreamControl()
    let transport = await makeSubscriptionTransport(withStreamControl: control)

    let subscriptionStream = try transport.send(
      subscription: MockSubscription.mock(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    )

    await expect(control.isReady).toEventually(beTrue())
    control.yieldEvent()
    await expect(subscriptionStream.state).toEventually(equal(.active))

    // Start consuming the stream, then cancel
    let task = Task {
      for try await _ in subscriptionStream {}
    }

    task.cancel()

    await expect(subscriptionStream.state).toEventually(equal(.finished(.cancelled)))
  }

  // MARK: - Retrying tests

  func test__retryingTask__givenInterceptorThrowsRetryError_retriesWithRequestFromError() async throws {
    class RetryingTestInterceptor: GraphQLInterceptor, @unchecked Sendable {
      func intercept<Request: GraphQLRequest>(
        request: Request,
        next: NextInterceptorFunction<Request>
      ) async throws -> InterceptorResultStream<Request> {
        if let isRetry = request.additionalHeaders["IsRetry"],
          isRetry == "true"
        {
          return await next(request)
        }

        var request = request
        request.addHeader(name: "IsRetry", value: "true")
        throw RequestChain.Retry(request: request)
      }

    }

    let retryInterceptor = RetryingTestInterceptor()

    let transport = RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: MockProvider(interceptors: [retryInterceptor]),
      store: .mock(),
      endpointURL: serverUrl
    )

    await Self.registerRequestHandler(for: serverUrl) { request in
      expect(request.allHTTPHeaderFields?["IsRetry"]).to(equal("true"))

      return (
        .mock(),
        Self.emptyResponseData()
      )
    }

    let responseStream = try transport.send(
      query: MockQuery.mock(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    )

    let actual = try await responseStream.getAllValues()
    expect(actual.count).to(equal(1))
  }  

  // MARK: - Interceptor Chain Ordering Tests

  /// An interceptor that records when it is called, then forwards to the next interceptor.
  struct OrderTrackingInterceptor: GraphQLInterceptor, @unchecked Sendable {
    let index: Int
    let callOrder: CallOrderTracker

    func intercept<Request: GraphQLRequest>(
      request: Request,
      next: NextInterceptorFunction<Request>
    ) async throws -> InterceptorResultStream<Request> {
      callOrder.record(index)
      return await next(request)
    }
  }

  /// Thread-safe tracker for interceptor call order.
  final class CallOrderTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _order: [Int] = []

    func record(_ index: Int) {
      lock.withLock { _order.append(index) }
    }

    var order: [Int] {
      lock.withLock { _order }
    }
  }

  func test__interceptorChain__givenMultipleInterceptors__shouldCallAllInOrder() async throws {
    await Self.registerRequestHandler(for: serverUrl) { _ in
      (.mock(), Self.emptyResponseData())
    }

    let tracker = CallOrderTracker()

    let transport = RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: MockProvider(interceptors: [
        OrderTrackingInterceptor(index: 0, callOrder: tracker),
        OrderTrackingInterceptor(index: 1, callOrder: tracker),
        OrderTrackingInterceptor(index: 2, callOrder: tracker),
      ]),
      store: .mock(),
      endpointURL: serverUrl
    )

    let responseStream = try transport.send(
      query: MockQuery.mock(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    )

    _ = try await responseStream.getAllValues()

    expect(tracker.order).to(equal([0, 1, 2]))
  }

  func test__interceptorChain__givenSingleInterceptor__shouldCallIt() async throws {
    await Self.registerRequestHandler(for: serverUrl) { _ in
      (.mock(), Self.emptyResponseData())
    }

    let tracker = CallOrderTracker()

    let transport = RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: MockProvider(interceptors: [
        OrderTrackingInterceptor(index: 0, callOrder: tracker),
      ]),
      store: .mock(),
      endpointURL: serverUrl
    )

    let responseStream = try transport.send(
      query: MockQuery.mock(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    )

    _ = try await responseStream.getAllValues()

    expect(tracker.order).to(equal([0]))
  }

  // MARK: - Content-Type Response Tests

  /// Helper that sends a query through a full transport with the given response headers
  /// and returns the parsed result.
  private func sendQueryWithResponseHeaders(
    _ headerFields: [String: String]?,
    responseData: Data? = nil
  ) async throws -> [GraphQLResponse<MockQuery<Hero>>] {
    let data = responseData ?? """
      {
        "data": {
          "__typename": "Hero",
          "name": "R2-D2"
        }
      }
      """.data(using: .utf8)!

    await Self.registerRequestHandler(for: serverUrl) { _ in
      (.mock(headerFields: headerFields), data)
    }

    let transport = RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: .mock(),
      endpointURL: serverUrl
    )

    return try await transport.send(
      query: MockQuery<Hero>(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()
  }

  // This test verifies that unknown content-types do not cause failures for standard
  // (non-multipart) GraphQL responses. There is no content-type checking on single-response
  // parsing, and this test ensures that existing behaviour does not change.
  func test__response__givenUnknownContentType__shouldNotFail() async throws {
    let results = try await sendQueryWithResponseHeaders(
      ["content-type": "unknown/type"]
    )

    expect(results).to(haveCount(1))
    expect(results.first?.data?.name).to(equal("R2-D2"))
  }

  func test__response__givenJSONContentType__shouldSucceed() async throws {
    let results = try await sendQueryWithResponseHeaders(
      ["content-type": "application/json"]
    )

    expect(results).to(haveCount(1))
    expect(results.first?.data?.name).to(equal("R2-D2"))
  }

  func test__response__givenGraphQLOverHTTPContentType__shouldSucceed() async throws {
    let results = try await sendQueryWithResponseHeaders(
      ["content-type": "application/graphql-response+json"]
    )

    expect(results).to(haveCount(1))
    expect(results.first?.data?.name).to(equal("R2-D2"))
  }

  func test__response__givenNoContentTypeHeader__shouldSucceed() async throws {
    let results = try await sendQueryWithResponseHeaders(nil)

    expect(results).to(haveCount(1))
    expect(results.first?.data?.name).to(equal("R2-D2"))
  }

  // MARK: - Cache Policy Tests

  private final class HeroSelectionSet: MockSelectionSet, @unchecked Sendable {
    override class var __selections: [Selection] {
      [
        .field("hero", HeroField.self)
      ]
    }

    var hero: HeroField? { __data["hero"] }

    final class HeroField: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("name", String.self),
        ]
      }

      var name: String { __data["name"] }
    }
  }

  private static let heroServerData: JSONObject = [
    "data": [
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ]
    ]
  ]

  /// Creates a MockNetworkTransport + ApolloClient backed by a MockGraphQLServer.
  private func makeClientWithMockServer() -> (ApolloClient, MockGraphQLServer, ApolloStore) {
    let mockServer = MockGraphQLServer()
    let store = ApolloStore()
    let transport = MockNetworkTransport(mockServer: mockServer, store: store)
    let client = ApolloClient(networkTransport: transport, store: store)
    return (client, mockServer, store)
  }

  func test__fetch__givenCacheFirst_withCachedData__shouldReturnFromCache() async throws {
    let (client, _, store) = makeClientWithMockServer()

    // Pre-populate cache
    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2"],
    ])

    // No server expectation — if the network is hit, it will throw unexpectedRequest
    let result = try await client.fetch(
      query: MockQuery<HeroSelectionSet>(),
      cachePolicy: .cacheFirst
    )

    expect(result.source).to(equal(.cache))
    expect(result.data?.hero?.name).to(equal("R2-D2"))
  }

  func test__fetch__givenCacheFirst_withNoCachedData__shouldFetchFromNetwork() async throws {
    let (client, mockServer, _) = makeClientWithMockServer()

    let serverExpectation = await mockServer.expect(MockQuery<HeroSelectionSet>.self) { @Sendable _ in
      Self.heroServerData
    }

    let result = try await client.fetch(
      query: MockQuery<HeroSelectionSet>(),
      cachePolicy: .cacheFirst
    )

    expect(result.source).to(equal(.server))
    expect(result.data?.hero?.name).to(equal("R2-D2"))

    await fulfillment(of: [serverExpectation])
  }

  func test__fetch__givenNetworkOnly_withCachedData__shouldFetchFromNetwork() async throws {
    let (client, mockServer, store) = makeClientWithMockServer()

    // Pre-populate cache with different data
    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "C-3PO"],
    ])

    let serverExpectation = await mockServer.expect(MockQuery<HeroSelectionSet>.self) { @Sendable _ in
      Self.heroServerData
    }

    let result = try await client.fetch(
      query: MockQuery<HeroSelectionSet>(),
      cachePolicy: .networkOnly
    )

    expect(result.source).to(equal(.server))
    expect(result.data?.hero?.name).to(equal("R2-D2"))

    await fulfillment(of: [serverExpectation])
  }

  func test__fetch__givenCacheOnly_withCachedData__shouldReturnFromCache() async throws {
    let (client, _, store) = makeClientWithMockServer()

    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2"],
    ])

    let result = try await client.fetch(
      query: MockQuery<HeroSelectionSet>(),
      cachePolicy: .cacheOnly
    )

    expect(result).toNot(beNil())
    expect(result?.source).to(equal(.cache))
    expect(result?.data?.hero?.name).to(equal("R2-D2"))
  }

  func test__fetch__givenCacheOnly_withNoCachedData__shouldReturnNil() async throws {
    let (client, _, _) = makeClientWithMockServer()

    let result = try await client.fetch(
      query: MockQuery<HeroSelectionSet>(),
      cachePolicy: .cacheOnly
    )

    expect(result).to(beNil())
  }

  func test__fetch__givenNetworkOnly__shouldWriteResultToCache() async throws {
    let (client, mockServer, store) = makeClientWithMockServer()

    let serverExpectation = await mockServer.expect(MockQuery<HeroSelectionSet>.self) { @Sendable _ in
      Self.heroServerData
    }

    _ = try await client.fetch(
      query: MockQuery<HeroSelectionSet>(),
      cachePolicy: .networkOnly
    )

    await fulfillment(of: [serverExpectation])

    // Verify data was written to cache by reading it back
    let cachedResult = try await client.fetch(
      query: MockQuery<HeroSelectionSet>(),
      cachePolicy: .cacheOnly
    )

    expect(cachedResult).toNot(beNil())
    expect(cachedResult?.source).to(equal(.cache))
    expect(cachedResult?.data?.hero?.name).to(equal("R2-D2"))
  }

  func test__fetch__givenNetworkFirst_whenNetworkFails__shouldFallBackToCache() async throws {
    let (client, _, store) = makeClientWithMockServer()

    // Pre-populate cache
    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2"],
    ])

    // No server expectation registered — network request will throw unexpectedRequest error
    // networkFirst should catch this and fall back to cache
    let result = try await client.fetch(
      query: MockQuery<HeroSelectionSet>(),
      cachePolicy: .networkFirst
    )

    expect(result.source).to(equal(.cache))
    expect(result.data?.hero?.name).to(equal("R2-D2"))
  }
}
