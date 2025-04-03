import Foundation
import Combine
#if !COCOAPODS
import ApolloAPI
#endif

#warning("TODO: Kill this and put logic in RequestChain.")
/// An interceptor which actually fetches data from the network.
public final class NetworkFetchInterceptor: ApolloInterceptor {
  let session: any ApolloURLSession

  /// Designated initializer.
  ///
  /// - Parameter session: The `URLSession` to use to fetch data
  public init(session: some ApolloURLSession) {
    self.session = session
  }
  
  public func intercept<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    next: NextInterceptorFunction<Operation>
  ) async throws -> InterceptorResult<Operation> {
    let urlRequest = try request.toURLRequest()

    let (bytes, response) = try await session.bytes(for: urlRequest, delegate: nil)

    guard let response = response as? HTTPURLResponse else {
      preconditionFailure()
      #warning("Throw error instead of precondition failure? Look into if it is possible for this to even occur.")
    }

    return InterceptorResult(
      response: .init(
        response: response,
        asyncBytes: bytes
      ))
  }

}
