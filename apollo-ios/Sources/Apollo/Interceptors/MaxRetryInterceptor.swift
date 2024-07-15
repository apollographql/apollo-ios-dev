import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// An interceptor to enforce a maximum number of retries of any `HTTPRequest`
public class MaxRetryInterceptor: ApolloInterceptor {
  
  private let maxRetries: Int
  private var hitCount = 0

  public var id: String = UUID().uuidString
  
  public enum RetryError: Error, LocalizedError {
    case hitMaxRetryCount(count: Int, operationName: String)
    
    public var errorDescription: String? {
      switch self {
      case .hitMaxRetryCount(let count, let operationName):
        return "The maximum number of retries (\(count)) was hit without success for operation \"\(operationName)\"."
      }
    }
  }
  
  /// Designated initializer.
  ///
  /// - Parameter maxRetriesAllowed: How many times a query can be retried, in addition to the initial attempt before
  public init(maxRetriesAllowed: Int = 3) {
    self.maxRetries = maxRetriesAllowed
  }
  
  public func intercept<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    response: HTTPResponse<Operation>?
  ) async throws -> RequestChain.NextAction<Operation> {
    guard self.hitCount <= self.maxRetries else {
      throw RetryError.hitMaxRetryCount(
        count: self.maxRetries,
        operationName: Operation.operationName
      )
    }
    
    self.hitCount += 1
    return .proceed(request: request, response: response)    
  }
}
