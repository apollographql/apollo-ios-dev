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

  // MARK: - Row-per-element schema

  /// Writes the given records as rows in the row-per-element records
  /// table, in a single transaction. For each `(cacheKey, fieldName)`:
  ///
  /// - **Scalar fields** (`String`, `Int`, `Bool`, `Double`,
  ///   `CacheReference`, etc.) become a single row at the default
  ///   `position` value (`-1`).
  /// - **List-typed fields** are written as `N` rows at positions
  ///   `0..N-1`. The write is atomic: any existing rows for
  ///   `(cacheKey, fieldName)` are deleted before the new ones are
  ///   inserted, so a partial-list state is never observable to
  ///   readers and shape transitions (scalar↔list, longer-list →
  ///   shorter-list) leave no in-field orphans.
  /// - **Nested-list elements** (a list whose elements are themselves
  ///   lists, e.g. `[[Int]]`) recurse via a synthetic sub-record at
  ///   `<parent>.<field>.$[<position>]`. The parent row's
  ///   `child_key_value` points to the sub-record key. The sub-record
  ///   holds the inner list's element rows under the sentinel
  ///   `field_name = "$"`.
  ///
  /// Note: when overwriting a field whose previous value was a nested
  /// list, the synthetic sub-record rows are *not* cleaned up by this
  /// method. They remain in the database as orphans until a follow-up
  /// cascade-delete PR ships. Reads are unaffected — orphans are
  /// unreachable through `selectRecords`.
  ///
  /// If any row fails to bind or step, the whole transaction is rolled
  /// back so callers either see all writes applied or none.
  ///
  /// Requires the row-per-element records table (see
  /// `createNewRecordsTableIfNeeded()`).
  func insertOrUpdate(records: [Record]) throws

  /// Removes every row whose `cache_key` matches `cacheKey`.
  ///
  /// Synthetic sub-records (`<parent>.<field>.$[N]`) produced by
  /// nested-list writes against this `cacheKey` are *not* cascade-
  /// deleted by this method. If the record being deleted has list-
  /// typed fields with depth ≥ 2, the corresponding synthetic sub-
  /// record rows remain in the database as orphans (unreachable but
  /// persistent). A follow-up cascade-delete PR handles that
  /// cleanup. Reads are unaffected — orphans never surface through
  /// `selectRecords`.
  ///
  /// Distinct from the legacy `deleteRecord(for:)` by the column it
  /// targets; this method operates on the row-per-element schema's
  /// `cache_key`.
  func deleteRecord(forKey cacheKey: CacheKey) throws

  /// Removes every row whose `cache_key` matches the wildcard
  /// `pattern`. Comparison is case-insensitive (`COLLATE NOCASE`).
  /// `\`, `%`, and `_` in `pattern` are escaped so they match
  /// literally rather than acting as `LIKE` wildcards.
  func deleteRecords(matchingKey pattern: CacheKey) throws

}

extension SQLiteDatabase {

  public func addOrUpdateRecordString(_ recordString: String, for cacheKey: CacheKey) throws {
    try addOrUpdate(records: [(cacheKey, recordString)])
  }

}
