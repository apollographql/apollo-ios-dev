import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

#warning("TODO: remove unchecked when making interceptor functions async.")
/// An interceptor to enforce a maximum number of retries of any `HTTPRequest`
public actor MaxRetryInterceptor: ApolloInterceptor, Sendable {

  private let maxRetries: Int
  private var hitCount = 0
  
  public struct MaxRetriesError: Error, LocalizedError {
    let count: Int
    let operationName: String

    public var errorDescription: String? {
      return "The maximum number of retries (\(count)) was hit without success for operation \"\(operationName)\"."
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
    next: NextInterceptorFunction<Operation>
  ) async throws -> InterceptorResultStream<Operation> {
    guard self.hitCount <= self.maxRetries else {
      throw MaxRetriesError(
        count: self.maxRetries,
        operationName: Operation.operationName
      )
    }

    self.hitCount += 1
    return try await next(request)
  }
}
