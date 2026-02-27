import Foundation
@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@testable import ApolloWebSocket

/// A mock delegate that records lifecycle events from ``WebSocketTransport`` for test assertions.
///
/// Delegate methods are `isolated` to the `WebSocketTransport` actor, so writes to the
/// internal event list are serialized through the actor. Reads from the test thread are
/// protected by an `NSLock` to prevent data races with `toEventually` polling.
public final class MockWebSocketTransportDelegate: WebSocketTransportDelegate, @unchecked Sendable {
  public enum Event: Equatable, CustomStringConvertible {
    case didConnect
    case didReconnect
    case didDisconnect(hasError: Bool)
    case didReceivePing(hasPayload: Bool)
    case didReceivePong(hasPayload: Bool)

    public var description: String {
      switch self {
      case .didConnect: return "didConnect"
      case .didReconnect: return "didReconnect"
      case .didDisconnect(let hasError): return "didDisconnect(hasError: \(hasError))"
      case .didReceivePing(let hasPayload): return "didReceivePing(hasPayload: \(hasPayload))"
      case .didReceivePong(let hasPayload): return "didReceivePong(hasPayload: \(hasPayload))"
      }
    }
  }

  private let lock = NSLock()
  private var _events: [Event] = []

  public init() {}
  
  public var events: [Event] {
    lock.lock()
    defer { lock.unlock() }
    return _events
  }

  private func record(_ event: Event) {
    lock.lock()
    _events.append(event)
    lock.unlock()
  }

  public func webSocketTransportDidConnect(_ webSocketTransport: isolated WebSocketTransport) {
    record(.didConnect)
  }

  public func webSocketTransportDidReconnect(_ webSocketTransport: isolated WebSocketTransport) {
    record(.didReconnect)
  }

  public func webSocketTransport(
    _ webSocketTransport: isolated WebSocketTransport,
    didDisconnectWithError error: (any Error)?
  ) {
    record(.didDisconnect(hasError: error != nil))
  }

  public func webSocketTransport(
    _ webSocketTransport: isolated WebSocketTransport,
    didReceivePingWithPayload payload: JSONObject?
  ) {
    record(.didReceivePing(hasPayload: payload != nil))
  }

  public func webSocketTransport(
    _ webSocketTransport: isolated WebSocketTransport,
    didReceivePongWithPayload payload: JSONObject?
  ) {
    record(.didReceivePong(hasPayload: payload != nil))
  }
}
