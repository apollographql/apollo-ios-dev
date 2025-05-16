import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

#warning(
  """
  TODO: Write new tests. This has changed so much, tests need to be completely new.
  To test:
  - Retrying
  - Cache reads and writes based on cache policy (and if source is cache)
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

  struct MockProvider: MockInterceptorProvider {
    var session: MockURLSession
    var interceptors: [any ApolloInterceptor]

    func urlSession<Operation>(for operation: Operation) -> any ApolloURLSession where Operation: GraphQLOperation {
      session
    }

    func interceptors<Operation: GraphQLOperation>(
      for operation: Operation
    ) -> [any ApolloInterceptor] {
      interceptors
    }
  }

  func emptyResponseData() -> Data {
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

  struct DelayInterceptor: ApolloInterceptor {
    let nanoseconds: UInt64

    init(_ nanoseconds: UInt64) {
      self.nanoseconds = nanoseconds
    }

    func intercept<Request>(
      request: Request,
      next: (Request) async throws -> InterceptorResultStream<Request.Operation>
    ) async throws -> InterceptorResultStream<Request.Operation> where Request: GraphQLRequest {
      try await Task.sleep(nanoseconds: nanoseconds)
      return try await next(request)
    }

  }

  // MARK: - Tests

  func test_send_givenNoDataChunkReturned_throwsNoResultsError() async throws {
    await Self.registerRequestHandler(for: serverUrl) { request -> (HTTPURLResponse, Data?) in
      (.mock(), nil)
    }

    let transport = RequestChainNetworkTransport(
      interceptorProvider: MockProvider(session: session, interceptors: []),
      endpointURL: serverUrl
    )

    let resultStream = try transport.send(query: MockQuery.mock(), cachePolicy: .default)

    await expect {
      try await resultStream.getAllValues()
    }.to(throwError(RequestChainError.noResults))
  }

  func test_send_givenNoParsingInterceptor_throwsMissingParsedResultError() async throws {
    await Self.registerRequestHandler(for: serverUrl) { request in
      (
        .mock(),
        self.emptyResponseData()
      )
    }

    let transport = RequestChainNetworkTransport(
      interceptorProvider: MockProvider(session: session, interceptors: []),
      endpointURL: serverUrl
    )

    let resultStream = try transport.send(query: MockQuery.mock(), cachePolicy: .default)

    await expect {
      try await resultStream.getAllValues()
    }.to(throwError(RequestChainError.missingParsedResult))
  }

  // MARK: - Error Interceptor Tests
  #warning("TODO: Kill this, or implement it's usage in Request Chain.")
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

  // MARK: - Cancellation tests

  func test__cancellingTask__propogatesTaskCancellationToInterceptors() async throws {
    await Self.registerRequestHandler(for: serverUrl) { request in
      (
        .mock(),
        self.emptyResponseData()
      )
    }

    let cancellationInterceptor = CancellationTestingInterceptor()
    let retryInterceptor = BlindRetryingTestInterceptor()

    let transport = RequestChainNetworkTransport(
      interceptorProvider: MockProvider(
        session: session,
        interceptors: [
          cancellationInterceptor,
          retryInterceptor,
        ]
      ),
      endpointURL: serverUrl
    )

    let task = Task {
      let responseStream = try transport.send(query: MockQuery.mock(), cachePolicy: .fetchIgnoringCacheCompletely)

      for try await _ in responseStream {
        fail("This should not have gone through")
      }
    }

    task.cancel()

    await expect(cancellationInterceptor.hasBeenCancelled).toEventually(beTrue())
  }

//  await Self.registerRequestHandler(for: serverUrl) { request in
//    (
//      .mock(url: self.serverUrl),
//      """
//      {
//        "data": {
//          "__typename": "Hero",
//          "name": "R2-D2"
//        }
//      }
//      """.data(using: .utf8)
//    )
//  }
//
//  let transport = RequestChainNetworkTransport(
//    interceptorProvider: MockProvider(
//      session: self.session,
//      interceptors: [
//        DelayInterceptor(500_000_000),
//        JSONResponseParsingInterceptor(),
//      ]
//    ),
//    endpointURL: TestURL.mockServer.url
//  )

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
