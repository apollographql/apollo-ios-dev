import Apollo
import ApolloAPI
import Foundation

public actor WebSocketTransport: SubscriptionNetworkTransport {

  public enum Error: Swift.Error {
    /// WebSocketTransport has not yet been implemented for Apollo iOS 2.0. This will be implemented in a future
    /// release.
    case notImplemented
  }

  private var connection: WebSocketConnection?

  public let session: WebSocketURLSession

  public init(session: WebSocketURLSession) {
    self.session = session
//    self.connection = WebSocketConnection()
  }

  nonisolated public func send<Subscription: GraphQLSubscription>(
    subscription: Subscription,
    fetchBehavior: Apollo.FetchBehavior,
    requestConfiguration: Apollo.RequestConfiguration
  ) throws -> AsyncThrowingStream<Apollo.GraphQLResponse<Subscription>, any Swift.Error> {
    throw Error.notImplemented
  }

}

public final class WebSocketConnection: Sendable {

  //  enum State {
  //    case notStarted
  //    case connecting
  //    case connected
  //    case disconnected
  //  }

  //  private unowned let transport: WebSocketTransport
  private let webSocketTask: URLSessionWebSocketTask

  init(task: URLSessionWebSocketTask) {
    self.webSocketTask = task
  }

  deinit {
    self.webSocketTask.cancel(with: .goingAway, reason: nil)
  }

  func openConnection() async throws -> AsyncThrowingStream<URLSessionWebSocketTask.Message, any Swift.Error> {
    webSocketTask.resume()
    return AsyncThrowingStream { [weak self] in
      guard let self else { return nil }

      try Task.checkCancellation()

      let message = try await self.webSocketTask.receive()

      return Task.isCancelled ? nil : message
    }
  }

  func send(with: Any) throws {

  }

}

public protocol GraphQLWebSocketRequest<Operation>: Sendable {
  associatedtype Operation: GraphQLOperation

  /// The GraphQL Operation to execute
  var operation: Operation { get set }

  /// The ``FetchBehavior`` to use for this request.
  /// Determines if fetching will include cache/network.
  var fetchBehavior: FetchBehavior { get set }

  /// Determines if the results of a network fetch should be written to the local cache.
  var writeResultsToCache: Bool { get set }

  /// The timeout interval specifies the limit on the idle interval allotted to a request in the process of
  /// loading. This timeout interval is measured in seconds.
  var requestTimeout: TimeInterval? { get set }
}
