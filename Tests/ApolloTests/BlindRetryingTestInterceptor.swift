import Apollo
import ApolloAPI
import Foundation

// An interceptor which blindly retries every time it receives a request.
class BlindRetryingTestInterceptor: GraphQLInterceptor, @unchecked Sendable {
  var hitCount = 0

  func intercept<Request: GraphQLRequest>(
    request: Request,
    next: (Request) async -> InterceptorResultStream<Request>
  ) async throws -> InterceptorResultStream<Request> {
    self.hitCount += 1
    throw RequestChain.Retry(request: request)
  }

}
