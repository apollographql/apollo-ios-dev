import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

class CacheDependentInterceptorTests: XCTestCase, CacheDependentTesting, MockResponseProvider {
  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  var cache: (any NormalizedCache)!
  var store: ApolloStore!

  override func setUp() async throws {
    try await super.setUp()

    cache = try await makeNormalizedCache()
    store = ApolloStore(cache: cache)
  }

  override func tearDown() async throws {
    await Self.cleanUpRequestHandlers()
    cache = nil
    store = nil

    try await super.tearDown()
  }

  #warning("Decide if we are going to implement error interceptor and then reenable this test.")
  func testChangingCachePolicyInErrorInterceptorWorks() async throws {
    throw XCTSkip()
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
    final class RerouteToCacheErrorInterceptor: ApolloErrorInterceptor {
      nonisolated(unsafe) var handledError: (any Error)?

      func intercept<Request>(
        error: any Error,
        request: Request,
        result: InterceptorResult<Request.Operation>?
      ) async throws -> GraphQLResult<Request.Operation.Data> where Request: GraphQLRequest {
        self.handledError = error

        guard error is ResponseCodeInterceptor.ResponseCodeError else {
          throw error
        }
        var request = request
        request.cachePolicy = .returnCacheDataDontFetch
        throw RequestChainRetry(request: request)
      }
    }

    struct TestProvider: MockInterceptorProvider {
      let store: ApolloStore
      let urlSession: MockURLSession = MockURLSession(responseProvider: CacheDependentInterceptorTests.self)

      init(store: ApolloStore) {
        self.store = store
      }

      let errorInterceptor = RerouteToCacheErrorInterceptor()

      func interceptors<Operation>(for operation: Operation) -> [any ApolloInterceptor]
      where Operation: GraphQLOperation {
        []
      }

      func errorInterceptor<Operation>(for operation: Operation) -> (any ApolloErrorInterceptor)?
      where Operation: GraphQLOperation {
        self.errorInterceptor
      }
    }

    await CacheDependentInterceptorTests.registerRequestHandler(for: TestURL.mockServer.url) { _ in
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

    let testProvider = TestProvider(store: self.store)
    let network = RequestChainNetworkTransport(
      interceptorProvider: testProvider,
      endpointURL: TestURL.mockServer.url
    )

    var responseCount = 0

    // Send the initial request ignoring cache data so it doesn't initially get the data from the cache.
    for try await response in try network.send(
      query: MockQuery<GivenSelectionSet>(),
      cachePolicy: .fetchIgnoringCacheData
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
