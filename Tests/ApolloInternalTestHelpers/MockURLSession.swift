import Foundation
import Apollo
import ApolloAPI
import ApolloWebSocket

public struct MockURLSession: ApolloURLSession, WebSocketURLSession {

  public let session: URLSession
  public let mockWebSocketTask: MockWebSocketTask

  public init<T: MockResponseProvider>(responseProvider: T.Type) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol<T>.self]
    session = URLSession(configuration: configuration)
    mockWebSocketTask = MockWebSocketTask()
  }

  public func chunks(
    for request: URLRequest
  ) async throws -> (any AsyncChunkSequence, URLResponse) {
    try await session.chunks(for: request)
  }

  public func webSocketTask(with request: URLRequest) -> any WebSocketTask {
    mockWebSocketTask
  }

}
