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

  // MARK: - Thread Safety
  //
  // WebSocketConnection.send() spawns unstructured Task blocks that run concurrently
  // on the default executor (not actor-isolated). When multiple messages are sent in
  // rapid succession (e.g. resubscribing all active subscriptions after reconnection),
  // concurrent Tasks can race on the mutable state below. The lock serializes access.

  private let lock = NSLock()

  // MARK: - Client → Server (SUT sends messages, test inspects them)

  /// Messages the client (system-under-test) has sent via `send(_:)`.
  ///
  /// - Important: Access is serialized via `lock` to prevent data races from concurrent
  ///   `WebSocketConnection.send()` tasks. Use the public accessor which reads under the lock.
  private var _clientSentMessages: [URLSessionWebSocketTask.Message] = []

  public var clientSentMessages: [URLSessionWebSocketTask.Message] {
    lock.lock()
    defer { lock.unlock() }
    return _clientSentMessages
  }

  // MARK: - Lifecycle tracking

  private var _isResumed: Bool = false
  private var _cancelCode: URLSessionWebSocketTask.CloseCode?
  private var _cancelReason: Data?

  public var isResumed: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _isResumed
  }

  public var cancelCode: URLSessionWebSocketTask.CloseCode? {
    lock.lock()
    defer { lock.unlock() }
    return _cancelCode
  }

  public var cancelReason: Data? {
    lock.lock()
    defer { lock.unlock() }
    return _cancelReason
  }

  // MARK: - Init

  public init() {}

  // MARK: - Server Controls (used by tests)

  /// Send a message to the client as the server.
  public func emit(_ message: URLSessionWebSocketTask.Message) {
    serverMessages.emit(message)
  }

  /// Emit a typed server message (serializes to JSON internally).
  ///
  /// Prefer this over the raw `.string(...)` overload so tests read as structured
  /// message values instead of hand-written JSON strings.
  public func emit(_ message: ServerMessage) {
    var json: [String: Any]
    switch message {
    case .connectionAck(let payload):
      json = ["type": "connection_ack"]
      if let payload { json["payload"] = payload }
    case .ping(let payload):
      json = ["type": "ping"]
      if let payload { json["payload"] = payload }
    case .pong(let payload):
      json = ["type": "pong"]
      if let payload { json["payload"] = payload }
    case .next(let id, let payload):
      json = ["type": "next", "id": id, "payload": payload]
    case .error(let id, let payload):
      json = ["type": "error", "id": id, "payload": payload]
    case .complete(let id):
      json = ["type": "complete", "id": id]
    }
    let data = try! JSONSerialization.data(withJSONObject: json)
    emit(.string(String(data: data, encoding: .utf8)!))
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
    lock.lock()
    defer { lock.unlock() }
    _isResumed = true
  }

  public func send(_ message: URLSessionWebSocketTask.Message) async throws {
    lock.withLock {
      _clientSentMessages.append(message)
    }
  }

  public func receive() async throws -> URLSessionWebSocketTask.Message {
    guard let message = try await serverMessageIterator.next() else {
      // Real URLSessionWebSocketTask throws POSIXError(.ENOTCONN) (code 57) when the
      // server closes the connection gracefully. Match that behavior so the transport's
      // receive loop handles mock disconnection the same way as real disconnection.
      throw POSIXError(.ENOTCONN)
    }
    return message
  }

  public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    lock.lock()
    _cancelCode = closeCode
    _cancelReason = reason
    lock.unlock()
    // Match real URLSessionWebSocketTask behavior: cancelling the task causes any
    // pending receive() call to throw URLError(.cancelled).
    serverMessages.throw(URLError(.cancelled))
  }

  // MARK: - Client Message Inspection (used by tests)

  /// Returns the parsed JSON dictionaries for all client-sent messages matching the given
  /// `graphql-transport-ws` message type (e.g. `"subscribe"`, `"complete"`, `"connection_init"`).
  public func clientSentMessages(ofType type: String) -> [[String: Any]] {
    clientSentMessages.compactMap { message in
      let data: Data
      switch message {
      case .string(let string):
        data = Data(string.utf8)
      case .data(let d):
        data = d
      @unknown default:
        return nil
      }
      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["type"] as? String == type else {
        return nil
      }
      return json
    }
  }

  /// Returns the operation ID from the subscribe message at the given index.
  ///
  /// Use this to extract the actual server-assigned ID instead of hardcoding operation IDs
  /// in test assertions and mock server messages.
  ///
  /// - Precondition: There must be at least `index + 1` subscribe messages already sent.
  public func subscribeOperationID(at index: Int) -> String {
    let messages = clientSentMessages(ofType: "subscribe")
    precondition(
      index < messages.count,
      "Expected subscribe message at index \(index), but only \(messages.count) subscribe messages exist"
    )
    guard let id = messages[index]["id"] as? String else {
      preconditionFailure("Subscribe message at index \(index) has no 'id' field")
    }
    return id
  }

  // MARK: - Typed Server Message Helpers

  /// A test-friendly representation of `graphql-transport-ws` server messages.
  ///
  /// Mirrors `WebSocketTransport.Message.Incoming` but uses `[String: Any]` for payloads
  /// so tests can construct nested dictionaries without `JSONObject` type constraints.
  public enum ServerMessage {
    case connectionAck(payload: [String: Any]? = nil)
    case ping(payload: [String: Any]? = nil)
    case pong(payload: [String: Any]? = nil)
    case next(id: String, payload: [String: Any])
    case error(id: String, payload: [[String: Any]])
    case complete(id: String)
  }
}
