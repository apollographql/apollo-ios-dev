#if !COCOAPODS
import ApolloAPI
#endif

/// An error interceptor called to allow further examination of error data when an error occurs in the chain.
#warning("TODO: Should this be Sendable or not?")
#warning("TODO: Kill this, or implement it's usage in Request Chain.")
public protocol ApolloErrorInterceptor: Sendable {

  /// Asynchronously handles the receipt of an error at any point in the chain.
  ///
  /// - Parameters:
  ///   - error: The received error
  ///   - chain: The chain the error was received on
  ///   - request: The request, as far as it was constructed
  ///   - response: [optional] The response, if one was received
  ///   - completion: The completion closure to fire when the operation has completed. Note that if you call `retry` on the chain, you will not want to call the completion block in this method.
  func handleError<Operation: GraphQLOperation>(
    error: any Error,
    request: HTTPRequest<Operation>,
    response: HTTPResponse<Operation>?
  ) async throws -> GraphQLResult<Operation.Data>
  #warning("TODO: make this return a NextAction and handle proceeding with that action.")
}
