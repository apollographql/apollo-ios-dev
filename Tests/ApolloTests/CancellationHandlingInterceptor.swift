import Apollo
import ApolloAPI
import Foundation

final class CancellationTestingInterceptor: ApolloInterceptor {
  private(set) nonisolated(unsafe) var hasBeenCancelled = false

  func intercept<Request: GraphQLRequest>(
    request: Request,
    next: (Request) async -> InterceptorResultStream<Request>
  ) async throws -> InterceptorResultStream<Request> {
    do {
      try Task.checkCancellation()
      return await next(request)

    } catch is CancellationError {
      self.hasBeenCancelled = true
      throw CancellationError()
    }
  }

  func cancel() {
    self.hasBeenCancelled = true
  }
}
