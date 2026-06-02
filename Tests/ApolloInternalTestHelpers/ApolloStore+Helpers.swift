@testable @_spi(Execution) import Apollo
import ApolloAPI

extension ApolloStore {

  /// Test-only helper that loads a whole `Record` for the given cache
  /// key by calling the underlying `NormalizedCache.loadRecords(...)`
  /// directly. The projection-driven `ReadTransaction.loadObject(forKey:
  /// selections:variables:)` requires a selection set; tests that
  /// just want to inspect a record's full stored state use this
  /// helper instead.
  public func loadRecord(forKey key: CacheKey) async throws -> Record {
    return try await withinReadTransaction { transaction in
      let records = try await transaction.readOnlyCache.loadRecords(forKeys: [key])
      guard let record = records[key] else {
        throw JSONDecodingError.missingValue
      }
      return record
    }
  }

}
