import Foundation
import Apollo
import ApolloAPI

public final class WebSocketTransport: SubscriptionNetworkTransport {

  public enum Error: Swift.Error {
    /// WebSocketTransport has not yet been implemented for Apollo iOS 2.0. This will be implemented in a future
    /// release.
    case notImplemented
  }

  private var connection: any WebSocketConnection

  public init(connection: any WebSocketConnection) {
    self.connection = connection
  }

  public func send<Subscription: GraphQLSubscription>(
    subscription: Subscription,
    fetchBehavior: Apollo.FetchBehavior,
    requestConfiguration: Apollo.RequestConfiguration
  ) throws -> AsyncThrowingStream<Apollo.GraphQLResponse<Subscription>, any Swift.Error> {
    throw Error.notImplemented
  }

}

public protocol WebSocketConnection: Actor {

  func openConnection() async throws

  func sendOperation(with: Any) throws -> AsyncThrowingStream<JSONObject, any Swift.Error>

}

public protocol SubscriptionURLSession: Sendable {

//  func
}
