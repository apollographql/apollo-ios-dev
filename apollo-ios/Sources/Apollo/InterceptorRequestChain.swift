import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// A chain that allows a single network request to be created and executed.
public struct RequestChain {

  public enum NextAction<Operation: GraphQLOperation> {
    case proceed(
      request: HTTPRequest<Operation>,
      response: HTTPResponse<Operation>?
    )

    case proceedAndEmit(
      intermediaryResult: GraphQLResult<Operation.Data>,
      request: HTTPRequest<Operation>,
      response: HTTPResponse<Operation>?
    )

    case exitEarlyAndEmit(
      result: GraphQLResult<Operation.Data>,
      request: HTTPRequest<Operation>
    )

    case retry(
      request: HTTPRequest<Operation>
    )

    fileprivate var request: HTTPRequest<Operation> {
      switch self {
      case 
        let .exitEarlyAndEmit(_, request),
        let .retry(request),
        let .proceed(request, _),
        let .proceedAndEmit(_, request, _):
          return request
      }
    }

    fileprivate var response: HTTPResponse<Operation>? {
      switch self {
      case .exitEarlyAndEmit, .retry: return nil

      case
        let .proceed(_, response),
        let .proceedAndEmit(_, _, response):
        return response
      }
    }

    fileprivate var result: GraphQLResult<Operation.Data>? {
      switch self {
      case .retry: return nil

      case let .exitEarlyAndEmit(result, _): return result

      case 
        let .proceed(_, response),
        let .proceedAndEmit(_, _, response):
        return response?.parsedResult
      }
    }
  }

  public enum ChainError: Error, LocalizedError {
    case invalidIndex(chain: RequestChain, index: Int)
    case chainTerminatedWithNoResult
    case unknownInterceptor(id: String)

    public var errorDescription: String? {
      switch self {
      case .chainTerminatedWithNoResult:
        return "This request chain terminated with no 'parsedResult'. This is a developer error."
      case .invalidIndex(_, let index):
        return "`proceedAsync` was called for index \(index), which is out of bounds of the receiver for this chain. Double-check the order of your interceptors."
      case let .unknownInterceptor(id):
        return "`proceedAsync` was called by unknown interceptor \(id)."
      }
    }
  }

  private let interceptors: [any ApolloInterceptor]

  /// Something which allows additional error handling to occur when some kind of error has happened.
  private let errorInterceptor: (any ApolloErrorInterceptor)?

  /// Creates a chain with the given interceptor array.
  ///
  /// - Parameters:
  ///   - interceptors: The array of interceptors to use.
  ///   - callbackQueue: The `DispatchQueue` to call back on when an error or result occurs.
  ///   Defaults to `.main`.
  public init(
    interceptors: [any ApolloInterceptor],
    errorInterceptor: any ApolloErrorInterceptor
  ) {
    self.interceptors = interceptors
    self.errorInterceptor = errorInterceptor
  }

  /// Kicks off the request from the beginning of the interceptor array.
  ///
  /// - Parameters:
  ///   - request: The request to send.
  ///   - completion: The completion closure to call when the request has completed.
  public func kickoff<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>
  ) -> AsyncThrowingStream<GraphQLResult<Operation.Data>, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        var nextAction: NextAction<Operation> = .proceed(
          request: request,
          response: nil
        )

        do {
          for interceptor in interceptors {
            try Task.checkCancellation()

            switch nextAction {
            case let .proceedAndEmit(intermediaryResult,
                                     request,
                                     response):
              continuation.yield(intermediaryResult)
              fallthrough

            case let .proceed(request, response):
              nextAction = try await interceptor.intercept(
                request: request,
                response: response
              )
              continue

            case let .exitEarlyAndEmit(result, _):
              continuation.yield(result)
              continuation.finish()
              return

            case let .retry(request):
              for try await result in kickoff(request: request) {
                continuation.yield(result)
              }
            }
          }

          try Task.checkCancellation()
          guard let result = nextAction.result else {
            throw ChainError.chainTerminatedWithNoResult
          }

          continuation.yield(result)
          continuation.finish()

        } catch {
          do {
            let errorRecoveryResult = try await handleError(
              error,
              request: nextAction.request,
              response: nextAction.response
            )
            continuation.yield(errorRecoveryResult)
            continuation.finish()

          } catch {
            continuation.finish(throwing: error)
          }
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  /// Handles the error by returning it on the appropriate queue, or by applying an additional
  /// error interceptor if one has been provided.
  ///
  /// - Parameters:
  ///   - error: The error to handle
  ///   - request: The request, as far as it has been constructed.
  ///   - response: The response, as far as it has been constructed.
  ///   - completion: The completion closure to call when work is complete.
  public func handleError<Operation: GraphQLOperation>(
    _ error: any Error,
    request: HTTPRequest<Operation>,
    response: HTTPResponse<Operation>?
  ) async throws -> GraphQLResult<Operation.Data> {
    try Task.checkCancellation()

    guard let additionalHandler = self.errorInterceptor else {
      throw error
    }

    return try await additionalHandler.handleError(
      error: error,
      request: request,
      response: response
    )
  }

}
