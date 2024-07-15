import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// An interceptor that reads data from the cache for queries, following the `HTTPRequest`'s `cachePolicy`.
public struct CacheReadInterceptor: ApolloInterceptor {

  private let store: ApolloStore

  public var id: String = UUID().uuidString
  
  /// Designated initializer
  ///
  /// - Parameter store: The store to use when reading from the cache.
  public init(store: ApolloStore) {
    self.store = store
  }
  
  public func intercept<Operation>(
    request: HTTPRequest<Operation>,
    response: HTTPResponse<Operation>?
  ) async throws -> RequestChain.NextAction<Operation> where Operation : ApolloAPI.GraphQLOperation {
      switch Operation.operationType {
      case .mutation,
          .subscription:
        // Mutations and subscriptions don't need to hit the cache.
        return .proceed(request: request, response: response)

      case .query:
        switch request.cachePolicy {
        case 
            .fetchIgnoringCacheCompletely,
            .fetchIgnoringCacheData:
          // Don't bother with the cache, just keep going
          return .proceed(request: request, response: response)

        case .returnCacheDataAndFetch:
          do {
            let result = try await self.fetchFromCache(for: request)
            return .proceedAndEmit(intermediaryResult: result, request: request, response: response)

          } catch {
            // Don't return a cache miss error, just keep going
            return .proceed(request: request, response: response)
          }

        case .returnCacheDataElseFetch:
          do {
            let result = try await self.fetchFromCache(for: request)

            // Cache hit! We're done.
            return .exitEarlyAndEmit(result: result, request: request)

          } catch {
            // Cache miss, proceed to network without returning error
            return .proceed(request: request, response: response)
          }

        case .returnCacheDataDontFetch:
          do {
            let result = try await self.fetchFromCache(for: request)

            // Cache hit! We're done.
            return .exitEarlyAndEmit(result: result, request: request)

          } catch {
            // Don't return a cache miss error, just keep going
            throw error
          }

        }
      }
    }
  
  private func fetchFromCache<Operation: GraphQLOperation>(
    for request: HTTPRequest<Operation>
  ) async throws -> GraphQLResult<Operation.Data> {
    try await withCheckedThrowingContinuation { continuation in
      self.store.load(request.operation) { loadResult in
        guard !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }

        continuation.resume(with: loadResult)
      }
    }
  }
}
