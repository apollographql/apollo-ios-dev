import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

#warning("TODO: Implement retrying based on catching error")
#warning("TODO: add optional underlying error property to retry error")
public struct RequestChainRetry: Swift.Error { }

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

      try await kickoffRequestInterceptors(for: request, continuation: continuation)
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

  private func kickoffRequestInterceptors(
    for initialRequest: HTTPRequest<Operation>,
    continuation: ResultStream.Continuation
  ) async throws {

    var next: @Sendable (HTTPRequest<Operation>) async throws -> InterceptorResult<Operation> = { request in
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
    request: HTTPRequest<Operation>
  ) async throws -> InterceptorResult<Operation> {
    let urlRequest = try request.toURLRequest()

    let (bytes, response) = try await urlSession.bytes(for: urlRequest, delegate: nil)

    guard let response = response as? HTTPURLResponse else {
      preconditionFailure()
      #warning("Throw error instead of precondition failure? Look into if it is possible for this to even occur.")
    }

    return InterceptorResult(
      response: response,
      responseAsyncBytes: bytes
    )
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
