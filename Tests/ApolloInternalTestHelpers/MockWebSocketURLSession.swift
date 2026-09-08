import Apollo
import ApolloAPI
import ApolloWebSocket
import Foundation

/// A factory that vends `MockWebSocketTask` instances in sequence.
///
/// Use this when testing reconnection scenarios where each connection attempt should use a fresh task.
///
/// ```swift
/// let task1 = MockWebSocketTask()
/// let task2 = MockWebSocketTask()
/// let factory = MockWebSocketTaskFactory([task1, task2])
/// // First call to next() returns task1, second returns task2
/// ```
public final class MockWebSocketTaskFactory: @unchecked Sendable {
  public var tasks: [MockWebSocketTask]
  private var index = 0

  /// The `URLRequest`s passed to each `webSocketTask(with:)` call, in order.
  public private(set) var capturedRequests: [URLRequest] = []

  /// The most recently vended task — i.e. the task currently being used by the mock session.
  ///
  /// This is useful in tests that need to emit server messages or inspect client messages
  /// on the active connection without maintaining a separate local variable.
  ///
  /// - Precondition: At least one task must have been vended via `next(for:)`.
  public var currentTask: MockWebSocketTask {
    precondition(index > 0, "MockWebSocketTaskFactory: no task has been vended yet")
    return tasks[index - 1]
  }

  public init(_ tasks: [MockWebSocketTask]) {
    self.tasks = tasks
  }

  func next(for request: URLRequest) -> MockWebSocketTask {
    capturedRequests.append(request)
    precondition(
      index < tasks.count,
      "MockWebSocketTaskFactory: requested task at index \(index) but only \(tasks.count) tasks were provided"
    )
    let task = tasks[index]
    index += 1
    return task
  }
}

/// A `WebSocketURLSession` that vends `MockWebSocketTask`s instead of real WebSocket connections.
///
/// This is the WebSocket counterpart to `ApolloTestSupport`'s `MockURLSession`, which stubs `ApolloURLSession` for
/// HTTP. It lives here rather than in `ApolloTestSupport` so that module does not need to depend on
/// `ApolloWebSocket`.
public struct MockWebSocketURLSession: WebSocketURLSession {

  /// The default mock WebSocket task, used when no task factory is provided.
  /// When a factory is provided, this is set to the factory's first task for convenience.
  public let mockWebSocketTask: MockWebSocketTask

  /// Optional factory for vending fresh tasks on each `webSocketTask(with:)` call.
  /// When set, `mockWebSocketTask` is not used by `webSocketTask(with:)`.
  private let taskFactory: MockWebSocketTaskFactory?

  public init() {
    mockWebSocketTask = MockWebSocketTask()
    taskFactory = nil
  }

  public init(taskFactory: MockWebSocketTaskFactory) {
    self.taskFactory = taskFactory
    // Set mockWebSocketTask to the first task for test convenience,
    // but webSocketTask(with:) will call factory.next() sequentially.
    mockWebSocketTask = taskFactory.tasks[0]
  }

  public func webSocketTask(with request: URLRequest) -> any WebSocketTask {
    taskFactory?.next(for: request) ?? mockWebSocketTask
  }

}
