@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

#warning(
  """
  TODO: Write new tests. This has changed so much, tests need to be completely new.
  To test:
  - Retrying
  - Cache reads and writes based on cache policy (and if source is cache)
  - cache only request gets sent through interceptors still
  - cache read after failed network fetch
  - Tests for subscriptions over HTTP
  """
)
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

  struct DelayInterceptor: GraphQLInterceptor {
    let nanoseconds: UInt64

    init(_ nanoseconds: UInt64) {
      self.nanoseconds = nanoseconds
    }

    func intercept<Request: GraphQLRequest>(
      request: Request,
      next: NextInterceptorFunction<Request>
    ) async throws -> InterceptorResultStream<Request> {
      try await Task.sleep(nanoseconds: nanoseconds)
      return await next(request)
    }

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

  //
  //  // MARK: `proceedAsync` Tests
  //
  //  @available(*, deprecated)
  //  struct SimpleForwardingInterceptor_deprecated: ApolloInterceptor {
  //    var id: String = UUID().uuidString
  //
  //    let expectation: XCTestExpectation
  //
  //    func interceptAsync<Operation>(
  //      chain: any Apollo.RequestChain,
  //      request: Apollo.HTTPRequest<Operation>,
  //      response: Apollo.HTTPResponse<Operation>?,
  //      completion: @Sendable @escaping (Result<Apollo.GraphQLResult<Operation.Data>, any Error>) -> Void
  //    ) {
  //      expectation.fulfill()
  //
  //      chain.proceedAsync(request: request, response: response, completion: completion)
  //    }
  //  }
  //
  //  struct SimpleForwardingInterceptor: ApolloInterceptor {
  //    var id: String = UUID().uuidString
  //
  //    let expectation: XCTestExpectation
  //
  //    func interceptAsync<Operation>(
  //      chain: any Apollo.RequestChain,
  //      request: Apollo.HTTPRequest<Operation>,
  //      response: Apollo.HTTPResponse<Operation>?,
  //      completion: @Sendable @escaping (Result<Apollo.GraphQLResult<Operation.Data>, any Error>) -> Void
  //    ) {
  //      expectation.fulfill()
  //
  //      chain.proceedAsync(
  //        request: request,
  //        response: response,
  //        interceptor: self,
  //        completion: completion
  //      )
  //    }
  //  }
  //
  //  @available(*, deprecated, message: "Testing deprecated function")
  //  func test__proceedAsync__givenInterceptors_usingDeprecatedFunction_shouldCallAllInterceptors() throws {
  //    let expectations = [
  //      expectation(description: "Interceptor 1 executed"),
  //      expectation(description: "Interceptor 2 executed"),
  //      expectation(description: "Interceptor 3 executed")
  //    ]
  //
  //    let requestChain = InterceptorRequestChain(interceptors: [
  //      SimpleForwardingInterceptor_deprecated(expectation: expectations[0]),
  //      SimpleForwardingInterceptor_deprecated(expectation: expectations[1]),
  //      SimpleForwardingInterceptor_deprecated(expectation: expectations[2])
  //    ])
  //
  //    let request = JSONRequest(
  //      operation: MockQuery<Hero>(),
  //      graphQLEndpoint: TestURL.mockServer.url,
  //      clientName: "test-client",
  //      clientVersion: "test-client-version"
  //    )
  //
  //    // when
  //    requestChain.kickoff(request: request) { result in }
  //
  //    // then
  //    wait(for: expectations, timeout: 1, enforceOrder: true)
  //  }
  //
  //  func test__proceedAsync__givenInterceptors_usingNewFunction_shouldCallAllInterceptors() throws {
  //    let expectations = [
  //      expectation(description: "Interceptor 1 executed"),
  //      expectation(description: "Interceptor 2 executed"),
  //      expectation(description: "Interceptor 3 executed")
  //    ]
  //
  //    let requestChain = InterceptorRequestChain(interceptors: [
  //      SimpleForwardingInterceptor(expectation: expectations[0]),
  //      SimpleForwardingInterceptor(expectation: expectations[1]),
  //      SimpleForwardingInterceptor(expectation: expectations[2])
  //    ])
  //
  //    let request = JSONRequest(
  //      operation: MockQuery<Hero>(),
  //      graphQLEndpoint: TestURL.mockServer.url,
  //      clientName: "test-client",
  //      clientVersion: "test-client-version"
  //    )
  //
  //    // when
  //    requestChain.kickoff(request: request) { result in }
  //
  //    // then
  //    wait(for: expectations, timeout: 1, enforceOrder: true)
  //  }
  //
  //  @available(*, deprecated, message: "Testing deprecated function")
  //  func test__proceedAsync__givenInterceptors_usingBothFunctions_shouldCallAllInterceptors() throws {
  //    let expectations = [
  //      expectation(description: "Interceptor 1 executed"),
  //      expectation(description: "Interceptor 2 executed"),
  //      expectation(description: "Interceptor 3 executed"),
  //      expectation(description: "Interceptor 4 executed"),
  //      expectation(description: "Interceptor 5 executed"),
  //      expectation(description: "Interceptor 6 executed"),
  //      expectation(description: "Interceptor 7 executed"),
  //      expectation(description: "Interceptor 8 executed")
  //    ]
  //
  //    let requestChain = InterceptorRequestChain(interceptors: [
  //      SimpleForwardingInterceptor(expectation: expectations[0]),
  //      SimpleForwardingInterceptor_deprecated(expectation: expectations[1]),
  //      SimpleForwardingInterceptor(expectation: expectations[2]),
  //      SimpleForwardingInterceptor_deprecated(expectation: expectations[3]),
  //      SimpleForwardingInterceptor_deprecated(expectation: expectations[4]),
  //      SimpleForwardingInterceptor(expectation: expectations[5]),
  //      SimpleForwardingInterceptor(expectation: expectations[6]),
  //      SimpleForwardingInterceptor_deprecated(expectation: expectations[7])
  //    ])
  //
  //    let request = JSONRequest(
  //      operation: MockQuery<Hero>(),
  //      graphQLEndpoint: TestURL.mockServer.url,
  //      clientName: "test-client",
  //      clientVersion: "test-client-version"
  //    )
  //
  //    // when
  //    requestChain.kickoff(request: request) { result in }
  //
  //    // then
  //    wait(for: expectations, timeout: 1, enforceOrder: true)
  //  }
  //
  //  // MARK: Response Tests
  //
  //  func test__response__givenUnsuccessfulStatusCode_shouldFail() throws {
  //    // given
  //    let client = MockURLSessionClient(
  //      response: .mock(
  //        url: TestURL.mockServer.url,
  //        statusCode: 500,
  //        httpVersion: nil,
  //        headerFields: nil
  //      ),
  //      data: """
  //      {
  //        "data": {
  //          "__typename": "Hero",
  //          "name": "R2-D2"
  //        }
  //      }
  //      """.data(using: .utf8)
  //    )
  //
  //    let provider = DefaultInterceptorProvider(
  //      client: client,
  //      store: ApolloStore()
  //    )
  //
  //    let transport = RequestChainNetworkTransport(
  //      interceptorProvider: provider,
  //      endpointURL: TestURL.mockServer.url
  //    )
  //
  //    let expectation = expectation(description: "Response received")
  //
  //    _ = transport.send(operation: MockQuery<Hero>()) { result in
  //      switch result {
  //      case .success:
  //        XCTFail("Unexpected response: \(result)")
  //
  //      case .failure:
  //        expectation.fulfill()
  //      }
  //    }
  //
  //    wait(for: [expectation], timeout: 1)
  //  }
  //
  //  // This test is odd because you might assume it would fail but there is no content-type checking on standard
  //  // GraphQL response parsing. So this test is here to ensure that existing behaviour does not change.
  //  func test__response__givenUnknownContentType_shouldNotFail() throws {
  //    // given
  //    let client = MockURLSessionClient(
  //      response: .mock(
  //        url: TestURL.mockServer.url,
  //        statusCode: 200,
  //        httpVersion: nil,
  //        headerFields: ["content-type": "unknown/type"]
  //      ),
  //      data: """
  //      {
  //        "data": {
  //          "__typename": "Hero",
  //          "name": "R2-D2"
  //        }
  //      }
  //      """.data(using: .utf8)
  //    )
  //
  //    let provider = DefaultInterceptorProvider(
  //      client: client,
  //      store: ApolloStore()
  //    )
  //
  //    let transport = RequestChainNetworkTransport(
  //      interceptorProvider: provider,
  //      endpointURL: TestURL.mockServer.url
  //    )
  //
  //    let expectation = expectation(description: "Response received")
  //
  //    _ = transport.send(operation: MockQuery<Hero>()) { result in
  //      switch result {
  //      case let .success(responseData):
  //        XCTAssertEqual(responseData.data?.__typename, "Hero")
  //        XCTAssertEqual(responseData.data?.name, "R2-D2")
  //
  //        expectation.fulfill()
  //
  //      case .failure:
  //        XCTFail("Unexpected response: \(result)")
  //      }
  //    }
  //
  //    wait(for: [expectation], timeout: 1)
  //  }
  //
  //  func test__response__givenJSONContentType_shouldSucceed() throws {
  //    // given
  //    let client = MockURLSessionClient(
  //      response: .mock(
  //        url: TestURL.mockServer.url,
  //        statusCode: 200,
  //        httpVersion: nil,
  //        headerFields: ["content-type": "application/json"]
  //      ),
  //      data: """
  //      {
  //        "data": {
  //          "__typename": "Hero",
  //          "name": "R2-D2"
  //        }
  //      }
  //      """.data(using: .utf8)
  //    )
  //
  //    let provider = DefaultInterceptorProvider(
  //      client: client,
  //      store: ApolloStore()
  //    )
  //
  //    let transport = RequestChainNetworkTransport(
  //      interceptorProvider: provider,
  //      endpointURL: TestURL.mockServer.url
  //    )
  //
  //    let expectation = expectation(description: "Response received")
  //
  //    _ = transport.send(operation: MockQuery<Hero>()) { result in
  //      switch result {
  //      case let .success(responseData):
  //        XCTAssertEqual(responseData.data?.__typename, "Hero")
  //        XCTAssertEqual(responseData.data?.name, "R2-D2")
  //
  //        expectation.fulfill()
  //
  //      case .failure:
  //        XCTFail("Unexpected response: \(result)")
  //      }
  //    }
  //
  //    wait(for: [expectation], timeout: 1)
  //  }
  //
  //  func test__response__givenGraphQLOverHTTPContentType_shouldSucceed() throws {
  //    // given
  //    let client = MockURLSessionClient(
  //      response: .mock(
  //        url: TestURL.mockServer.url,
  //        statusCode: 200,
  //        httpVersion: nil,
  //        headerFields: ["content-type": "application/graphql-response+json"]
  //      ),
  //      data: """
  //      {
  //        "data": {
  //          "__typename": "Hero",
  //          "name": "R2-D2"
  //        }
  //      }
  //      """.data(using: .utf8)
  //    )
  //
  //    let provider = DefaultInterceptorProvider(
  //      client: client,
  //      store: ApolloStore()
  //    )
  //
  //    let transport = RequestChainNetworkTransport(
  //      interceptorProvider: provider,
  //      endpointURL: TestURL.mockServer.url
  //    )
  //
  //    let expectation = expectation(description: "Response received")
  //
  //    _ = transport.send(operation: MockQuery<Hero>()) { result in
  //      switch result {
  //      case let .success(responseData):
  //        XCTAssertEqual(responseData.data?.__typename, "Hero")
  //        XCTAssertEqual(responseData.data?.name, "R2-D2")
  //
  //        expectation.fulfill()
  //
  //      case .failure:
  //        XCTFail("Unexpected response: \(result)")
  //      }
  //    }
  //
  //    wait(for: [expectation], timeout: 1)
  //  }
}
