import Apollo
import Foundation

/// A thread-safe container for a ``SubscriptionState`` value.
///
/// This class is used by the WebSocket transport to communicate subscription
/// lifecycle state to the ``SubscriptionStream`` held by the consumer.
/// The transport updates the state from within its actor isolation,
/// while the consumer reads it from any context.
final class SubscriptionStateStorage: @unchecked Sendable {
  private let lock = NSLock()
  private var _state: SubscriptionState = .pending

  var state: SubscriptionState {
    lock.lock()
    defer { lock.unlock() }
    return _state
  }

  func set(_ state: SubscriptionState) {
    lock.lock()
    _state = state
    lock.unlock()
  }
}
