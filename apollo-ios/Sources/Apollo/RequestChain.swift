#if !COCOAPODS
import ApolloAPI
#endif

#warning("TODO: Implement retrying based on catching error")
public struct RequestChainRetryError: Swift.Error { }

struct RequestChain<Operation: GraphQLOperation>: Sendable {

  private let urlSession: any ApolloURLSession
  private let interceptors: [any ApolloInterceptor]
  private let cacheInterceptor: any CacheInterceptor
  private let errorInterceptor: (any ApolloErrorInterceptor)?

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
    request: HTTPRequest<Operation>
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

      try await startRequestInterceptors(for: request, continuation: continuation)

    }
  }

  func kickoff(
    request: HTTPRequest<Operation>
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

  private func startRequestInterceptors(
    for request: HTTPRequest<Operation>,
    continuation: ResultStream.Continuation
  ) async throws {
    var interceptorIterator = interceptors.makeIterator()
    var currentResult: InterceptorResult<Operation>

////    for interceptor in interceptors {
////      try await interceptor.intercept(request: request) {
////        currentResult =
////      }
////    }
//
//    @Sendable func proceedThrough(
//      interceptor: any ApolloInterceptor
//    ) async throws {
//      try await interceptor.intercept(request: request) {
//        guard let nextInterceptor = interceptorIterator.next() else {
//          return
//        }
//
//        try await proceedThrough(interceptor: nextInterceptor)
//      }
//    }
////
//    try await proceedThroughInterceptors()

    while let nextInterceptor = interceptorIterator.next() {
      try await nextInterceptor.intercept(request: request) {

      }
    }
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
