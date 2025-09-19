import Foundation
import Apollo
import ApolloAPI

public final class WebSocketTransport: SubscriptionNetworkTransport {

  public enum Error: Swift.Error {
    /// WebSocketTransport has not yet been implemented for Apollo iOS 2.0. This will be implemented
    /// in future release. Subscriptions over HTTP will work via the
    /// RequestChainNetworkTransport in 2.0 out of the box in the meantime. 
    case notImplemented
  }

  public func send<Subscription: GraphQLSubscription>(
    subscription: Subscription,
    fetchBehavior: Apollo.FetchBehavior,
    requestConfiguration: Apollo.RequestConfiguration
  ) throws -> AsyncThrowingStream<Apollo.GraphQLResponse<Subscription>, any Swift.Error> {
    throw Error.notImplemented
  }

}
