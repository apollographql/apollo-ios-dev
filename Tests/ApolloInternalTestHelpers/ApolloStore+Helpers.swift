@testable @_spi(Execution) import Apollo

extension ApolloStore {

  public func loadRecord(forKey key: CacheKey) async throws -> Record {
    return try await withinReadTransaction { transaction in
      return try await transaction.loadObject(forKey: key).get()
    }
  }
  
}
