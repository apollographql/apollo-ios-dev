import Foundation

/// A protocol that a type can conform to to provide mock responses to a ``MockURLSession``.
///
/// Typically an `XCTestCase` will conform to this protocol directly.
///
/// - Important: To ensure test isolation, requests handlers must be cleaned up after each
/// individual test by calling `Self.cleanUpRequestHandlers()`.
///
/// This is an example of how an `XCTestCase` should use this protocol.
///
/// ```
/// class MyTests: XCTestCase, MockResponseProvider {
///
///   var session: MockURLSession!
///
///   override func setUp() async throws {
///     try await super.setUp()
///
///     session = MockURLSession(requestProvider: Self.self)
///   }
///
///   override func tearDown() async throws {
///     await Self.cleanUpRequestHandlers()
///     session = nil
///
///     try await super.tearDown()
///   }
///
///   func testThatMocksAResponse() async throws {
///     let url = URL(string: "www.test.com")!
///     let responseStrings: [String] = [
///       ... // An array of strings for each multipart response chunk in your mocked response.
///     ]
///     await Self.registerRequestHandler(for: url) { request in
///       let response = HTTPURLResponse(
///         url: url,
///         statusCode: 200,
///         httpVersion: nil,
///         headerFields: nil
///       )
///
///       let stream = AsyncThrowingStream { continuation in
///         for string in responseStrings {
///           continuation.yield(string.data(using: .utf8)!)
///         }
///         continuation.finish()
///       }
///
///       return (response. stream)
///     }
///
///     // Send mockRequest
///     let (dataStream, response) = try await self.session.bytes(for: request, delegate: nil)
///
///     for try await chunk in dataStream.chunks {
///       let chunkString = String(data: chunk, encoding: .utf8)
///
///       ... // test assertions on response
///     }
///   }
/// ```
public protocol MockResponseProvider {
  typealias MultiResponseHandler = @Sendable (URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, any Error>?)
  typealias SingleResponseHandler = @Sendable (URLRequest) async throws -> (response: HTTPURLResponse, Data?)
}

extension MockResponseProvider {

  public static func registerRequestHandler(for url: URL, handler: @escaping MultiResponseHandler) async {
    await requestStorage.registerRequestHandler(for: Self.self, url: url, handler: handler)
  }

  public static func registerRequestHandler(for url: URL, handler: @escaping SingleResponseHandler) async {
    await requestStorage.registerRequestHandler(for: Self.self, url: url, handler: { request in
      let (response, data) = try await handler(request)
      nonisolated(unsafe) var didYieldData = false

      let stream = AsyncThrowingStream<Data, any Error> {
        if didYieldData {
          return nil
        }

        didYieldData = true
        return data
      }

      return (response, stream)
    })
  }

  public static func requestHandler(for url: URL) async -> MultiResponseHandler? {
    await requestStorage.requestHandler(for: Self.self, url: url)
  }

  /// Removes all request handlers for the provider type.
  ///
  /// - Important: To ensure test isolation, requests handlers must be cleaned up after each
  /// individual test.
  public static func cleanUpRequestHandlers() async {
    await requestStorage.removeRequestHandlers(for: Self.self)
  }
}

fileprivate let requestStorage = RequestStorage()
fileprivate actor RequestStorage {
  private var providers: [ObjectIdentifier: [URL: MockResponseProvider.MultiResponseHandler]] = [:]

  func registerRequestHandler(
    for type: Any.Type,
    url: URL,
    handler: @escaping MockResponseProvider.MultiResponseHandler
  ) {
    let typeId = ObjectIdentifier(type)
    var handlers = providers[typeId, default: [:]]
    handlers[url] = handler
    providers[typeId] = handlers
  }

  func requestHandler(for type: Any.Type, url: URL) -> MockResponseProvider.MultiResponseHandler? {
    providers[ObjectIdentifier(type)]?[url]
  }

  func removeRequestHandlers(for type: Any.Type) {
    providers[ObjectIdentifier(type)] = nil
  }
}
