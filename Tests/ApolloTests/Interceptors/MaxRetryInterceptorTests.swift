import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

class MaxRetryInterceptorTests: XCTestCase, MockResponseProvider  {

  override func tearDown() async throws {
    await Self.cleanUpRequestHandlers()

    try await super.tearDown()
  }

  final class TestProvider: InterceptorProvider {
    let testInterceptor: any GraphQLInterceptor
    let retryCount: Int

    init(testInterceptor: any GraphQLInterceptor, retryCount: Int) {
      self.testInterceptor = testInterceptor
      self.retryCount = retryCount
    }

    func graphQLInterceptors<Operation>(for operation: Operation) -> [any GraphQLInterceptor]
    where Operation: GraphQLOperation {
      [
        MaxRetryInterceptor(maxRetriesAllowed: self.retryCount),
        self.testInterceptor,
      ]
    }
  }

  // MARK: - Tests

  func testMaxRetryInterceptorErrorsAfterMaximumRetries() async throws {
    let testProvider = TestProvider(
      testInterceptor: BlindRetryingTestInterceptor(),
      retryCount: 15
    )

    let urlSession = MockURLSession(responseProvider: Self.self)
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
      }
    )
  }

  func testRetryInterceptorDoesNotErrorIfRetriedFewerThanMaxTimes() async throws {
    let testInterceptor = RetryToCountThenSucceedInterceptor(timesToCallRetry: 2)
    let testProvider = TestProvider(
      testInterceptor: testInterceptor,
      retryCount: 3
    )

    await Self.registerRequestHandler(for: TestURL.mockServer.url) { request in
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

    let urlSession = MockURLSession(responseProvider: Self.self)
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

    await expect { try await results.getAllValues() }.to(throwError(ApolloClient.Error.noResults))
    expect(testInterceptor.timesRetryHasBeenCalled).to(equal(testInterceptor.timesToCallRetry))
  }

  func testExponentialBackoffDoesNotBreakInterceptorChain() async throws {
    // Test that exponential backoff preserves normal interceptor chain behavior
    final class TestProvider: InterceptorProvider {
      let testInterceptor = RetryToCountThenSucceedInterceptor(timesToCallRetry: 2)
      let retryCount = 3

      func graphQLInterceptors<Operation>(for operation: Operation) -> [any GraphQLInterceptor]
      where Operation: GraphQLOperation {
        let config = MaxRetryInterceptor.Configuration(
          maxRetries: self.retryCount,
          baseDelay: 0.001,  // Very small delay to keep test fast
          multiplier: 2.0,
          maxDelay: 0.01,
          enableExponentialBackoff: true,
          enableJitter: false
        )
        return [
          MaxRetryInterceptor(configuration: config),
          testInterceptor
        ]
      }
    }

    let testProvider = TestProvider()
    let urlSession = MockURLSession(responseProvider: Self.self)
    let network = RequestChainNetworkTransport(
      urlSession: urlSession,
      interceptorProvider: testProvider,
      store: .mock(),
      endpointURL: TestURL.mockServer.url
    )

    let operation = MockQuery.mock()

    await Self.registerRequestHandler(for: TestURL.mockServer.url) { request in
      return (
        HTTPURLResponse(
          url: TestURL.mockServer.url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!,
        operation.defaultResponseData
      )
    }

    let results = try network.send(
      query: operation,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration()
    )

    await expect { try await results.getAllValues().count }.to(equal(1))
    expect(testProvider.testInterceptor.timesRetryHasBeenCalled)
      .to(equal(testProvider.testInterceptor.timesToCallRetry))
  }

  func testExponentialBackoffPreservesErrorHandling() async throws {
    // Test that exponential backoff doesn't interfere with proper error propagation
    final class TestProvider: InterceptorProvider {
      let testInterceptor = BlindRetryingTestInterceptor()
      let retryCount = 2

      func graphQLInterceptors<Operation>(for operation: Operation) -> [any GraphQLInterceptor]
      where Operation: GraphQLOperation {
        let config = MaxRetryInterceptor.Configuration(
          maxRetries: self.retryCount,
          baseDelay: 0.001,
          multiplier: 2.0,
          maxDelay: 0.01,
          enableExponentialBackoff: true,
          enableJitter: false
        )
        return [
          MaxRetryInterceptor(configuration: config),
          self.testInterceptor,
        ]
      }
    }

    let testProvider = TestProvider()
    let urlSession = MockURLSession(responseProvider: Self.self)
    let network = RequestChainNetworkTransport(
      urlSession: urlSession,
      interceptorProvider: testProvider,
      store: .mock(),
      endpointURL: TestURL.mockServer.url
    )

    let operation = MockQuery.mock()

    await Self.registerRequestHandler(for: TestURL.mockServer.url) { request in
      return (
        HTTPURLResponse(
          url: TestURL.mockServer.url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!,
        operation.defaultResponseData
      )
    }

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
      }
    )    
    expect(testProvider.testInterceptor.hitCount).to(equal(testProvider.retryCount + 1))
  }
}
