import Foundation
import Apollo
import ApolloAPI

// An interceptor which blindly retries every time it receives a request. 
class BlindRetryingTestInterceptor: ApolloInterceptor, @unchecked Sendable {
  var hitCount = 0
  private(set) var hasBeenCancelled = false

  public var id: String = UUID().uuidString

  func intercept<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    next: NextInterceptorFunction<Operation>
  ) async throws -> InterceptorResultStream<Operation> {
    self.hitCount += 1
    throw RequestChainRetry()
  }
  
  // Purposely not adhering to `Cancellable` here to make sure non `Cancellable` interceptors don't have this called.
  func cancel() {
    self.hasBeenCancelled = true
  }
}
