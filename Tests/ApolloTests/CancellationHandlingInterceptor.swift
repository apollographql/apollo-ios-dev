import Foundation
import Apollo
import ApolloAPI

class CancellationHandlingInterceptor: ApolloInterceptor, Cancellable, @unchecked Sendable {
  private(set) var hasBeenCancelled = false

  public var id: String = UUID().uuidString
  
  func interceptAsync<Operation: GraphQLOperation>(
    chain: any RequestChain,
    request: HTTPRequest<Operation>,
    response: HTTPResponse<Operation>?,
    completion: @escaping @Sendable (Result<GraphQLResult<Operation.Data>, any Error>) -> Void) {
    
    guard !self.hasBeenCancelled else {
      return
    }
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      chain.proceedAsync(
        request: request,
        response: response,
        interceptor: self,
        completion: completion
      )
    }
  }
  
  func cancel() {
    self.hasBeenCancelled = true
  }
}
