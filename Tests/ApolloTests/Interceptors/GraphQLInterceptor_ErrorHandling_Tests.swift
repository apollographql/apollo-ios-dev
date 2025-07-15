import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

class GraphQLInterceptor_ErrorHandling_Tests: XCTestCase, CacheDependentTesting, MockResponseProvider {
  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  var store: ApolloStore!
  var session: MockURLSession!

  override func setUp() async throws {
    try await super.setUp()

    store = try await makeTestStore()
    session = MockURLSession(responseProvider: Self.self)
  }

  override func tearDown() async throws {
    await Self.cleanUpRequestHandlers()
    session = nil
    store = nil

    try await super.tearDown()
  }

  // MARK: - Tests

  func test__errorInterceptor__givenNextInterceptorThrowsBeforeCallingNext__mapErrorIsCalledWithThrownError()
    async throws
  {
    // given
    actor ErrorInterceptor: GraphQLInterceptor {
      nonisolated(unsafe) var handledError: (any Error)?

      func intercept<Request>(
        request: Request,
        next: (Request) async -> InterceptorResultStream<Request>
      ) async throws -> InterceptorResultStream<Request> where Request: GraphQLRequest {
        return await next(request).mapErrors { error in
          self.handledError = error

          throw error
        }
      }
    }

    struct ThrowErrorInterceptor: HTTPInterceptor {
      func intercept(
        request: URLRequest,
        next: (URLRequest) async throws -> HTTPResponse
      ) async throws -> HTTPResponse {
        throw TestError()
      }
    }

    struct TestProvider: InterceptorProvider {
      let errorInterceptor = ErrorInterceptor()

      func graphQLInterceptors<Operation: GraphQLOperation>(for operation: Operation) -> [any GraphQLInterceptor] {
        return [
          errorInterceptor
        ]
      }

      func httpInterceptors<Operation>(for operation: Operation) -> [any HTTPInterceptor] where Operation : GraphQLOperation {
        return [
          ThrowErrorInterceptor()
        ]
      }
    }

    let testProvider = TestProvider()
    let network = RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: testProvider,
      store: store,
      endpointURL: TestURL.mockServer.url
    )

    // when
    let resultStream = try network.send(
      query: MockQuery<MockSelectionSet>(),
      fetchBehavior: FetchBehavior.NetworkOnly,
      requestConfiguration: RequestConfiguration()
    )

    await expect {
      try await resultStream.getAllValues()
    }.to(throwError(TestError()))

    expect(testProvider.errorInterceptor.handledError as? TestError).toNot(beNil())
  }


  func test__errorInterceptor__givenHTTPInterceptorThrowsBeforeCallingNext__mapErrorIsCalledWithThrownError()
    async throws
  {
    // given
    actor ErrorInterceptor: GraphQLInterceptor {
      nonisolated(unsafe) var handledError: (any Error)?

      func intercept<Request>(
        request: Request,
        next: (Request) async -> InterceptorResultStream<Request>
      ) async throws -> InterceptorResultStream<Request> where Request: GraphQLRequest {
        return await next(request).mapErrors { error in
          self.handledError = error

          throw error
        }
      }
    }

    struct ThrowErrorInterceptor: HTTPInterceptor {
      func intercept(
        request: URLRequest,
        next: (URLRequest) async throws -> HTTPResponse
      ) async throws -> HTTPResponse {
        throw TestError()
      }
    }

    struct TestProvider: InterceptorProvider {
      let errorInterceptor = ErrorInterceptor()

      func graphQLInterceptors<Operation: GraphQLOperation>(for operation: Operation) -> [any GraphQLInterceptor] {
        return [
          errorInterceptor
        ]
      }

      func httpInterceptors<Operation>(for operation: Operation) -> [any HTTPInterceptor] where Operation : GraphQLOperation {
        return [
          ThrowErrorInterceptor()
        ]
      }
    }

    let testProvider = TestProvider()
    let network = RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: testProvider,
      store: store,
      endpointURL: TestURL.mockServer.url
    )

    // when
    let resultStream = try network.send(
      query: MockQuery<MockSelectionSet>(),
      fetchBehavior: FetchBehavior.NetworkOnly,
      requestConfiguration: RequestConfiguration()
    )

    await expect {
      try await resultStream.getAllValues()
    }.to(throwError(TestError()))

    expect(testProvider.errorInterceptor.handledError as? TestError).toNot(beNil())
  }

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
    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid", "name": "R2-D2"],
    ])

    /// This interceptor will reroute anything that fails with a response code error to retry hitting only the cache
    final class RerouteToCacheErrorInterceptor: GraphQLInterceptor {
      nonisolated(unsafe) var handledError: (any Error)?

      func intercept<Request: GraphQLRequest>(
        request: Request,
        next: NextInterceptorFunction<Request>
      ) async throws -> InterceptorResultStream<Request> {
        return await next(request).mapErrors { error in
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

      func graphQLInterceptors<Operation: GraphQLOperation>(for operation: Operation) -> [any GraphQLInterceptor] {
        DefaultInterceptorProvider.shared.graphQLInterceptors(for: operation) + [
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
        """
        {
          "errors": [{
            "message": "Bad request, could not start execution!"
          }]
        }
        """.data(using: .utf8)
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
      expect(response.source).to(equal(GraphQLResponse<MockQuery<GivenSelectionSet>>.Source.cache))
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
