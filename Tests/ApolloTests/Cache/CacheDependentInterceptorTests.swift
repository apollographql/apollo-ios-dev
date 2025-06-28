import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

class GraphQLInterceptor_ErrorHandling_Tests: XCTestCase, CacheDependentTesting, MockResponseProvider {
  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  var cache: (any NormalizedCache)!
  var store: ApolloStore!
  var session: MockURLSession!

  override func setUp() async throws {
    try await super.setUp()

    cache = try await makeNormalizedCache()
    store = ApolloStore(cache: cache)
    session = MockURLSession(responseProvider: Self.self)
  }

  override func tearDown() async throws {
    await Self.cleanUpRequestHandlers()
    session = nil
    cache = nil
    store = nil

    try await super.tearDown()
  }

  // MARK: - Tests
  #warning("TODO: Refactor these tests")
  //
  //  func test__send__ErrorInterceptorGetsCalledAfterAnErrorIsReceived() {
  //    class ErrorInterceptor: ApolloErrorInterceptor {
  //      var error: (any Error)? = nil
  //
  //      func handleErrorAsync<Operation: GraphQLOperation>(
  //        error: any Error,
  //          chain: any RequestChain,
  //          request: HTTPRequest<Operation>,
  //          response: HTTPResponse<Operation>?,
  //          completion: @escaping (Result<GraphQLResult<Operation.Data>, any Error>) -> Void) {
  //
  //        self.error = error
  //        completion(.failure(error))
  //      }
  //    }
  //
  //    class TestProvider: InterceptorProvider {
  //      let errorInterceptor = ErrorInterceptor()
  //      func interceptors<Operation: GraphQLOperation>(
  //        for operation: Operation
  //      ) -> [any ApolloInterceptor] {
  //        return [
  //          // An interceptor which will error without a response
  //          AutomaticPersistedQueryInterceptor()
  //        ]
  //      }
  //
  //      func additionalErrorInterceptor<Operation: GraphQLOperation>(for operation: Operation) -> (any ApolloErrorInterceptor)? {
  //        return self.errorInterceptor
  //      }
  //    }
  //
  //    let provider = TestProvider()
  //    let transport = RequestChainNetworkTransport(interceptorProvider: provider,
  //                                                 endpointURL: TestURL.mockServer.url,
  //                                                 autoPersistQueries: true)
  //
  //    let expectation = self.expectation(description: "Hero name query complete")
  //    _ = transport.send(operation: MockQuery.mock()) { result in
  //      defer {
  //        expectation.fulfill()
  //      }
  //      switch result {
  //      case .success:
  //        XCTFail("This should not have succeeded")
  //      case .failure(let error):
  //        switch error {
  //        case AutomaticPersistedQueryInterceptor.APQError.noParsedResponse:
  //          // This is what we want.
  //          break
  //        default:
  //          XCTFail("Unexpected error: \(error)")
  //        }
  //      }
  //    }
  //
  //    self.wait(for: [expectation], timeout: 1)
  //
  //    switch provider.errorInterceptor.error {
  //    case .some(let error):
  //      switch error {
  //      case AutomaticPersistedQueryInterceptor.APQError.noParsedResponse:
  //        // Again, this is what we expect.
  //        break
  //      default:
  //        XCTFail("Unexpected error on the interceptor: \(error)")
  //      }
  //    case .none:
  //      XCTFail("Error interceptor did not receive an error!")
  //    }
  //  }
  //
  //  func test__upload__ErrorInterceptorGetsCalledAfterAnErrorIsReceived() throws {
  //    class ErrorInterceptor: ApolloErrorInterceptor {
  //      var error: (any Error)? = nil
  //
  //      func handleErrorAsync<Operation: GraphQLOperation>(
  //        error: any Error,
  //          chain: any RequestChain,
  //          request: HTTPRequest<Operation>,
  //          response: HTTPResponse<Operation>?,
  //          completion: @escaping (Result<GraphQLResult<Operation.Data>, any Error>) -> Void) {
  //
  //        self.error = error
  //        completion(.failure(error))
  //      }
  //    }
  //
  //    class TestProvider: InterceptorProvider {
  //      let errorInterceptor = ErrorInterceptor()
  //      func interceptors<Operation: GraphQLOperation>(
  //        for operation: Operation
  //      ) -> [any ApolloInterceptor] {
  //        return [
  //          // An interceptor which will error without a response
  //          ResponseCodeInterceptor()
  //        ]
  //      }
  //
  //      func additionalErrorInterceptor<Operation: GraphQLOperation>(for operation: Operation) -> (any ApolloErrorInterceptor)? {
  //        return self.errorInterceptor
  //      }
  //    }
  //
  //    let provider = TestProvider()
  //    let transport = RequestChainNetworkTransport(interceptorProvider: provider,
  //                                                 endpointURL: TestURL.mockServer.url,
  //                                                 autoPersistQueries: true)
  //
  //    let fileURL = TestFileHelper.fileURLForFile(named: "a", extension: "txt")
  //    let file = try GraphQLFile(
  //      fieldName: "file",
  //      originalName: "a.txt",
  //      fileURL: fileURL
  //    )
  //
  //    let expectation = self.expectation(description: "Hero name query complete")
  //    _ = transport.upload(operation: MockQuery.mock(), files: [file], context: nil) { result in
  //      defer {
  //        expectation.fulfill()
  //      }
  //      switch result {
  //      case .success:
  //        XCTFail("This should not have succeeded")
  //      case .failure(let error):
  //        switch error {
  //        case ResponseCodeInterceptor.ResponseCodeError.invalidResponseCode:
  //          // This is what we want.
  //          break
  //        default:
  //          XCTFail("Unexpected error: \(error)")
  //        }
  //      }
  //    }
  //
  //    self.wait(for: [expectation], timeout: 1)
  //
  //    switch provider.errorInterceptor.error {
  //    case .some(let error):
  //      switch error {
  //      case ResponseCodeInterceptor.ResponseCodeError.invalidResponseCode:
  //        // Again, this is what we expect.
  //        break
  //      default:
  //        XCTFail("Unexpected error on the interceptor: \(error)")
  //      }
  //    case .none:
  //      XCTFail("Error interceptor did not receive an error!")
  //    }
  //  }
  //
  //  func testErrorInterceptorGetsCalledInDefaultInterceptorProviderSubclass() {
  //    class ErrorInterceptor: ApolloErrorInterceptor {
  //      var error: (any Error)? = nil
  //
  //      func handleErrorAsync<Operation: GraphQLOperation>(
  //        error: any Error,
  //        chain: any RequestChain,
  //        request: HTTPRequest<Operation>,
  //        response: HTTPResponse<Operation>?,
  //        completion: @escaping (Result<GraphQLResult<Operation.Data>, any Error>) -> Void) {
  //
  //        self.error = error
  //        completion(.failure(error))
  //      }
  //    }
  //
  //    class TestProvider: DefaultInterceptorProvider {
  //      let errorInterceptor = ErrorInterceptor()
  //
  //      override func interceptors<Operation: GraphQLOperation>(
  //        for operation: Operation
  //      ) -> [any ApolloInterceptor] {
  //        return [
  //          // An interceptor which will error without a response
  //          AutomaticPersistedQueryInterceptor()
  //        ]
  //      }
  //
  //      override func additionalErrorInterceptor<Operation: GraphQLOperation>(for operation: Operation) -> (any ApolloErrorInterceptor)? {
  //        return self.errorInterceptor
  //      }
  //    }
  //
  //    let provider = TestProvider(store: ApolloStore())
  //    let transport = RequestChainNetworkTransport(interceptorProvider: provider,
  //                                                 endpointURL: TestURL.mockServer.url,
  //                                                 autoPersistQueries: true)
  //
  //    let expectation = self.expectation(description: "Hero name query complete")
  //    _ = transport.send(operation: MockQuery.mock()) { result in
  //      defer {
  //        expectation.fulfill()
  //      }
  //      switch result {
  //      case .success:
  //        XCTFail("This should not have succeeded")
  //      case .failure(let error):
  //        switch error {
  //        case AutomaticPersistedQueryInterceptor.APQError.noParsedResponse:
  //          // This is what we want.
  //          break
  //        default:
  //          XCTFail("Unexpected error: \(error)")
  //        }
  //      }
  //    }
  //
  //    self.wait(for: [expectation], timeout: 1)
  //
  //    switch provider.errorInterceptor.error {
  //    case .some(let error):
  //      switch error {
  //      case AutomaticPersistedQueryInterceptor.APQError.noParsedResponse:
  //        // Again, this is what we expect.
  //        break
  //      default:
  //        XCTFail("Unexpected error on the interceptor: \(error)")
  //      }
  //    case .none:
  //      XCTFail("Error interceptor did not receive an error!")
  //    }
  //  }
  //
  //  func test__error__givenGraphqlError_withoutData_shouldReturnError() {
  //    // given
  //    let client = MockURLSessionClient(
  //      response: .mock(
  //        url: TestURL.mockServer.url,
  //        statusCode: 200,
  //        httpVersion: nil,
  //        headerFields: nil
  //      ),
  //      data: """
  //      {
  //        "errors": [{
  //          "message": "Bad request, could not start execution!"
  //        }]
  //      }
  //      """.data(using: .utf8)
  //    )
  //
  //    let interceptorProvider = DefaultInterceptorProvider(client: client, store: ApolloStore())
  //    let interceptors = interceptorProvider.interceptors(for: MockQuery.mock())
  //    let requestChain = InterceptorRequestChain(interceptors: interceptors)
  //
  //    let expectation = expectation(description: "Response received")
  //
  //    let request = JSONRequest(
  //      operation: MockQuery<Hero>(),
  //      graphQLEndpoint: TestURL.mockServer.url,
  //      clientName: "test-client",
  //      clientVersion: "test-client-version"
  //    )
  //
  //    // when + then
  //    requestChain.kickoff(request: request) { result in
  //      defer {
  //        expectation.fulfill()
  //      }
  //
  //      switch (result) {
  //      case let .success(data):
  //        XCTAssertEqual(data.errors, [
  //          GraphQLError("Bad request, could not start execution!")
  //        ])
  //      case let .failure(error):
  //        XCTFail("Unexpected failure result - \(error)")
  //      }
  //    }
  //
  //    wait(for: [expectation], timeout: 1)
  //  }

  func test__interceptor__changingFetchBehaviorOnFailureAndRetrying_fetchBehaviorIsChanged() async throws {
    // given
    final class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      final class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    // Set up initial cache state
    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid", "name": "R2-D2"],
    ])

    /// This interceptor will reroute anything that fails with a response code error to retry hitting only the cache
    final class RerouteToCacheErrorInterceptor: ApolloInterceptor {
      nonisolated(unsafe) var handledError: (any Error)?

      func intercept<Request: GraphQLRequest>(
        request: Request,
        next: NextInterceptorFunction<Request>
      ) async throws -> InterceptorResultStream<GraphQLResponse<Request.Operation>> {

        do {
          return try await next(request)

        } catch {
          self.handledError = error
          guard error is ResponseCodeInterceptor.ResponseCodeError else {
            throw error
          }
          var request = request
          request.fetchBehavior = FetchBehavior.CacheOnly

          throw RequestChain.Retry(request: request)
        }
      }
    }

    struct TestProvider: InterceptorProvider {
      let errorInterceptor = RerouteToCacheErrorInterceptor()

      func graphQLInterceptors<Request>(for request: Request) -> [any ApolloInterceptor] where Request : GraphQLRequest {
        DefaultInterceptorProvider.shared.graphQLInterceptors(for: request) + [
          errorInterceptor
        ]
      }
    }

    await Self.registerRequestHandler(for: TestURL.mockServer.url) { _ in
      return (
        HTTPURLResponse(
          url: TestURL.mockServer.url,
          statusCode: 401,
          httpVersion: nil,
          headerFields: nil
        )!,
        Data()
      )
    }

    let testProvider = TestProvider()
    let network = RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: testProvider,
      store: store,
      endpointURL: TestURL.mockServer.url
    )

    var responseCount = 0

    // Send the initial request ignoring cache data so it doesn't initially get the data from the cache.
    for try await response in try network.send(
      query: MockQuery<GivenSelectionSet>(),
      fetchBehavior: FetchBehavior.NetworkOnly,
      requestConfiguration: RequestConfiguration()
    ) {
      responseCount += 1

      // Check that the final result is what we expected
      guard let heroName: String = response.data?.hero?.name else {
        XCTFail("Could not access hero name from returned result")
        return
      }

      expect(heroName).to(equal("R2-D2"))
      expect(response.source).to(equal(GraphQLResult<GivenSelectionSet>.Source.cache))
    }

    expect(responseCount).to(equal(1))

    // Validate that there was a handled error before we went to the cache and we didn't just go straight to the cache.
    guard let handledError = testProvider.errorInterceptor.handledError else {
      XCTFail("No error was handled!")
      return
    }

    switch handledError {
    case let error as ResponseCodeInterceptor.ResponseCodeError:
      XCTAssertEqual(error.response.statusCode, 401)
    default:
      XCTFail("Unexpected error on the additional error handler: \(handledError)")
    }
  }
}
