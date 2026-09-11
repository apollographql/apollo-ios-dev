import Apollo
import ApolloAPI
import Foundation

/// A `GraphQLInterceptor` that holds the request chain in flight instead of calling `next`, suspending until its task
/// is cancelled and then throwing a `CancellationError`.
///
/// Suspending is what makes a cancellation test deterministic. An interceptor that only checks cancellation on its way
/// through races the test's `cancel()` call, and when the check wins it continues down the chain and never observes
/// cancellation at all.
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
    await withTaskCancellationHandler {
      await waitForCancellation()
    } onCancel: {
      markCancelled()
    }

    throw CancellationError()
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
