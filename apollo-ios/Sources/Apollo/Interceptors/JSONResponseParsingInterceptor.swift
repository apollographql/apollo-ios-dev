import Foundation
import Combine
#if !COCOAPODS
import ApolloAPI
#endif

/// An interceptor which parses JSON response data into a `GraphQLResult` and attaches it to the `HTTPResponse`.
public struct JSONResponseParsingInterceptor: ApolloInterceptor {

  public init() { }

  public func intercept<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    next: NextInterceptorFunction<Operation>
  ) async throws -> InterceptorResult<Operation> {
    var result = try await next(request)

    let parser = JSONResponseParser<Operation>(
      response: result.response,
      operationVariables: request.operation.__variables,
      includeCacheRecords: request.cachePolicy.shouldParsingIncludeCacheRecords
    )
    
    result.parsedResults = parser.parseJSONtoResults(
      fromByteStream: result.responseAsyncBytes
    ).map {
      InterceptorResult<Operation>.ParsedResult(result: $0, cacheRecords: $1)
    }

    return result
  }
}

fileprivate extension CachePolicy {
  var shouldParsingIncludeCacheRecords: Bool {
    switch self {
    case .fetchIgnoringCacheCompletely:
      return false

    default:
      return true
    }
  }
}
