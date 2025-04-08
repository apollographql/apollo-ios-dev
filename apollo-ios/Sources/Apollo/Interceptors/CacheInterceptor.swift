#if !COCOAPODS
import ApolloAPI
#endif

public protocol CacheInterceptor: Sendable {

  func readCacheData<Query: GraphQLQuery>(
    for query: Query
  ) async throws -> GraphQLResult<Query.Data>

  func writeCacheData<Operation: GraphQLOperation>(
    cacheRecords: RecordSet,
    for operation: Operation,
    with result: GraphQLResult<Operation.Data>
  ) async throws

}

public struct DefaultCacheInterceptor: CacheInterceptor {

  let store: ApolloStore

  public func readCacheData<Query: GraphQLQuery>(
    for query: Query
  ) async throws -> GraphQLResult<Query.Data> {
    try Task.checkCancellation()
    return try await store.load(query)
  }

  public func writeCacheData<Operation: GraphQLOperation>(
    cacheRecords: RecordSet,
    for operation: Operation,
    with result: GraphQLResult<Operation.Data>
  ) async throws {
    #warning("TODO: need to pass through context identifier. Can we use task local values?")
    try await store.publish(records: cacheRecords)
  }
  
}
