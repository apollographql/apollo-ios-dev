import Foundation
import Apollo
import ApolloAPI

// An interceptor which blindly retries every time it receives a request. 
class BlindRetryingTestInterceptor: ApolloInterceptor, @unchecked Sendable {
  var hitCount = 0

  func intercept<Request: GraphQLRequest>(
    request: Request,
    next: NextInterceptorFunction<Request>
  ) async throws -> InterceptorResultStream<Request.Operation> {
    self.hitCount += 1
    throw RequestChainRetry(request: request)
  }

}
