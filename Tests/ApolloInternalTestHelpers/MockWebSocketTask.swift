import Foundation
import ApolloWebSocket

/// A mock implementation of ``WebSocketTask`` for unit testing WebSocket interactions.
///
/// This mock lets tests control the receive side by pushing messages via the ``receiveMessages``
/// stream mocker, and inspect the send side by reading ``sentMessages``.
///
/// ```swift
/// let mock = MockWebSocketTask()
///
/// // Push a message the SUT will receive:
/// mock.receiveMessages.emit(.string("{\"type\":\"connection_ack\"}"))
///
/// // End the stream when done:
/// mock.receiveMessages.finish()
///
/// // Assert on what was sent:
/// let sent = mock.sentMessages
/// ```
public final class MockWebSocketTask: WebSocketTask, @unchecked Sendable {

  // MARK: - Receive side (test → SUT)

  /// Push messages here that the system-under-test will receive when it calls `receive()`.
  public let receiveMessages = AsyncStreamMocker<URLSessionWebSocketTask.Message>()

  private lazy var receiveIterator = receiveMessages.makeAsyncIterator()

  // MARK: - Send side (SUT → test)

  /// Messages sent by the system-under-test via `send(_:)`.
  public private(set) var sentMessages: [URLSessionWebSocketTask.Message] = []

  // MARK: - Lifecycle tracking

  public private(set) var isResumed: Bool = false
  public private(set) var cancelCode: URLSessionWebSocketTask.CloseCode?
  public private(set) var cancelReason: Data?

  // MARK: - Init

  public init() {}

  // MARK: - WebSocketTask conformance

  public func resume() {
    isResumed = true
  }

  public func send(_ message: URLSessionWebSocketTask.Message) async throws {
    sentMessages.append(message)
  }

  public func receive() async throws -> URLSessionWebSocketTask.Message {
    guard let message = try await receiveIterator.next() else {
      throw CancellationError()
    }
    return message
  }

  public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    cancelCode = closeCode
    cancelReason = reason
  }
}
