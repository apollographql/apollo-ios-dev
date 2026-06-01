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
  /// A caller attempted to store a record whose cache key contains
  /// `SQLiteSchema.Records.syntheticKeyToken`, which is reserved for
  /// the synthetic sub-record keys the database generates internally
  /// for nested-list storage.
  case reservedCacheKey(key: String)

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
    case .reservedCacheKey(let key):
      return "Cache key '\(key)' contains '\(SQLiteSchema.Records.syntheticKeyToken)', which is reserved for synthetic sub-record keys, and cannot be stored"
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
  ///   inserted — including any reachable synthetic sub-records the
  ///   prior rows pointed at — so partial-list states are never
  ///   observable and shape transitions (scalar↔list, longer-list →
  ///   shorter-list, nested-list → anything) leave no orphans.
  /// - **Empty lists** (`[]`) become a single marker row at
  ///   `position = -2` (`SQLiteSchema.Records.emptyListPositionValue`)
  ///   with no value column populated, so a cached empty list stays
  ///   distinguishable from a field that was never written.
  /// - **Nested-list elements** (a list whose elements are themselves
  ///   lists, e.g. `[[Int]]`) recurse via a synthetic sub-record at
  ///   `<parent>.<field>.$[<position>]`. The parent row's
  ///   `child_key_value` points to the sub-record key. The sub-record
  ///   holds the inner list's element rows under the sentinel
  ///   `field_name = "$"`.
  ///
  /// Throws `SQLiteError.reservedCacheKey` — before any row is
  /// written — if any record's cache key contains the reserved
  /// synthetic-key token `SQLiteSchema.Records.syntheticKeyToken`
  /// (`.$[`). Reserving the token guarantees user records can never
  /// collide with the synthetic sub-record keys generated for
  /// nested-list storage.
  ///
  /// If any row fails to bind or step, the whole transaction is rolled
  /// back so callers either see all writes applied or none.
  ///
  /// Requires the row-per-element records table (see
  /// `createNewRecordsTableIfNeeded()`).
  func insertOrUpdate(records: [Record]) throws

  /// Removes every row whose `cache_key` matches `cacheKey`, plus
  /// every row of every synthetic sub-record reachable from those
  /// rows via `child_key_value` pointers matching the synthetic-key
  /// suffix (`.$[<integer>]`). Real (non-synthetic) `CacheReference`
  /// targets are *not* followed — those point to independent records
  /// that may be reachable from other cache keys and have their own
  /// lifecycle.
  ///
  /// Distinct from the legacy `deleteRecord(for:)` by the column it
  /// targets and the cascade behavior; this method operates on the
  /// row-per-element schema's `cache_key`.
  func deleteRecord(forKey cacheKey: CacheKey) throws

  /// Removes every row whose `cache_key` matches the wildcard
  /// `pattern`, plus every row of every synthetic sub-record
  /// reachable from those records via `child_key_value` pointers.
  /// Comparison is case-insensitive (`COLLATE NOCASE`). `\`, `%`,
  /// and `_` in `pattern` are escaped so they match literally
  /// rather than acting as `LIKE` wildcards. The synthetic cascade
  /// follows the same rule as `deleteRecord(forKey:)` — only
  /// synthetic-suffix children are removed; real `CacheReference`
  /// targets are left alone.
  func deleteRecords(matchingKey pattern: CacheKey) throws

}

extension SQLiteDatabase {

  public func addOrUpdateRecordString(_ recordString: String, for cacheKey: CacheKey) throws {
    try addOrUpdate(records: [(cacheKey, recordString)])
  }

}
