import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// An interceptor which writes data to the cache, following the `HTTPRequest`'s `cachePolicy`.
public struct CacheWriteInterceptor: ApolloInterceptor {
  
  public enum CacheWriteError: Error, LocalizedError {
    case noResponseToParse
    
    public var errorDescription: String? {
      switch self {
      case .noResponseToParse:
        return "The Cache Write Interceptor was called before a response was received to be parsed. Double-check the order of your interceptors."
      }
    }
  }
  
  public let store: ApolloStore
  public var id: String = UUID().uuidString
  
  /// Designated initializer
  ///
  /// - Parameter store: The store to use when writing to the cache.
  public init(store: ApolloStore) {
    self.store = store
  }
  
  public func intercept<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    response: HTTPResponse<Operation>?
  ) async throws -> RequestChain.NextAction<Operation> {
    guard request.cachePolicy != .fetchIgnoringCacheCompletely else {
      // If we're ignoring the cache completely, we're not writing to it.
      return .proceed(request: request, response: response)
    }

    guard
      let createdResponse = response,
      let legacyResponse = createdResponse.legacyResponse else {
      throw CacheWriteError.noResponseToParse
    }

    let (_, records) = try legacyResponse.parseResult()
    try Task.checkCancellation()

    if let records = records {
      #warning("TODO: can we do this in the background, or do we need to wait for it to finish?")
      self.store.publish(records: records, identifier: request.contextIdentifier)
    }

    return .proceed(request: request, response: response)
  }
}
