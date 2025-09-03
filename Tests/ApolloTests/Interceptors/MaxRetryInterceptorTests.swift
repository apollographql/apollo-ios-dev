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
    let testInterceptor: any GraphQLInterceptor
    let retryCount: Int

    init(testInterceptor: any GraphQLInterceptor, retryCount: Int) {
      self.testInterceptor = testInterceptor
      self.retryCount = retryCount
    }

    func graphQLInterceptors<Operation>(for operation: Operation) -> [any GraphQLInterceptor] where Operation : GraphQLOperation {
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

    await expect { try await results.getAllValues() }.to(throwError(ApolloClient.Error.noResults))
    expect(testInterceptor.timesRetryHasBeenCalled).to(equal(testInterceptor.timesToCallRetry))    
  }
  
  func testExponentialBackoffDoesNotBreakInterceptorChain() {
    // Test that exponential backoff preserves normal interceptor chain behavior
    class TestProvider: InterceptorProvider {
      let testInterceptor = RetryToCountThenSucceedInterceptor(timesToCallRetry: 2)
      let retryCount = 3
      
      let mockClient: MockURLSessionClient = {
        let client = MockURLSessionClient()
        client.jsonData = [:]
        client.response = HTTPURLResponse(url: TestURL.mockServer.url,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)
        return client
      }()
      
      func interceptors<Operation: GraphQLOperation>(
        for operation: Operation
      ) -> [any ApolloInterceptor] {
        let config = MaxRetryInterceptor.Configuration(
          maxRetries: self.retryCount,
          baseDelay: 0.001, // Very small delay to keep test fast
          multiplier: 2.0,
          maxDelay: 0.01,
          enableExponentialBackoff: true,
          enableJitter: false
        )
        return [
          MaxRetryInterceptor(configuration: config),
          self.testInterceptor,
          NetworkFetchInterceptor(client: self.mockClient),
          JSONResponseParsingInterceptor()
        ]
      }
    }

    let testProvider = TestProvider()
    let network = RequestChainNetworkTransport(interceptorProvider: testProvider,
                                               endpointURL: TestURL.mockServer.url)
    
    let expectation = self.expectation(description: "Request completed successfully")
    
    let operation = MockQuery.mock()
    _ = network.send(operation: operation) { result in
      defer {
        expectation.fulfill()
      }
      
      switch result {
      case .success:
        // Verify that the chain completed successfully even with exponential backoff
        XCTAssertEqual(testProvider.testInterceptor.timesRetryHasBeenCalled, testProvider.testInterceptor.timesToCallRetry)
      case .failure(let error):
        XCTFail("Chain should have succeeded with exponential backoff: \(error)")
      }
    }
    
    self.wait(for: [expectation], timeout: 2)
  }
  
  func testExponentialBackoffPreservesErrorHandling() {
    // Test that exponential backoff doesn't interfere with proper error propagation
    class TestProvider: InterceptorProvider {
      let testInterceptor = BlindRetryingTestInterceptor()
      let retryCount = 2
      
      func interceptors<Operation: GraphQLOperation>(
        for operation: Operation
      ) -> [any ApolloInterceptor] {
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
          self.testInterceptor
        ]
      }
    }

    let testProvider = TestProvider()
    let network = RequestChainNetworkTransport(interceptorProvider: testProvider,
                                               endpointURL: TestURL.mockServer.url)
    
    let expectation = self.expectation(description: "Request failed as expected")
    
    let operation = MockQuery.mock()
    _ = network.send(operation: operation) { result in
      defer {
        expectation.fulfill()
      }
      
      switch result {
      case .success:
        XCTFail("This should not have succeeded")
      case .failure(let error):
        // Verify that the correct error is propagated even with exponential backoff
        guard case MaxRetryInterceptor.RetryError.hitMaxRetryCount(let count, _) = error else {
          XCTFail("Unexpected error type: \(error)")
          return
        }
        XCTAssertEqual(count, testProvider.retryCount)
        // Verify that retries still happened correctly
        XCTAssertEqual(testProvider.testInterceptor.hitCount, testProvider.retryCount + 1)
      }
    }
    
    self.wait(for: [expectation], timeout: 2)
  }
}
