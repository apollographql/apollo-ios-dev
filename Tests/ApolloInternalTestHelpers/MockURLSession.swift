import Foundation
import Apollo
import ApolloAPI
import ApolloWebSocket

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
  public let tasks: [MockWebSocketTask]
  private var index = 0

  public init(_ tasks: [MockWebSocketTask]) {
    self.tasks = tasks
  }

  func next() -> MockWebSocketTask {
    let task = tasks[index]
    index += 1
    return task
  }
}

public struct MockURLSession: ApolloURLSession, WebSocketURLSession {

  public let session: URLSession

  /// The default mock WebSocket task, used when no task factory is provided.
  /// When a factory is provided, this is set to the factory's first task for convenience.
  public let mockWebSocketTask: MockWebSocketTask

  /// Optional factory for vending fresh tasks on each `webSocketTask(with:)` call.
  /// When set, `mockWebSocketTask` is not used by `webSocketTask(with:)`.
  private let taskFactory: MockWebSocketTaskFactory?

  public init<T: MockResponseProvider>(responseProvider: T.Type) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol<T>.self]
    session = URLSession(configuration: configuration)
    mockWebSocketTask = MockWebSocketTask()
    taskFactory = nil
  }

  public init<T: MockResponseProvider>(
    responseProvider: T.Type,
    taskFactory: MockWebSocketTaskFactory
  ) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol<T>.self]
    session = URLSession(configuration: configuration)
    self.taskFactory = taskFactory
    // Set mockWebSocketTask to the first task for test convenience,
    // but webSocketTask(with:) will call factory.next() sequentially.
    mockWebSocketTask = taskFactory.tasks[0]
  }

  public func chunks(
    for request: URLRequest
  ) async throws -> (any AsyncChunkSequence, URLResponse) {
    try await session.chunks(for: request)
  }

  public func webSocketTask(with request: URLRequest) -> any WebSocketTask {
    taskFactory?.next() ?? mockWebSocketTask
  }

}
