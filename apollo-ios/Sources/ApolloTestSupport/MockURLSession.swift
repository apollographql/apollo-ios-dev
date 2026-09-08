import Apollo
import Foundation

/// An `ApolloURLSession` that serves the responses registered with a ``MockResponseProvider`` instead of performing
/// network requests.
///
/// Use this to stub the network layer of an `ApolloClient` in tests. Because it replaces only the session, the rest
/// of the `RequestChain` — the interceptors, the response parsing, and the cache reads and writes — runs exactly as
/// it does in production. Responses are served through a `URLProtocol`, so multi-part response bodies are split into
/// chunks by the same code path a real response uses.
///
/// ```swift
/// class MyTests: XCTestCase, MockResponseProvider {
///
///   func testFetch() async throws {
///     let endpointURL = URL(string: "http://localhost/graphql")!
///
///     await Self.registerRequestHandler(for: endpointURL) { request in
///       let response = HTTPURLResponse(
///         url: endpointURL,
///         statusCode: 200,
///         httpVersion: nil,
///         headerFields: ["Content-Type": "application/json"]
///       )!
///       let body = #"{"data": {"hero": {"__typename": "Droid", "name": "R2-D2"}}}"#
///
///       return (response, Data(body.utf8))
///     }
///
///     let store = ApolloStore()
///     let client = ApolloClient(
///       networkTransport: RequestChainNetworkTransport(
///         urlSession: MockURLSession(responseProvider: Self.self),
///         interceptorProvider: DefaultInterceptorProvider.shared,
///         store: store,
///         endpointURL: endpointURL
///       ),
///       store: store
///     )
///
///     // ... assertions ...
///   }
/// }
/// ```
///
/// - Important: Request handlers are stored statically per ``MockResponseProvider`` type. To ensure test isolation,
/// call `Self.cleanUpRequestHandlers()` in your `tearDown()`.
///
/// - Note: This stubs `ApolloURLSession` only. It does not conform to `WebSocketURLSession`, so it cannot be used
/// with a `WebSocketTransport`. GraphQL subscriptions over HTTP can be stubbed by registering a `multipart/mixed`
/// response.
public struct MockURLSession: ApolloURLSession {

  private let session: URLSession

  /// Designated initializer.
  ///
  /// - Parameter responseProvider: The ``MockResponseProvider`` type whose registered request handlers should serve
  /// this session's responses. Typically the `XCTestCase` subclass running the test.
  public init<Provider: MockResponseProvider>(responseProvider: Provider.Type) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol<Provider>.self]

    self.session = URLSession(configuration: configuration)
  }

  public func chunks(
    for request: URLRequest
  ) async throws -> (any AsyncChunkSequence, URLResponse) {
    try await session.chunks(for: request)
  }

}
