#if !COCOAPODS
import ApolloAPI
#endif
import Combine

/// A protocol to set up a chainable unit of networking work.
#warning("Rename to RequestChainInterceptor?")
public protocol ApolloInterceptor {

  /// Used to uniquely identify this interceptor from other interceptors in a request chain.
  ///
  /// Each operation request has it's own interceptor request chain so the interceptors do not
  /// need to be uniquely identifiable between each and every request, only unique between the
  /// list of interceptors in a single request.
#warning("Get rid of?")
  var id: String { get }

  /// Called when this interceptor should do its work.
  ///
  /// - Parameters:
  ///   - chain: The chain the interceptor is a part of.
  ///   - request: The request, as far as it has been constructed
  ///   - response: [optional] The response, if received
  ///   - completion: The completion block to fire when data needs to be returned to the UI.
  func intercept<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    response: HTTPResponse<Operation>?
  ) async throws -> RequestChain.NextAction<Operation>
}
