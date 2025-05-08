import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

#warning("TODO: Implement retrying based on catching error")
public struct RequestChainRetry<Request: GraphQLRequest>: Swift.Error {
  public let request: Request
  public let underlyingError: (any Swift.Error)?

  public init(
    request: Request,
    underlyingError: (any Error)? = nil
  ) {
    self.request = request
    self.underlyingError = underlyingError
  }
}

struct RequestChain<Request: GraphQLRequest>: Sendable {

  private let urlSession: any ApolloURLSession
  private let interceptors: [any ApolloInterceptor]
  private let cacheInterceptor: any CacheInterceptor
  private let errorInterceptor: (any ApolloErrorInterceptor)?

  typealias Operation = Request.Operation
  typealias ResultStream = AsyncThrowingStream<GraphQLResult<Operation.Data>, any Error>

  /// Creates a chain with the given interceptor array.
  ///
  /// - Parameters:
  ///   - interceptors: The array of interceptors to use.
  ///   - callbackQueue: The `DispatchQueue` to call back on when an error or result occurs.
  ///   Defaults to `.main`.
  init(
    urlSession: any ApolloURLSession,
    interceptors: [any ApolloInterceptor],
    cacheInterceptor: any CacheInterceptor,
    errorInterceptor: (any ApolloErrorInterceptor)?
  ) {
    self.urlSession = urlSession
    self.interceptors = interceptors
    self.cacheInterceptor = cacheInterceptor
    self.errorInterceptor = errorInterceptor
  }

  /// Kicks off the request from the beginning of the interceptor array.
  ///
  /// - Parameters:
  ///   - request: The request to send.
  func kickoff(
    request: Request
  ) -> ResultStream where Operation: GraphQLQuery {
    return doInAsyncThrowingStream { continuation in

      if request.cachePolicy.shouldAttemptCacheRead {
        do {
          let cacheData = try await cacheInterceptor.readCacheData(for: request.operation)
          continuation.yield(cacheData)

        } catch {
          if case .returnCacheDataDontFetch = request.cachePolicy {
            throw error
          }
        }
      }

      try await kickoffRequestInterceptors(for: request, continuation: continuation)
    }
  }

  func kickoff(
    request: Request
  ) -> ResultStream {
    return doInAsyncThrowingStream { continuation in

    }
  }

  private func doInAsyncThrowingStream(
    _ body: @escaping @Sendable (ResultStream.Continuation) async throws -> Void
  ) -> ResultStream {
    return AsyncThrowingStream { continuation in
      let task = Task {
        try await body(continuation)
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func kickoffRequestInterceptors(
    for initialRequest: Request,
    continuation: ResultStream.Continuation
  ) async throws {

    var next: @Sendable (Request) async throws -> InterceptorResultStream<Operation> = { request in
      try await executeNetworkFetch(request: request)
    }

    for interceptor in interceptors.reversed() {
      let tempNext = next

      next = { request in
        try await interceptor.intercept(request: request, next: tempNext)
      }
    }

    let result = try await next(initialRequest)
  }

  private func executeNetworkFetch(
    request: Request
  ) async throws -> InterceptorResultStream<Operation> {
    return InterceptorResultStream(stream: AsyncThrowingStream { continuation in
      let task = Task {
        let (chunks, response) = try await urlSession.chunks(for: request)

        guard let response = response as? HTTPURLResponse else {
          preconditionFailure()
#warning("Throw error instead of precondition failure? Look into if it is possible for this to even occur.")
        }

        for try await chunk in chunks {
          continuation.yield(
            InterceptorResult(
              response: response,
              rawResponseChunk: chunk as! Data
            )
          )
        }

        continuation.finish()
      }

      continuation.onTermination = { _ in task.cancel() }
    })
  }


}

fileprivate extension CachePolicy {
  var shouldAttemptCacheRead: Bool {
    switch self {
    case .fetchIgnoringCacheCompletely,
        .fetchIgnoringCacheData:
      return false

    case .returnCacheDataAndFetch,
        .returnCacheDataDontFetch,
        .returnCacheDataElseFetch:
      return true
    }
  }
}
