import Foundation
import Apollo
import ApolloAPI

public final class WebSocketTransport: SubscriptionNetworkTransport {

  public enum Error: Swift.Error {
    /// WebSocketTransport has not yet been implemented for Apollo iOS 2.0. This will be implemented
    /// in a 2.1 update as soon as we can after 2.0 is out. Subscriptions over HTTP will work via the
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
