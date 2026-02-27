/// The lifecycle state of an individual GraphQL subscription.
///
/// This state reflects where the subscription currently is in its lifecycle,
/// from initial setup through active data reception to termination.
///
/// For WebSocket-based subscriptions, the state includes connection-aware
/// states like ``reconnecting`` and ``paused`` that reflect the health of
/// the underlying connection.
public enum SubscriptionState: Sendable, Equatable, CustomStringConvertible {
  /// The subscription has been initiated but is not yet active.
  ///
  /// The transport may still be establishing a connection or sending
  /// the subscribe message to the server.
  case pending

  /// The subscription is active and may receive data from the server.
  case active

  /// The subscription's underlying connection was intentionally paused.
  ///
  /// The subscription will resume automatically when the connection is
  /// restored via the transport's `resume()` method.
  case paused

  /// The subscription's underlying connection was lost.
  ///
  /// The transport is attempting to reconnect and will automatically
  /// resubscribe when the connection is restored.
  case reconnecting

  /// The subscription has ended.
  ///
  /// The subscription was either completed normally by the server,
  /// terminated due to an error, or cancelled by the client.
  case stopped

  public var description: String {
    switch self {
    case .pending: return "pending"
    case .active: return "active"
    case .paused: return "paused"
    case .reconnecting: return "reconnecting"
    case .stopped: return "stopped"
    }
  }
}
