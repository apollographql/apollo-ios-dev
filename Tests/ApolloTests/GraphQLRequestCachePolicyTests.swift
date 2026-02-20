import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

/// Tests for the cache policy conversion from FetchBehavior to URLRequest.CachePolicy
class GraphQLRequestCachePolicyTests: XCTestCase {

  // MARK: - Standard Cache Policies

  func test__cachePolicy__givenCacheOnly__shouldReturnCacheDataDontLoad() throws {
    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .CacheOnly,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.returnCacheDataDontLoad))
  }

  func test__cachePolicy__givenCacheAndNetwork__shouldReloadIgnoringLocalCache() throws {
    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .CacheAndNetwork,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
  }

  func test__cachePolicy__givenCacheFirst__shouldUseProtocolCachePolicy() throws {
    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .CacheFirst,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.useProtocolCachePolicy))
  }

  func test__cachePolicy__givenNetworkFirst__shouldReloadIgnoringLocalCache() throws {
    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .NetworkFirst,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
  }

  func test__cachePolicy__givenNetworkOnly__shouldReloadIgnoringLocalCache() throws {
    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .NetworkOnly,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
  }

  // MARK: - Custom FetchBehavior Combinations

  func test__cachePolicy__givenCustom_onNetworkFailure_never__shouldReloadIgnoringLocalCache() throws {
    // This is an undefined/impossible combination - should use safest fallback
    let customBehavior = FetchBehavior(
      cacheRead: .onNetworkFailure,
      networkFetch: .never
    )

    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: customBehavior,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
  }

  func test__cachePolicy__givenCustom_onNetworkFailure_onCacheMiss__shouldReloadIgnoringLocalCache() throws {
    // This is an undefined/impossible combination - should use safest fallback
    let customBehavior = FetchBehavior(
      cacheRead: .onNetworkFailure,
      networkFetch: .onCacheMiss
    )

    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: customBehavior,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
  }

  func test__cachePolicy__givenCustom_never_never__shouldReloadIgnoringLocalCache() throws {
    // This is an undefined/impossible combination - should use safest fallback
    let customBehavior = FetchBehavior(
      cacheRead: .never,
      networkFetch: .never
    )

    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: customBehavior,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
  }

  func test__cachePolicy__givenCustom_never_onCacheMiss__shouldReloadIgnoringLocalCache() throws {
    // This is an undefined/impossible combination - should use safest fallback
    let customBehavior = FetchBehavior(
      cacheRead: .never,
      networkFetch: .onCacheMiss
    )

    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: customBehavior,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
  }

  // MARK: - Different Operation Types

  func test__cachePolicy__givenMutation_withNetworkOnly__shouldReloadIgnoringLocalCache() throws {
    let subject = JSONRequest.mock(
      operation: MockMutation.mock(),
      fetchBehavior: .NetworkOnly,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
  }

  func test__cachePolicy__givenSubscription_withNetworkOnly__shouldReloadIgnoringLocalCache() throws {
    let subject = JSONRequest.mock(
      operation: MockSubscription.mock(),
      fetchBehavior: .NetworkOnly,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
  }

  // MARK: - Cache Policy Persistence Across Request Modifications

  func test__cachePolicy__shouldPersistAfterAddingHeaders() throws {
    var subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .CacheFirst,
      graphQLEndpoint: TestURL.mockServer.url
    )

    subject.addHeader(name: "Authorization", value: "Bearer token")
    subject.addHeaders(["Custom-Header": "CustomValue"])

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.useProtocolCachePolicy))
    expect(urlRequest.allHTTPHeaderFields?["Authorization"]).to(equal("Bearer token"))
    expect(urlRequest.allHTTPHeaderFields?["Custom-Header"]).to(equal("CustomValue"))
  }

  func test__cachePolicy__shouldPersistWithCustomTimeout() throws {
    var subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .NetworkFirst,
      graphQLEndpoint: TestURL.mockServer.url
    )

    subject.requestTimeout = 30.0

    let urlRequest = try subject.toURLRequest()

    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
    expect(urlRequest.timeoutInterval).to(equal(30.0))
  }

  // MARK: - Ensuring URLCache Doesn't Interfere

  func test__cachePolicy__givenCacheOnly__urlShouldNotFetchFromNetwork() throws {
    // CacheOnly should prevent network fetch entirely
    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .CacheOnly,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    // .returnCacheDataDontLoad ensures the URLSession won't make a network request
    expect(urlRequest.cachePolicy).to(equal(.returnCacheDataDontLoad))
  }

  func test__cachePolicy__givenCacheAndNetwork__urlShouldAlwaysFetchFromNetwork() throws {
    // CacheAndNetwork should always fetch from network (Apollo cache is separate)
    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .CacheAndNetwork,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    // .reloadIgnoringLocalCacheData ensures fresh network fetch
    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
  }

  func test__cachePolicy__givenNetworkOnly__urlShouldBypassCache() throws {
    // NetworkOnly should completely bypass URL cache
    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .NetworkOnly,
      graphQLEndpoint: TestURL.mockServer.url
    )

    let urlRequest = try subject.toURLRequest()

    // .reloadIgnoringLocalCacheData ensures URL cache is bypassed
    expect(urlRequest.cachePolicy).to(equal(.reloadIgnoringLocalCacheData))
  }

  // MARK: - Verify Default Request Configuration

  func test__createDefaultRequest__shouldSetCachePolicy() throws {
    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .CacheFirst,
      graphQLEndpoint: TestURL.mockServer.url
    )

    // Test that createDefaultRequest (used by toURLRequest) sets cache policy
    let defaultRequest = subject.createDefaultRequest()

    expect(defaultRequest.cachePolicy).to(equal(.useProtocolCachePolicy))
  }

  func test__createDefaultRequest__shouldSetCachePolicyForAllBehaviors() throws {
    let behaviors: [(FetchBehavior, URLRequest.CachePolicy, String)] = [
      (.CacheOnly, .returnCacheDataDontLoad, "CacheOnly"),
      (.CacheAndNetwork, .reloadIgnoringLocalCacheData, "CacheAndNetwork"),
      (.CacheFirst, .useProtocolCachePolicy, "CacheFirst"),
      (.NetworkFirst, .reloadIgnoringLocalCacheData, "NetworkFirst"),
      (.NetworkOnly, .reloadIgnoringLocalCacheData, "NetworkOnly")
    ]

    for (fetchBehavior, expectedCachePolicy, description) in behaviors {
      let subject = JSONRequest.mock(
        operation: MockQuery.mock(),
        fetchBehavior: fetchBehavior,
        graphQLEndpoint: TestURL.mockServer.url
      )

      let urlRequest = try subject.toURLRequest()

      expect(urlRequest.cachePolicy)
        .to(
          equal(expectedCachePolicy),
          description: "Failed for \(description): expected \(expectedCachePolicy) but got \(urlRequest.cachePolicy)"
        )
    }
  }
}
