import Foundation
import Combine
#if !COCOAPODS
import ApolloAPI
#endif

/// An interceptor which parses JSON response data into a `GraphQLResult` and attaches it to the `HTTPResponse`.
public struct JSONResponseParsingInterceptor: ApolloInterceptor {

  public init() { }

  actor CurrentResult<Operation: GraphQLOperation> {
    var value: JSONResponseParser<Operation>.ParsedResult? = nil

    func set(_ value: JSONResponseParser<Operation>.ParsedResult) {
      self.value = value
    }
  }

  public func intercept<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    next: NextInterceptorFunction<Operation>
  ) async throws -> InterceptorResultStream<Operation> {

    let currentResult = CurrentResult<Operation>()

    return try await next(request).compactMap { result -> InterceptorResult<Operation>? in
      let parser = JSONResponseParser<Operation>(
        response: result.response,
        operationVariables: request.operation.__variables,
        includeCacheRecords: request.cachePolicy.shouldParsingIncludeCacheRecords
      )

      guard let parsedResult = try await parser.parse(
        dataChunk: result.rawResponseChunk,
        mergingIncrementalItemsInto: await currentResult.value
      ) else {
        return nil
      }

      await currentResult.set(parsedResult)
      return InterceptorResult(
        response: result.response,
        rawResponseChunk: result.rawResponseChunk,
        parsedResult: InterceptorResult.ParsedResult(
          result: parsedResult.0,
          cacheRecords: parsedResult.1
        ))
    }
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
