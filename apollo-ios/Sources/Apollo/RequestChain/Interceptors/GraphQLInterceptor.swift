import ApolloAPI
import Foundation

/// The stream of results passed through a series of ``GraphQLInterceptor``s by a ``RequestChain``.
///
/// This is a stream of ``ParsedResult``s wrapped in a ``NonCopyableAsyncThrowingStream`` to ensure the stream's values
/// are not consumed by intermediary interceptors.
///
/// Because some requests may have a multi-part response, such as subscriptions or operations using `@defer`, the
/// results of a ``RequestChain`` are processed as a stream. For requests that should have a single response, the stream
/// will emit a single value and then terminate.
public typealias InterceptorResultStream<Request: GraphQLRequest> =
  NonCopyableAsyncThrowingStream<ParsedResult<Request.Operation>>

/// A protocol for an interceptor in a ``RequestChain`` that can perform a unit of work that operates on a
/// ``GraphQLRequest`` and ``ParsedResult``.
///
/// The interceptor can perform pre-flight work on the ``GraphQLRequest`` and post-flight work on the ``ParsedResult``.
///
/// ## Pre-Flight
/// Each ``GraphQLInterceptor`` provided by an ``InterceptorProvider`` will have it's ``intercept(request:next:)``
/// function called in sequential order prior to fetching the request.
///
/// The interceptor may inspect or modify the provided `request`, which must then be passed into the `next` closure to
/// continue through the ``RequestChain``.
///
/// ## Calling `next` Is Required
/// Every ``GraphQLInterceptor`` must call `next`. The remaining steps of the ``RequestChain`` — the interceptors after
/// this one, the cache read, the network fetch, and response parsing — all run inside that call, so an interceptor
/// that returns a stream of its own instead silently skips them. Nothing else in the chain can observe that this
/// happened: ``GraphQLRequest/fetchBehavior`` is ignored, later interceptors never see the request, and the emitted
/// ``ParsedResult`` has not been through response parsing.
///
/// An interceptor that emits a result without calling `next` therefore fails the request with a
/// ``GraphQLInterceptorDidNotCallNextError`` naming the offending interceptor.
///
/// To supply results without performing a network fetch, use the seam intended for it rather than skipping the chain:
///
/// - **To substitute a canned response**, stub the `ApolloURLSession` — see `MockApolloURLSession` in
/// `ApolloTestSupport`. The interceptors, response parsing, and cache writes then all run as they do in production.
/// - **To supply a result only when the fetch fails**, call `next` and recover from the error with
/// ``NonCopyableAsyncThrowingStream/mapErrors(_:)``, which may return a ``ParsedResult`` of your own in its place.
/// - **To serve results from the cache**, use ``GraphQLRequest/fetchBehavior`` or a custom ``CacheInterceptor``.
/// - **To abort the request**, throw from ``intercept(request:next:)``. The error is propagated to the caller.
///
/// ## Post-Flight
/// After response data is fetched and parsed, the ``ParsedResult`` will be emitted by the ``InterceptorResultStream``
/// returned by the call to the `next` closure. The ``ParsedResult`` is passed back up the interceptor chain in reverse
/// order such that the first interceptor called will be the last to receive the response.
///
/// The response may be inspected or modified by using the mapping functions of ``NonCopyableAsyncThrowingStream``.
/// The interceptor must then return the stream to continue through the ``RequestChain``.
///
/// ## Error Handling
/// Both pre-flight and post-flight errors can be caught using the ``NonCopyableAsyncThrowingStream/mapErrors(_:)``
/// function of the ``InterceptorResultStream`` returned by calling the `next` closure. This will catch any errors
/// thrown in later steps of the ``RequestChain``, including:
/// - Pre-flight errors thrown by ``GraphQLInterceptor``s later in the ``RequestChain``.
/// - Networking errors thrown by the ``ApolloURLSession`` or ``HTTPInterceptor``s in the ``RequestChain``.
/// - Parsing errors thrown by the ``ResponseParsingInterceptor`` of the ``RequestChain``.
/// - Post-flight errors thrown by ``GraphQLInterceptor``s later in the request chain.
///
/// Your ``NonCopyableAsyncThrowingStream/mapErrors(_:)`` closure may rethrow the same error or a different error,
/// which will then be passed up through the rest of the request chain. If possible, you may recover from the error
/// by constructing and returning a ``ParsedResult``. Returning `nil` will suppress the error and terminate the
/// ``RequestChain``'s stream without emitting a result.
/// 
/// It is not required that every interceptor implement error handling. A ``GraphQLInterceptor`` that does not call
/// ``NonCopyableAsyncThrowingStream/mapErrors(_:)`` will be skipped if an error is emitted.
/// 
/// ## Example
/// As an example, a simple logging interceptor might look like this:
/// ```swift
/// struct LoggingInterceptor: GraphQLInterceptor {
/// 
/// let logger: Logger
/// 
/// func intercept<Request: GraphQLRequest>(
///   request: Request,
///   next: NextInterceptorFunction<Request>
/// ) async throws -> InterceptorResultStream<Request> {
///   // Pre-flight work
///   logger.log(request: request)
/// 
///   // Proceed to next interceptor
///   return await next(request)
///   .map { response in
///     // Post-flight work
///     logger.log(response: response)
///     return response
/// 
///   }.mapErrors { error in
///     // Handle errors from later steps of the `RequestChain`
///     logger.log(error: error)
/// 
///     // Rethrows the error to the next interceptor.
///     throw error
///   }
/// }
/// ```
public protocol GraphQLInterceptor: Sendable {

  /// A closure called to proceed to the next step in the ``RequestChain`` after performing pre-flight work.
  ///
  /// - Parameters:
  ///   - Request: The ``GraphQLRequest`` to send to the next step in the ``RequestChain``.
  ///
  /// - Returns: An ``InterceptorResultStream`` used to intercept response data and perform post-flight work.
  typealias NextInterceptorFunction<Request: GraphQLRequest> = @Sendable (Request) async ->
    InterceptorResultStream<Request>

  /// The entry point used to intercept the ``GraphQLRequest``.
  ///
  /// This function is called by the ``RequestChain`` during pre-flight operations. Post-flight work can be performed
  /// in the `map` functions of the ``InterceptorResultStream`` returned by calling the `next` closure.
  ///
  /// - Parameters:
  ///   - request: The current pre-flight state of the request, may be modified by subsequent interceptors after
  ///   calling the `next` closure.
  ///   - next: The ``NextInterceptorFunction`` that must be called to proceed to the next step in the
  ///   ``RequestChain``. An interceptor that emits a result without calling this closure fails the request with a
  ///   ``GraphQLInterceptorDidNotCallNextError``.
  /// - Returns: The stream of results to pass to the next interceptor for post-flight processing.
  func intercept<Request: GraphQLRequest>(
    request: Request,
    next: NextInterceptorFunction<Request>
  ) async throws -> InterceptorResultStream<Request>

}

/// An error indicating that a ``GraphQLInterceptor`` emitted a result without calling its `next` closure, skipping
/// the remaining steps of the ``RequestChain``.
///
/// See [Calling `next` Is Required](<doc:GraphQLInterceptor#Calling-next-Is-Required>) for the supported ways to
/// supply results without performing a network fetch.
public struct GraphQLInterceptorDidNotCallNextError: Swift.Error, LocalizedError, CustomStringConvertible {

  /// The ``GraphQLInterceptor`` that emitted a result without calling `next`, if it could be identified.
  public let interceptor: (any GraphQLInterceptor)?

  /// The name of the operation the ``RequestChain`` was executing.
  public let operationName: String

  /// Designated initializer.
  ///
  /// - Parameters:
  ///   - interceptor: The ``GraphQLInterceptor`` that emitted a result without calling `next`, if it could be
  ///   identified.
  ///   - operationName: The name of the operation the ``RequestChain`` was executing.
  public init(interceptor: (any GraphQLInterceptor)?, operationName: String) {
    self.interceptor = interceptor
    self.operationName = operationName
  }

  public var description: String {
    let interceptorName = interceptor.map { "\(type(of: $0))" } ?? "A GraphQLInterceptor"

    return """
      \(interceptorName) emitted a result for operation "\(operationName)" without calling the `next` closure. \
      Every GraphQLInterceptor must call `next`, which is what runs the rest of the RequestChain — the remaining \
      interceptors, the cache read, the network fetch, and response parsing.

      To substitute a canned response, stub the ApolloURLSession instead of skipping the chain (see \
      MockApolloURLSession in ApolloTestSupport). To supply a result only when the fetch fails, call `next` and \
      recover with `mapErrors`. To serve results from the cache, use the request's `fetchBehavior` or a custom \
      CacheInterceptor. To abort the request, throw from `intercept(request:next:)`.
      """
  }

  public var errorDescription: String? { description }
}
