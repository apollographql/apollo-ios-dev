import Foundation
import Apollo

public struct DatabaseRow {
  let cacheKey: CacheKey
  let storedInfo: String

  public init(cacheKey: CacheKey, storedInfo: String) {
    self.cacheKey = cacheKey
    self.storedInfo = storedInfo
  }
}

public enum SQLiteError: Error, CustomStringConvertible {
  case execution(message: String, resultCode: Int32)
  case open(path: String, resultCode: Int32)
  case prepare(message: String, resultCode: Int32)
  case step(message: String, resultCode: Int32)
  
  public var description: String {
    switch self {
    case .execution(let message, _):
      return message
    case .open(let path, _):
      return "Failed to open SQLite database connection at path: \(path)"
    case .prepare(let message, _):
      return message
    case .step(let message, _):
      return message
    }
  }
}

public protocol SQLiteDatabase {

  init(fileURL: URL) throws

  func createRecordsTableIfNeeded() throws

  /// Creates the schema-metadata table if it doesn't exist. The table is a
  /// key/value store keyed on `String`; the only reserved key currently
  /// recognized is `version`, holding the integer schema version of the
  /// records table layout (read via `readSchemaVersion()`).
  func createSchemaMetadataTableIfNeeded() throws

  /// Returns the integer schema version stamped in the metadata table, or
  /// `0` when no row exists. Callers use the value to decide whether the
  /// stored data needs to be migrated to a newer schema layout.
  func readSchemaVersion() throws -> Int

  /// Writes the integer schema version into the metadata table, replacing
  /// any prior value. The metadata table must already exist; the caller is
  /// expected to call `createSchemaMetadataTableIfNeeded()` first.
  func writeSchemaVersion(_ version: Int) throws

  func selectRawRows(forKeys keys: Set<CacheKey>) throws -> [DatabaseRow]

  func addOrUpdate(records: [(cacheKey: CacheKey, recordString: String)]) throws

  func deleteRecord(for cacheKey: CacheKey) throws

  func deleteRecords(matching pattern: CacheKey) throws

  func clearDatabase(shouldVacuumOnClear: Bool) throws

  @available(*, deprecated, renamed: "addOrUpdate(records:)")
  func addOrUpdateRecordString(_ recordString: String, for cacheKey: CacheKey) throws

}

extension SQLiteDatabase {

  public func addOrUpdateRecordString(_ recordString: String, for cacheKey: CacheKey) throws {
    try addOrUpdate(records: [(cacheKey, recordString)])
  }

}

public extension SQLiteDatabase {

  static var tableName: String {
    "records"
  }

  static var idColumnName: String {
    "_id"
  }

  static var keyColumnName: String {
    "key"
  }

  static var recordColumName: String {
    "record"
  }

  static var schemaMetadataTableName: String {
    "schema_metadata"
  }

  static var schemaMetadataKeyColumnName: String {
    "key"
  }

  static var schemaMetadataValueColumnName: String {
    "value"
  }

  /// The metadata key under which the records-table schema version is stored.
  static var schemaVersionMetadataKey: String {
    "version"
  }
}
