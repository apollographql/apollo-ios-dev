import Foundation
import ApolloWebSocket

/// A mock implementation of ``WebSocketTask`` for unit testing WebSocket interactions.
///
/// From the test's perspective, this mock acts as the **server**. Use ``emit(_:)`` to send
/// messages to the client, and read ``clientSentMessages`` to inspect what the client sent.
///
/// ```swift
/// let mock = MockWebSocketTask()
///
/// // Send a message to the client (as the server):
/// mock.emit(.string("{\"type\":\"connection_ack\"}"))
///
/// // Close the connection:
/// mock.finish()
///
/// // Inspect what the client sent to the server:
/// let sent = mock.clientSentMessages
/// ```
public final class MockWebSocketTask: WebSocketTask, @unchecked Sendable {

  // MARK: - Server → Client (test pushes messages to the SUT)

  private let serverMessages = AsyncStreamMocker<URLSessionWebSocketTask.Message>()

  private lazy var serverMessageIterator = serverMessages.makeAsyncIterator()

  // MARK: - Client → Server (SUT sends messages, test inspects them)

  /// Messages the client (system-under-test) has sent via `send(_:)`.
  public private(set) var clientSentMessages: [URLSessionWebSocketTask.Message] = []

  // MARK: - Lifecycle tracking

  public private(set) var isResumed: Bool = false
  public private(set) var cancelCode: URLSessionWebSocketTask.CloseCode?
  public private(set) var cancelReason: Data?

  // MARK: - Init

  public init() {}

  // MARK: - Server Controls (used by tests)

  /// Send a message to the client as the server.
  public func emit(_ message: URLSessionWebSocketTask.Message) {
    serverMessages.emit(message)
  }

  /// Close the server's message stream with an error.
  public func `throw`(_ error: any Error) {
    serverMessages.throw(error)
  }

  /// Close the server's message stream normally (no more messages).
  public func finish() {
    serverMessages.finish()
  }

  // MARK: - WebSocketTask conformance (called by SUT)

  public func resume() {
    isResumed = true
  }

  public func send(_ message: URLSessionWebSocketTask.Message) async throws {
    clientSentMessages.append(message)
  }

  public func receive() async throws -> URLSessionWebSocketTask.Message {
    guard let message = try await serverMessageIterator.next() else {
      throw CancellationError()
    }
    return message
  }

  public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    cancelCode = closeCode
    cancelReason = reason
  }
}
