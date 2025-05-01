import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// A network transport is responsible for sending GraphQL operations to a server.
public protocol NetworkTransport: AnyObject, Sendable {

  /// Send a GraphQL operation to a server and return a response.
  ///
  /// Note if you're implementing this yourself rather than using one of the batteries-included versions of `NetworkTransport` (which handle this for you): The `clientName` and `clientVersion` should be sent with any URL request which needs headers so your client can be identified by tools meant to see what client is using which request. The `addApolloClientHeaders` method is provided below to do this for you if you're using Apollo Studio.
  ///
  /// - Parameters:
  ///   - operation: The operation to send.
  ///   - cachePolicy: The `CachePolicy` to use making this request.
  ///   - contextIdentifier:  [optional] A unique identifier for this request, to help with deduping cache hits for watchers. Defaults to `nil`.
  ///   - context: [optional] A context that is being passed through the request chain. Defaults to `nil`.
  /// - Returns: A stream of `GraphQLResult`s for each response.
  func send<Operation: GraphQLOperation>(
    operation: Operation,
    cachePolicy: CachePolicy,
    contextIdentifier: UUID?,
    context: (any RequestContext)?
  ) async throws -> AsyncThrowingStream<GraphQLResult<Operation.Data>, any Error>

}

// MARK: -

/// A network transport which can also handle uploads of files.
public protocol UploadingNetworkTransport: NetworkTransport {

  /// Uploads the given files with the given operation.
  ///
  /// - Parameters:
  ///   - operation: The operation to send
  ///   - files: An array of `GraphQLFile` objects to send.
  ///   - context: [optional] A context that is being passed through the request chain.
  /// - Returns: A stream of `GraphQLResult`s for each response.
  func upload<Operation: GraphQLOperation>(
    operation: Operation,
    files: [GraphQLFile],
    context: (any RequestContext)?
  ) async throws -> AsyncThrowingStream<GraphQLResult<Operation.Data>, any Error>
}
