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

    func graphQLInterceptors<Request>(for request: Request) -> [any ApolloInterceptor] where Request : GraphQLRequest {
      [
        MaxRetryInterceptor(maxRetriesAllowed: self.retryCount),
        self.testInterceptor
      ]
    }
  }

  // MARK: - Tests

  func testMaxRetryInterceptorErrorsAfterMaximumRetries() async throws {
    let testProvider = TestProvider(
      testInterceptor: BlindRetryingTestInterceptor(),
      retryCount: 15
    )

    let urlSession = MockURLSession(responseProvider: TestProvider.self)
    let network = RequestChainNetworkTransport(
      urlSession: urlSession,
      interceptorProvider: testProvider,
      store: .mock(),
      endpointURL: TestURL.mockServer.url
    )

    let operation = MockQuery.mock()
    let results = try network.send(
      query: operation,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration()
    )

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

    let urlSession = MockURLSession(responseProvider: TestProvider.self)
    let network = RequestChainNetworkTransport(
      urlSession: urlSession,
      interceptorProvider: testProvider,
      store: .mock(),
      endpointURL: TestURL.mockServer.url
    )

    let operation = MockQuery.mock()
    let results = try network.send(
      query: operation,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration()
    )

    await expect { try await results.getAllValues() }.to(throwError(RequestChainError.noResults))
    expect(testInterceptor.timesRetryHasBeenCalled).to(equal(testInterceptor.timesToCallRetry))    
  }
}
