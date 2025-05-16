import XCTest
import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

class MaxRetryInterceptorTests: XCTestCase {

  override func tearDown() async throws {
    await TestProvider.cleanUpRequestHandlers()

    try await super.tearDown()
  }

  final class TestProvider: InterceptorProvider, MockResponseProvider {
    let testInterceptor: any ApolloInterceptor
    let retryCount: Int

    init(testInterceptor: any ApolloInterceptor, retryCount: Int) {
      self.testInterceptor = testInterceptor
      self.retryCount = retryCount
    }

    func interceptors<Operation: GraphQLOperation>(
      for operation: Operation
    ) -> [any ApolloInterceptor] {
      [
        MaxRetryInterceptor(maxRetriesAllowed: self.retryCount),
        self.testInterceptor
      ]
    }

    func urlSession<Operation: GraphQLOperation>(for operation: Operation) -> any ApolloURLSession {
      MockURLSession(responseProvider: Self.self)
    }

    func cacheInterceptor<Operation: GraphQLOperation>(for operation: Operation) -> any CacheInterceptor {
      DefaultCacheInterceptor(store: ApolloStore(cache: NoCache()))
    }
  }

  // MARK: - Tests

  func testMaxRetryInterceptorErrorsAfterMaximumRetries() async throws {
    let testProvider = TestProvider(
      testInterceptor: BlindRetryingTestInterceptor(),
      retryCount: 15
    )
    let network = RequestChainNetworkTransport(interceptorProvider: testProvider,
                                               endpointURL: TestURL.mockServer.url)

    let operation = MockQuery.mock()
    let results = try network.send(query: operation, cachePolicy: .fetchIgnoringCacheCompletely)

    await expect {
      var iterator = results.makeAsyncIterator()
      _ = try await iterator.next()

    }.to(
      throwError(errorType: MaxRetryInterceptor.MaxRetriesError.self) { error in
        expect(error.count).to(equal(testProvider.retryCount))
        expect(error.operationName).to(equal(MockQuery<MockSelectionSet>.operationName))
      })
  }
  
  func testRetryInterceptorDoesNotErrorIfRetriedFewerThanMaxTimes() async throws {
    let testInterceptor = RetryToCountThenSucceedInterceptor(timesToCallRetry: 2)
    let testProvider = TestProvider(
      testInterceptor: testInterceptor,
      retryCount: 3
    )

    await TestProvider.registerRequestHandler(for: TestURL.mockServer.url) { request in
      return (
        HTTPURLResponse(
          url: TestURL.mockServer.url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!,
        Data()
      )
    }

    let network = RequestChainNetworkTransport(interceptorProvider: testProvider,
                                               endpointURL: TestURL.mockServer.url)

    let operation = MockQuery.mock()
    let results = try network.send(query: operation, cachePolicy: .fetchIgnoringCacheCompletely)

    await expect { try await results.getAllValues() }.to(throwError(RequestChainError.noResults))
    expect(testInterceptor.timesRetryHasBeenCalled).to(equal(testInterceptor.timesToCallRetry))    
  }
}
