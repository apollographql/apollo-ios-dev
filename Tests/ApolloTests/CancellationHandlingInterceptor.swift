import Apollo
import ApolloAPI
import Foundation

final class CancellationTestingInterceptor: GraphQLInterceptor, @unchecked Sendable {
  private let lock = NSLock()
  private var _hasBeenCancelled = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  var hasBeenCancelled: Bool {
    lock.withLock { _hasBeenCancelled }
  }

  func intercept<Request: GraphQLRequest>(
    request: Request,
    next: (Request) async -> InterceptorResultStream<Request>
  ) async throws -> InterceptorResultStream<Request> {
    do {
      try Task.checkCancellation()
      return await next(request)

    } catch is CancellationError {
      markCancelled()
      throw CancellationError()
    }
  }

  func cancel() {
    markCancelled()
  }

  /// Suspends until cancellation has been detected and `hasBeenCancelled` is `true`.
  ///
  /// Use this in tests instead of `toEventually(beTrue())` to avoid flakiness caused by
  /// polling across multiple cooperative-scheduler hops.
  func waitForCancellation() async {
    await withCheckedContinuation { continuation in
      lock.withLock {
        if _hasBeenCancelled {
          continuation.resume()
        } else {
          waiters.append(continuation)
        }
      }
    }
  }

  private func markCancelled() {
    var pending: [CheckedContinuation<Void, Never>] = []
    lock.withLock {
      _hasBeenCancelled = true
      pending = waiters
      waiters.removeAll()
    }
    for continuation in pending {
      continuation.resume()
    }
  }
}
