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

  /// Creates the row-per-field records table if it doesn't exist, and
  /// stamps `SQLiteSchema.Metadata.versionKey` with `SQLiteSchema.currentVersion`.
  /// The table uses a composite `(cache_key, field_name)` primary key and is
  /// declared `WITHOUT ROWID` so rows for one record cluster on disk in
  /// primary-key order, which keeps batched reads sequential.
  ///
  /// The caller must ensure the schema-metadata table already exists
  /// (call `createSchemaMetadataTableIfNeeded()` first).
  func createNewRecordsTableIfNeeded() throws

  /// Creates the schema-metadata table if it doesn't exist. The table is a
  /// key/value store keyed on `String`; the only reserved key currently
  /// recognized is `SQLiteSchema.Metadata.versionKey`, holding the
  /// `SchemaVersion` of the records-table layout (read via `readSchemaVersion()`).
  func createSchemaMetadataTableIfNeeded() throws

  /// Returns the `SchemaVersion` stamped in the metadata table, or `nil` if
  /// no version row exists or the stored value cannot be parsed. Callers
  /// use the value to decide whether the stored data needs to be migrated
  /// to a newer schema layout.
  func readSchemaVersion() throws -> SchemaVersion?

  /// Writes the `SchemaVersion` into the metadata table, replacing any
  /// prior value. The metadata table must already exist; the caller is
  /// expected to call `createSchemaMetadataTableIfNeeded()` first.
  func writeSchemaVersion(_ version: SchemaVersion) throws

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
