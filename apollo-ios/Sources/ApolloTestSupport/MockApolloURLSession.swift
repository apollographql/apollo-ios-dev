import Apollo
import Foundation

/// An `ApolloURLSession` that returns canned responses instead of performing network requests.
///
/// Use this to stub the network layer of an `ApolloClient` in tests. Because it replaces only the session, the rest of
/// the `RequestChain` — the interceptors, the response parsing, and the cache reads and writes — runs exactly as it
/// does in production.
///
/// ```swift
/// let session = MockApolloURLSession()
/// session.respond(with: .json("""
///   {"data": {"hero": {"__typename": "Droid", "name": "R2-D2"}}}
///   """))
///
/// let store = ApolloStore()
/// let client = ApolloClient(
///   networkTransport: RequestChainNetworkTransport(
///     urlSession: session,
///     interceptorProvider: DefaultInterceptorProvider.shared,
///     store: store,
///     endpointURL: URL(string: "http://localhost/graphql")!
///   ),
///   store: store
/// )
/// ```
///
/// - Note: Prefer stubbing the session over writing a `GraphQLInterceptor` that short-circuits the
/// `RequestChain`. A short-circuiting interceptor skips response parsing, so the result it supplies has not been
/// through the same code path as a real response.
public final class MockApolloURLSession: ApolloURLSession, @unchecked Sendable {

  /// A stubbed HTTP response.
  public struct Response: Sendable {

    /// The status code for the stubbed `HTTPURLResponse`.
    public var statusCode: Int

    /// The header fields for the stubbed `HTTPURLResponse`.
    public var headerFields: [String: String]

    /// The response body, split into the chunks emitted by the returned `AsyncChunkSequence`.
    ///
    /// A single-response operation should have exactly one chunk. For a multi-part response, each element is the
    /// payload of one part, with the `--boundary` delimiters already removed — the form the
    /// `ResponseParsingInterceptor` receives them in. Use ``multipart(parts:boundary:protocolSpec:statusCode:)``
    /// to build one rather than assembling the parts by hand.
    public var chunks: [Data]

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - statusCode: The status code for the stubbed `HTTPURLResponse`. Defaults to `200`.
    ///   - headerFields: The header fields for the stubbed `HTTPURLResponse`. Defaults to a JSON `Content-Type`.
    ///   - chunks: The response body, split into the chunks emitted by the returned `AsyncChunkSequence`.
    public init(
      statusCode: Int = 200,
      headerFields: [String: String] = ["Content-Type": "application/json"],
      chunks: [Data]
    ) {
      self.statusCode = statusCode
      self.headerFields = headerFields
      self.chunks = chunks
    }

    /// A single-chunk response with a JSON `Content-Type`.
    ///
    /// - Parameters:
    ///   - body: The response body.
    ///   - statusCode: The status code for the stubbed `HTTPURLResponse`. Defaults to `200`.
    /// - Returns: A ``Response`` emitting `body` as its only chunk.
    public static func json(_ body: Data, statusCode: Int = 200) -> Response {
      Response(
        statusCode: statusCode,
        headerFields: ["Content-Type": "application/json"],
        chunks: [body]
      )
    }

    /// A single-chunk response with a JSON `Content-Type`.
    ///
    /// - Parameters:
    ///   - body: The response body, encoded as UTF-8.
    ///   - statusCode: The status code for the stubbed `HTTPURLResponse`. Defaults to `200`.
    /// - Returns: A ``Response`` emitting `body` as its only chunk.
    public static func json(_ body: String, statusCode: Int = 200) -> Response {
      .json(Data(body.utf8), statusCode: statusCode)
    }

    /// A `multipart/mixed` response, used for HTTP subscriptions and operations using `@defer`.
    ///
    /// - Parameters:
    ///   - parts: The body of each part. A part is emitted as a chunk of the form
    ///   `content-type: application/json\r\n\r\n<part>`, matching what the `ResponseParsingInterceptor` receives
    ///   after the boundary delimiters are stripped from a real response.
    ///   - boundary: The multi-part boundary named in the `Content-Type` header. Defaults to `graphql`.
    ///   - protocolSpec: The protocol spec directive for the `Content-Type` header. Defaults to
    ///   ``ProtocolSpec/subscription``.
    ///   - statusCode: The status code for the stubbed `HTTPURLResponse`. Defaults to `200`.
    /// - Returns: A ``Response`` emitting one chunk per element of `parts`.
    public static func multipart(
      parts: [String],
      boundary: String = "graphql",
      protocolSpec: ProtocolSpec = .subscription,
      statusCode: Int = 200
    ) -> Response {
      Response(
        statusCode: statusCode,
        headerFields: [
          "Content-Type": "multipart/mixed;boundary=\(boundary);\(protocolSpec.directive)"
        ],
        chunks: parts.map { Data("content-type: application/json\r\n\r\n\($0)".utf8) }
      )
    }

    /// The multi-part protocol specs understood by Apollo's response parsing.
    public enum ProtocolSpec: Sendable {

      /// `subscriptionSpec=1.0` — GraphQL subscriptions over HTTP.
      case subscription

      /// `deferSpec=20220824` — GraphQL operations using the `@defer` directive.
      case deferred

      /// The `Content-Type` directive for the spec.
      public var directive: String {
        switch self {
        case .subscription: return "subscriptionSpec=1.0"
        case .deferred: return "deferSpec=20220824"
        }
      }
    }
  }

  /// What the session should do when a request is made.
  public enum Stub: Sendable {

    /// Return the given ``Response``.
    case response(Response)

    /// Throw the given error, as a failed network fetch would.
    case failure(any Swift.Error)
  }

  /// An error thrown by the ``MockApolloURLSession`` itself, rather than by one of its stubs.
  public enum Error: Swift.Error, LocalizedError, CustomStringConvertible {

    /// A request was made but no stub was registered to handle it.
    case noStubRegistered(URLRequest)

    /// A stub was found for the request, but an `HTTPURLResponse` could not be created for it. This happens when the
    /// request has no URL, or when the stub's status code or header fields are not valid.
    case couldNotCreateResponse(URLRequest)

    public var description: String {
      switch self {
      case .noStubRegistered(let request):
        return """
          MockApolloURLSession received a request for \(request.url?.absoluteString ?? "<no url>") but no stub was \
          registered to handle it. Register one with `respond(with:)`, `respond(handler:)`, `fail(with:)`, or \
          `enqueue(_:)`.
          """

      case .couldNotCreateResponse(let request):
        return """
          MockApolloURLSession could not create an HTTPURLResponse for the request to \
          \(request.url?.absoluteString ?? "<no url>"). Check that the request has a URL and that the stub's \
          status code and header fields are valid.
          """
      }
    }

    public var errorDescription: String? { description }
  }

  private let lock = NSLock()
  private var handler: (@Sendable (URLRequest) async throws -> Stub)?
  private var queue: [Stub] = []
  private var _receivedRequests: [URLRequest] = []

  /// The `URLRequest`s the session has received, in the order they were made.
  public var receivedRequests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return _receivedRequests
  }

  /// Designated initializer.
  ///
  /// A newly created session has no stubs. A request made before one is registered throws
  /// ``Error/noStubRegistered(_:)``.
  public init() {}

  // MARK: - Stubbing

  /// Responds to every request with the given ``Response``.
  ///
  /// Replaces any previously registered stub, handler, or queue.
  ///
  /// - Parameter response: The ``Response`` to return for every request.
  public func respond(with response: Response) {
    respond { _ in .response(response) }
  }

  /// Fails every request with the given error, as a failed network fetch would.
  ///
  /// Replaces any previously registered stub, handler, or queue.
  ///
  /// - Parameter error: The error to throw for every request.
  public func fail(with error: any Swift.Error) {
    respond { _ in .failure(error) }
  }

  /// Responds to each request by calling the given handler.
  ///
  /// Use this to vary the response by request, or to assert on the request as it is made. Replaces any previously
  /// registered stub, handler, or queue.
  ///
  /// - Parameter handler: Called for each request, returning the ``Stub`` to use for it.
  public func respond(handler: @escaping @Sendable (URLRequest) async throws -> Stub) {
    lock.lock()
    defer { lock.unlock() }

    self.handler = handler
    self.queue = []
  }

  /// Adds stubs to the queue of responses to be returned, in order, one per request.
  ///
  /// Use this for a sequence of requests that should receive different responses, such as a retried request.
  ///
  /// A queued stub takes precedence over one registered with ``respond(with:)``, ``fail(with:)``, or
  /// ``respond(handler:)``, which is used once the queue is exhausted. If there is no such stub, a request made after
  /// the queue is exhausted throws ``Error/noStubRegistered(_:)``.
  ///
  /// - Parameter stubs: The stubs to append to the queue.
  public func enqueue(_ stubs: Stub...) {
    lock.lock()
    defer { lock.unlock() }

    self.queue.append(contentsOf: stubs)
  }

  /// Removes all stubs and recorded requests.
  public func reset() {
    lock.lock()
    defer { lock.unlock() }

    handler = nil
    queue = []
    _receivedRequests = []
  }

  // MARK: - ApolloURLSession

  public func chunks(
    for request: URLRequest
  ) async throws -> (any AsyncChunkSequence, URLResponse) {
    try Task.checkCancellation()

    // Record the request and take the next stub under the lock, but call the handler outside of it — the handler is
    // async and may itself touch the session.
    let (nextStub, currentHandler) = lock.withLock {
      _receivedRequests.append(request)
      return (queue.isEmpty ? nil : queue.removeFirst(), self.handler)
    }

    let stub: Stub
    if let nextStub {
      stub = nextStub
    } else if let currentHandler {
      stub = try await currentHandler(request)
    } else {
      throw Error.noStubRegistered(request)
    }

    switch stub {
    case .failure(let error):
      throw error

    case .response(let response):
      guard
        let url = request.url,
        let httpResponse = HTTPURLResponse(
          url: url,
          statusCode: response.statusCode,
          httpVersion: "HTTP/1.1",
          headerFields: response.headerFields
        )
      else {
        throw Error.couldNotCreateResponse(request)
      }

      return (ChunkSequence(response.chunks), httpResponse)
    }
  }
}

// MARK: - ChunkSequence

extension MockApolloURLSession {

  /// An `AsyncChunkSequence` that emits a fixed list of chunks.
  ///
  /// Unlike a real response stream, the chunks are already split — no multi-part boundary parsing is performed.
  public struct ChunkSequence: AsyncChunkSequence {
    public typealias Element = Data

    private let chunks: [Data]

    /// Designated initializer.
    ///
    /// - Parameter chunks: The chunks to emit, in order.
    public init(_ chunks: [Data]) {
      self.chunks = chunks
    }

    public func makeAsyncIterator() -> AsyncIterator {
      AsyncIterator(chunks)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
      public typealias Element = Data

      private var remaining: [Data]

      init(_ chunks: [Data]) {
        self.remaining = chunks
      }

      public mutating func next() async throws -> Data? {
        try Task.checkCancellation()

        guard !remaining.isEmpty else { return nil }

        return remaining.removeFirst()
      }
    }
  }
}
