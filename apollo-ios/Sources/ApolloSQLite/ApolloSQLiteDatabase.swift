import Foundation
@_spi(Execution) import Apollo
import SQLite3

public final class ApolloSQLiteDatabase: SQLiteDatabase {
  
  private final class DBContextToken: Sendable {}

  private var db: OpaquePointer?
  private let dbURL: URL

  private let dbQueue = DispatchQueue(label: "com.apollo.sqlite.database")
  private static let dbContextKey = DispatchSpecificKey<DBContextToken>()
  private let dbContextValue = DBContextToken()

  let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  public init(fileURL: URL) throws {
    self.dbURL = fileURL
    try openConnection()
    dbQueue.setSpecific(key: Self.dbContextKey, value: dbContextValue)
  }

  deinit {
    sqlite3_close(db)
  }

  /// Closes the underlying SQLite connection. After calling this, the database
  /// must not be used for further operations. Intended for test teardown
  /// scenarios where the database file is about to be unlinked — closing the
  /// connection before unlink prevents libsqlite3's "vnode unlinked while in
  /// use" diagnostic from firing.
  @_spi(Testing)
  public func close() {
    dbQueue.sync {
      sqlite3_close(db)
      db = nil
    }
  }

  // MARK: - Internal Helpers

  private func performSync<T>(_ block: () throws -> T) throws -> T {
    if DispatchQueue.getSpecific(key: Self.dbContextKey) === dbContextValue {
      return try block()
    } else {
      return try dbQueue.sync(execute: block)
    }
  }

  private func openConnection() throws {
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI
    let result = sqlite3_open_v2(dbURL.path, &db, flags, nil)
    if result != SQLITE_OK {
      throw SQLiteError.open(path: dbURL.path, resultCode: result)
    }
  }

  private func rollbackTransaction() {
    sqlite3_exec(db, "ROLLBACK TRANSACTION", nil, nil, nil)
  }

  private func sqliteErrorMessage() -> String {
    return String(cString: sqlite3_errmsg(db))
  }

  @discardableResult
  private func exec(_ sql: String, errorMessage: @autoclosure () -> String) throws -> Int32 {
    let result = sqlite3_exec(db, sql, nil, nil, nil)
    if result != SQLITE_OK {
      throw SQLiteError.execution(message: "\(errorMessage()): \(sqliteErrorMessage())", resultCode: result)
    }
    return result
  }

  private func prepareStatement(_ sql: String, errorMessage: @autoclosure () -> String) throws -> OpaquePointer? {
    var stmt: OpaquePointer?
    let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    if result != SQLITE_OK {
      throw SQLiteError.prepare(message: "\(errorMessage()): \(sqliteErrorMessage())", resultCode: result)
    }
    return stmt
  }

  // MARK: - SQLiteDatabase Protocol

  public func createRecordsTableIfNeeded() throws {
    try performSync {
      let sql = """
      CREATE TABLE IF NOT EXISTS "\(SQLiteSchema.recordsTableName)" (
        "\(SQLiteSchema.LegacyRecords.id)"      INTEGER,
        "\(SQLiteSchema.LegacyRecords.key)"     TEXT UNIQUE,
        "\(SQLiteSchema.LegacyRecords.record)"  TEXT,
        PRIMARY KEY("\(SQLiteSchema.LegacyRecords.id)" AUTOINCREMENT)
      );
      """
      try exec(sql, errorMessage: "Failed to create '\(SQLiteSchema.recordsTableName)' database table")
    }
  }

  public func createNewRecordsTableIfNeeded() throws {
    try performSync {
      let sql = """
      CREATE TABLE IF NOT EXISTS "\(SQLiteSchema.recordsTableName)" (
        "\(SQLiteSchema.Records.cacheKey)"           TEXT NOT NULL,
        "\(SQLiteSchema.Records.fieldName)"          TEXT NOT NULL,
        "\(SQLiteSchema.Records.position)"           INTEGER NOT NULL DEFAULT \(SQLiteSchema.Records.defaultPositionValue),
        "\(SQLiteSchema.Records.intValue)"           INTEGER,
        "\(SQLiteSchema.Records.stringValue)"        TEXT,
        "\(SQLiteSchema.Records.floatValue)"         REAL,
        "\(SQLiteSchema.Records.boolValue)"          INTEGER,
        "\(SQLiteSchema.Records.childKeyValue)"      TEXT,
        "\(SQLiteSchema.Records.customScalarValue)"  TEXT,
        "\(SQLiteSchema.Records.writtenAt)"          INTEGER NOT NULL,
        PRIMARY KEY (
          "\(SQLiteSchema.Records.cacheKey)",
          "\(SQLiteSchema.Records.fieldName)",
          "\(SQLiteSchema.Records.position)"
        )
      ) WITHOUT ROWID;
      """
      try exec(sql, errorMessage: "Failed to create row-per-element '\(SQLiteSchema.recordsTableName)' database table")
    }
    try writeSchemaVersion(SQLiteSchema.currentVersion)
  }

  public func createSchemaMetadataTableIfNeeded() throws {
    try performSync {
      let sql = """
      CREATE TABLE IF NOT EXISTS "\(SQLiteSchema.Metadata.tableName)" (
        "\(SQLiteSchema.Metadata.keyColumn)"   TEXT PRIMARY KEY,
        "\(SQLiteSchema.Metadata.valueColumn)" TEXT
      );
      """
      try exec(sql, errorMessage: "Failed to create '\(SQLiteSchema.Metadata.tableName)' database table")
    }
  }

  public func readSchemaVersion() throws -> SchemaVersion? {
    try performSync {
      let sql = """
      SELECT \(SQLiteSchema.Metadata.valueColumn)
      FROM \(SQLiteSchema.Metadata.tableName)
      WHERE \(SQLiteSchema.Metadata.keyColumn) = ?
      """

      let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare schema-version read")
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_text(stmt, 1, SQLiteSchema.Metadata.versionKey, -1, SQLITE_TRANSIENT)

      let stepResult = sqlite3_step(stmt)
      switch stepResult {
      case SQLITE_DONE:
        // No row stored for the schema-version key.
        return nil
      case SQLITE_ROW:
        guard let textPtr = sqlite3_column_text(stmt, 0) else {
          return nil
        }
        return SchemaVersion(String(cString: textPtr))
      default:
        throw SQLiteError.step(
          message: "Schema-version read failed: \(sqliteErrorMessage())",
          resultCode: stepResult
        )
      }
    }
  }

  public func writeSchemaVersion(_ version: SchemaVersion) throws {
    try performSync {
      let sql = """
      INSERT INTO \(SQLiteSchema.Metadata.tableName) (\(SQLiteSchema.Metadata.keyColumn), \(SQLiteSchema.Metadata.valueColumn))
      VALUES (?, ?)
      ON CONFLICT(\(SQLiteSchema.Metadata.keyColumn)) DO UPDATE SET \(SQLiteSchema.Metadata.valueColumn) = excluded.\(SQLiteSchema.Metadata.valueColumn)
      """

      let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare schema-version write")
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_text(stmt, 1, SQLiteSchema.Metadata.versionKey, -1, SQLITE_TRANSIENT)
      sqlite3_bind_text(stmt, 2, version.description, -1, SQLITE_TRANSIENT)

      let stepResult = sqlite3_step(stmt)
      if stepResult != SQLITE_DONE {
        throw SQLiteError.step(
          message: "Schema-version write failed: \(sqliteErrorMessage())",
          resultCode: stepResult
        )
      }
    }
  }

  public func selectRawRows(forKeys keys: Set<CacheKey>) throws -> [DatabaseRow] {
      guard !keys.isEmpty else { return [] }

      let batchSize = 500
      var allRows = [DatabaseRow]()
      let keyBatches = keys.chunked(into: batchSize)

      for batch in keyBatches {
        let rows = try performSync {
          let placeholders = batch.map { _ in "?" }.joined(separator: ", ")
          let sql = """
          SELECT \(SQLiteSchema.LegacyRecords.key), \(SQLiteSchema.LegacyRecords.record)
          FROM \(SQLiteSchema.recordsTableName)
          WHERE \(SQLiteSchema.LegacyRecords.key) IN (\(placeholders))
          """

          let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare select statement")
          defer { sqlite3_finalize(stmt) }

          for (index, key) in batch.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), key, -1, SQLITE_TRANSIENT)
          }

          var rows = [DatabaseRow]()
          var result: Int32
          repeat {
            result = sqlite3_step(stmt)
            if result == SQLITE_ROW {
              let key = String(cString: sqlite3_column_text(stmt, 0))
              let record = String(cString: sqlite3_column_text(stmt, 1))
              rows.append(DatabaseRow(cacheKey: key, storedInfo: record))
            } else if result != SQLITE_DONE {
              let errorMsg = String(cString: sqlite3_errmsg(db))
              throw SQLiteError.step(message: "Failed to step raw row select: \(errorMsg)", resultCode: result)
            }
          } while result != SQLITE_DONE

          return rows
        }

        allRows.append(contentsOf: rows)
      }

      return allRows
  }

  public func addOrUpdate(records: [(cacheKey: CacheKey, recordString: String)]) throws {
    guard !records.isEmpty else { return }

    try performSync {
      let sql = """
      INSERT INTO \(SQLiteSchema.recordsTableName) (\(SQLiteSchema.LegacyRecords.key), \(SQLiteSchema.LegacyRecords.record))
      VALUES (?, ?)
      ON CONFLICT(\(SQLiteSchema.LegacyRecords.key)) DO UPDATE SET \(SQLiteSchema.LegacyRecords.record) = excluded.\(SQLiteSchema.LegacyRecords.record)
      """

      try exec("BEGIN TRANSACTION", errorMessage: "Failed to begin insert/update transaction")

      let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare insert/update statement")
      defer { sqlite3_finalize(stmt) }

      for (key, record) in records {
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, record, -1, SQLITE_TRANSIENT)

        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE {
          rollbackTransaction()
          throw SQLiteError.step(message: "Insert/update failed: \(sqliteErrorMessage())", resultCode: result)
        }

        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
      }

      do {
        try exec("COMMIT TRANSACTION", errorMessage: "Failed to commit transaction")
      } catch {
        rollbackTransaction()
        throw error
      }
    }
  }

  public func deleteRecord(for cacheKey: CacheKey) throws {
    try performSync {
      let sql = "DELETE FROM \(SQLiteSchema.recordsTableName) WHERE \(SQLiteSchema.LegacyRecords.key) = ?"
      let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare delete statement")
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_text(stmt, 1, cacheKey, -1, SQLITE_TRANSIENT)
      let result = sqlite3_step(stmt)
      if result != SQLITE_DONE {
        throw SQLiteError.step(message: "Delete failed: \(sqliteErrorMessage())", resultCode: result)
      }
    }
  }

  public func deleteRecords(matching pattern: CacheKey) throws {
    guard !pattern.isEmpty else { return }
    let wildcardPattern = "%\(pattern)%"

    try performSync {
      let sql = "DELETE FROM \(SQLiteSchema.recordsTableName) WHERE \(SQLiteSchema.LegacyRecords.key) LIKE ? COLLATE NOCASE"
      let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare delete pattern statement")
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_text(stmt, 1, wildcardPattern, -1, SQLITE_TRANSIENT)
      let result = sqlite3_step(stmt)
      if result != SQLITE_DONE {
        throw SQLiteError.step(message: "Pattern delete failed: \(sqliteErrorMessage())", resultCode: result)
      }
    }
  }

  public func clearDatabase(shouldVacuumOnClear: Bool) throws {
    try performSync {
      try exec("DELETE FROM \(SQLiteSchema.recordsTableName)", errorMessage: "Failed to clear database")
      if shouldVacuumOnClear {
        try exec("VACUUM;", errorMessage: "Failed to vacuum database")
      }
    }
  }

  public func setJournalMode(mode: JournalMode) throws {
    try performSync {
      _ = try exec("PRAGMA journal_mode = \(mode.rawValue);", errorMessage: "Failed to set journal mode")
    }
  }

  // MARK: - Row-per-element schema

  public func insertOrUpdate(records: [Record]) throws {
    guard !records.isEmpty else { return }

    // Reserved-key audit (ADR 0006): `.$[` is reserved for the
    // synthetic sub-record keys generated for nested-list storage.
    // Rejecting user keys that contain the token guarantees the
    // synthetic-key classifiers (`syntheticKeySuffixPattern` and
    // `syntheticKeySuffixLikePattern`) can never match a stored user
    // record. Checked before the transaction opens so a bad key in a
    // batch writes nothing.
    for record in records {
      if record.key.contains(SQLiteSchema.Records.syntheticKeyToken) {
        throw SQLiteError.reservedCacheKey(key: record.key)
      }
    }

    try performSync {
      try exec("BEGIN TRANSACTION", errorMessage: "Failed to begin insertOrUpdate transaction")
      do {
        for record in records {
          for (fieldName, cachedField) in record.fields {
            try writeFieldOrList(
              cacheKey: record.key,
              fieldName: fieldName,
              value: cachedField.value,
              writtenAt: cachedField.writtenAt
            )
          }
        }
      } catch {
        rollbackTransaction()
        throw error
      }
      do {
        try exec("COMMIT TRANSACTION", errorMessage: "Failed to commit insertOrUpdate transaction")
      } catch {
        rollbackTransaction()
        throw error
      }
    }
  }

  public func deleteRecord(forKey cacheKey: CacheKey) throws {
    // Direct delete only — synthetic sub-records (`<parent>.<field>.$[N]`)
    // produced by nested-list writes are not cascaded here. If the
    // record being deleted has list-typed fields with depth ≥ 2, the
    // corresponding synthetic sub-record rows remain in the database
    // as orphans. They are unreachable from any cache key after this
    // delete (the parent's `child_key_value` pointers are gone) but
    // they take up storage until a follow-up cascade-delete PR cleans
    // them up. Reads are unaffected — orphans never surface through
    // `selectRecords`.
    try performSync {
      try directDelete(cacheKey: cacheKey)
    }
  }

  public func deleteRecords(matchingKey pattern: CacheKey) throws {
    guard !pattern.isEmpty else { return }
    // `LIKE` treats `%` and `_` as wildcards. Escape them (along with
    // the escape character itself) so callers passing a literal
    // substring like "User_" don't accidentally delete "UserA1",
    // "User:1", "Users", etc.
    let escaped = pattern
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
    let wildcardPattern = "%\(escaped)%"

    try performSync {
      let sql = """
      DELETE FROM \(SQLiteSchema.recordsTableName)
      WHERE \(SQLiteSchema.Records.cacheKey) LIKE ? COLLATE NOCASE ESCAPE '\\'
      """
      let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare row-per-element pattern delete")
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_text(stmt, 1, wildcardPattern, -1, SQLITE_TRANSIENT)
      let result = sqlite3_step(stmt)
      if result != SQLITE_DONE {
        throw SQLiteError.step(message: "Row-per-element pattern delete failed: \(sqliteErrorMessage())", resultCode: result)
      }
    }
  }

  /// Per-ADR 0007 projection-aware read. Two SQL statements inside
  /// one `performSync`: an existence probe so the caller can tell
  /// "record absent" from "record present, field missing", then a
  /// row-filter `SELECT` that fetches only the requested
  /// `(cacheKey, fieldName)` pairs. Synthetic sub-record references
  /// in the returned rows are resolved transparently via
  /// `resolveSyntheticIfNeeded`, so nested-list fields materialize
  /// in their assembled form.
  @_spi(Execution)
  public func selectFields(_ projections: [FieldProjection]) throws -> [CacheKey: Record] {
    guard !projections.isEmpty else { return [:] }

    // Dedupe early so duplicate projections coalesce to one SQL bind.
    let uniqueProjections = Set(projections)
    let requestedKeys = Set(uniqueProjections.map(\.cacheKey))

    return try performSync {
      let existingKeys = try selectExistingKeys(requestedKeys)

      // No matching records exist — short-circuit before the
      // projection query so we don't issue a `WHERE (...) IN ()`
      // (SQLite rejects an empty IN-list anyway, and the result
      // would be empty regardless).
      guard !existingKeys.isEmpty else { return [:] }

      let projectedRows = try selectProjectedRows(Array(uniqueProjections))
      let assembled = try assembleRecords(from: projectedRows)
      let assembledByKey = Dictionary(uniqueKeysWithValues: assembled.map { ($0.key, $0) })

      var result: [CacheKey: Record] = [:]
      result.reserveCapacity(existingKeys.count)
      for key in existingKeys {
        // Honor `loadFields`'s contract: a record that exists but
        // has none of the requested fields surfaces with empty
        // `fields`. The caller's executor needs this to distinguish
        // a per-field `missingValue` error (record present, field
        // missing) from a record-level lookup miss.
        result[key] = assembledByKey[key] ?? Record(key: key, fields: [:])
      }
      return result
    }
  }

  /// Runs the existence-probe SQL: `SELECT DISTINCT cache_key …
  /// WHERE cache_key IN (?, ?, …)`. The result tells the caller
  /// which of the requested cache keys correspond to records that
  /// actually exist in the database.
  private func selectExistingKeys(_ keys: Set<CacheKey>) throws -> Set<CacheKey> {
    guard !keys.isEmpty else { return [] }
    let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ", ")
    let sql = """
    SELECT DISTINCT \(SQLiteSchema.Records.cacheKey)
    FROM \(SQLiteSchema.recordsTableName)
    WHERE \(SQLiteSchema.Records.cacheKey) IN (\(placeholders))
    """
    let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare existence-probe select")
    defer { sqlite3_finalize(stmt) }

    var bindIdx: Int32 = 1
    for key in keys {
      sqlite3_bind_text(stmt, bindIdx, key, -1, SQLITE_TRANSIENT)
      bindIdx += 1
    }

    var result: Set<CacheKey> = []
    var step = sqlite3_step(stmt)
    while step == SQLITE_ROW {
      if let ptr = sqlite3_column_text(stmt, 0) {
        result.insert(String(cString: ptr))
      }
      step = sqlite3_step(stmt)
    }
    if step != SQLITE_DONE {
      throw SQLiteError.step(
        message: "Existence-probe step failed: \(sqliteErrorMessage())",
        resultCode: step
      )
    }
    return result
  }

  /// Runs the projection SQL: `SELECT … WHERE (cache_key, field_name)
  /// IN (VALUES (?, ?), (?, ?), …)`. Returns the raw rows; assembly
  /// happens in the caller via the shared `assembleRecords` helper.
  private func selectProjectedRows<C: Collection>(_ projections: C) throws -> [DecodedRow]
  where C.Element == FieldProjection {
    guard !projections.isEmpty else { return [] }

    let valuesClause = Array(repeating: "(?, ?)", count: projections.count).joined(separator: ", ")
    let sql = """
    SELECT
      \(SQLiteSchema.Records.cacheKey),
      \(SQLiteSchema.Records.fieldName),
      \(SQLiteSchema.Records.position),
      \(SQLiteSchema.Records.intValue),
      \(SQLiteSchema.Records.stringValue),
      \(SQLiteSchema.Records.floatValue),
      \(SQLiteSchema.Records.boolValue),
      \(SQLiteSchema.Records.childKeyValue),
      \(SQLiteSchema.Records.customScalarValue),
      \(SQLiteSchema.Records.writtenAt)
    FROM \(SQLiteSchema.recordsTableName)
    WHERE (\(SQLiteSchema.Records.cacheKey), \(SQLiteSchema.Records.fieldName))
      IN (VALUES \(valuesClause))
    ORDER BY \(SQLiteSchema.Records.cacheKey),
             \(SQLiteSchema.Records.fieldName),
             \(SQLiteSchema.Records.position)
    """
    let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare projection select")
    defer { sqlite3_finalize(stmt) }

    var bindIdx: Int32 = 1
    for projection in projections {
      sqlite3_bind_text(stmt, bindIdx, projection.cacheKey, -1, SQLITE_TRANSIENT)
      sqlite3_bind_text(stmt, bindIdx + 1, projection.fieldName, -1, SQLITE_TRANSIENT)
      bindIdx += 2
    }

    return try readDecodedRows(stmt: stmt)
  }

  /// Test-only read path: loads every row for the given cache keys,
  /// reassembles them into `Record` instances, and follows synthetic
  /// sub-record `child_key_value` pointers to materialize nested lists.
  /// **Not part of the `SQLiteDatabase` public protocol** — production
  /// reads use ``selectFields(_:)``. Retained as test infrastructure
  /// for the row-per-element CRUD tests until PR-009h.
  internal func selectRecords(forKeys keys: Set<CacheKey>) throws -> [Record] {
    guard !keys.isEmpty else { return [] }

    var records: [Record] = []
    for batch in keys.chunked(into: 500) {
      let batchRecords = try performSync {
        try loadRecordBatch(Set(batch))
      }
      // Filter out synthetic sub-records — they're consumed by their
      // parent's nested-list assembly via `resolveSyntheticIfNeeded`
      // and shouldn't surface as top-level records to callers.
      records.append(contentsOf: batchRecords.filter { !Self.isSyntheticKey($0.key) })
    }
    return records
  }

  // MARK: - Row-per-element internals

  /// Writes one field's value, choosing the right row shape:
  /// - scalars get one row at `position = -1`
  /// - list-typed values get N rows at positions `0..N-1`
  /// - empty lists get a single marker row at `position = -2` with no
  ///   value column populated, so `[]` stays distinguishable from a
  ///   never-written field
  /// - nested-list elements recurse via a synthetic sub-record
  ///
  /// Any prior rows for `(cacheKey, fieldName)` are cleared first so
  /// shape transitions (scalar → list, list → scalar, longer-list →
  /// shorter-list) leave no in-field orphans. The clear-then-write
  /// happens inside the caller's transaction so partial states are
  /// never observable to readers.
  ///
  /// Note: this implementation does NOT cascade-clean synthetic sub-
  /// records pointed to by the previous rows. If the prior value was
  /// a list with depth ≥ 2, those synthetic sub-record rows remain
  /// in the database as orphans (unreachable but persistent). A
  /// follow-up cascade-delete PR handles that cleanup.
  private func writeFieldOrList(
    cacheKey: CacheKey,
    fieldName: String,
    value: Record.Value,
    writtenAt: Int64
  ) throws {
    try directDelete(cacheKey: cacheKey, fieldName: fieldName)

    if let array = value as? [Record.Value] {
      guard !array.isEmpty else {
        try upsertRow(
          cacheKey: cacheKey,
          fieldName: fieldName,
          position: SQLiteSchema.Records.emptyListPositionValue,
          typedValue: nil,
          writtenAt: writtenAt
        )
        return
      }
      for (idx, element) in array.enumerated() {
        try writeElement(
          cacheKey: cacheKey,
          fieldName: fieldName,
          position: Int64(idx),
          element: element,
          writtenAt: writtenAt
        )
      }
    } else {
      try writeElement(
        cacheKey: cacheKey,
        fieldName: fieldName,
        position: SQLiteSchema.Records.defaultPositionValue,
        element: value,
        writtenAt: writtenAt
      )
    }
  }

  /// Writes one row's worth of data: either a leaf typed value, or a
  /// nested list which becomes a synthetic sub-record linked via
  /// `child_key_value`.
  private func writeElement(
    cacheKey: CacheKey,
    fieldName: String,
    position: Int64,
    element: Record.Value,
    writtenAt: Int64
  ) throws {
    if let nestedArray = element as? [Record.Value] {
      let syntheticKey = syntheticSubRecordKey(
        parentCacheKey: cacheKey,
        parentFieldName: fieldName,
        position: position
      )
      try writeFieldOrList(
        cacheKey: syntheticKey,
        fieldName: SQLiteSchema.Records.syntheticFieldName,
        value: nestedArray as Record.Value,
        writtenAt: writtenAt
      )
      try upsertRow(
        cacheKey: cacheKey,
        fieldName: fieldName,
        position: position,
        typedValue: .childKey(syntheticKey),
        writtenAt: writtenAt
      )
    } else {
      let typedValue = try SQLiteFieldEncoding.encode(element)
      try upsertRow(
        cacheKey: cacheKey,
        fieldName: fieldName,
        position: position,
        typedValue: typedValue,
        writtenAt: writtenAt
      )
    }
  }

  /// Constructs a synthetic sub-record cache key. If the parent is
  /// already a synthetic sub-record (`fieldName` is the sentinel `$`),
  /// the new key just appends `.$[<position>]` to keep the synthetic
  /// chain readable. Otherwise the new key embeds the parent field
  /// name: `<parentCacheKey>.<parentFieldName>.$[<position>]`.
  private func syntheticSubRecordKey(
    parentCacheKey: CacheKey,
    parentFieldName: String,
    position: Int64
  ) -> CacheKey {
    if parentFieldName == SQLiteSchema.Records.syntheticFieldName {
      return "\(parentCacheKey).$[\(position)]"
    } else {
      return "\(parentCacheKey).\(parentFieldName).$[\(position)]"
    }
  }

  /// Issues one UPSERT against the records table for a single row.
  /// `ON CONFLICT (cache_key, field_name, position) DO UPDATE` copies
  /// every value column from `excluded.*`, so a field changing type
  /// (e.g. Int → String at the same position) also clears its prior
  /// column.
  ///
  /// A `nil` `typedValue` binds no value column (unbound parameters
  /// are NULL) and is valid only for the empty-list marker row at
  /// `position = -2` — the marker's meaning is carried entirely by
  /// its `position`.
  private func upsertRow(
    cacheKey: CacheKey,
    fieldName: String,
    position: Int64,
    typedValue: SQLiteFieldEncoding.TypedValue?,
    writtenAt: Int64
  ) throws {
    let sql = """
    INSERT INTO \(SQLiteSchema.recordsTableName) (
      \(SQLiteSchema.Records.cacheKey),
      \(SQLiteSchema.Records.fieldName),
      \(SQLiteSchema.Records.position),
      \(SQLiteSchema.Records.intValue),
      \(SQLiteSchema.Records.stringValue),
      \(SQLiteSchema.Records.floatValue),
      \(SQLiteSchema.Records.boolValue),
      \(SQLiteSchema.Records.childKeyValue),
      \(SQLiteSchema.Records.customScalarValue),
      \(SQLiteSchema.Records.writtenAt)
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(
      \(SQLiteSchema.Records.cacheKey),
      \(SQLiteSchema.Records.fieldName),
      \(SQLiteSchema.Records.position)
    ) DO UPDATE SET
      \(SQLiteSchema.Records.intValue)          = excluded.\(SQLiteSchema.Records.intValue),
      \(SQLiteSchema.Records.stringValue)       = excluded.\(SQLiteSchema.Records.stringValue),
      \(SQLiteSchema.Records.floatValue)        = excluded.\(SQLiteSchema.Records.floatValue),
      \(SQLiteSchema.Records.boolValue)         = excluded.\(SQLiteSchema.Records.boolValue),
      \(SQLiteSchema.Records.childKeyValue)     = excluded.\(SQLiteSchema.Records.childKeyValue),
      \(SQLiteSchema.Records.customScalarValue) = excluded.\(SQLiteSchema.Records.customScalarValue),
      \(SQLiteSchema.Records.writtenAt)         = excluded.\(SQLiteSchema.Records.writtenAt)
    """
    let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare record-row upsert")
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, cacheKey, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 2, fieldName, -1, SQLITE_TRANSIENT)
    sqlite3_bind_int64(stmt, 3, position)

    switch typedValue {
    case .int(let v):           sqlite3_bind_int64(stmt, 4, v)
    case .string(let v):        sqlite3_bind_text(stmt, 5, v, -1, SQLITE_TRANSIENT)
    case .float(let v):         sqlite3_bind_double(stmt, 6, v)
    case .bool(let v):          sqlite3_bind_int64(stmt, 7, v ? 1 : 0)
    case .childKey(let v):      sqlite3_bind_text(stmt, 8, v, -1, SQLITE_TRANSIENT)
    case .customScalar(let v):  sqlite3_bind_text(stmt, 9, v, -1, SQLITE_TRANSIENT)
    case nil:                   break  // empty-list marker: all value columns NULL
    }

    sqlite3_bind_int64(stmt, 10, writtenAt)

    let result = sqlite3_step(stmt)
    if result != SQLITE_DONE {
      throw SQLiteError.step(message: "Record-row upsert failed: \(sqliteErrorMessage())", resultCode: result)
    }
  }

  /// Deletes the rows for a given cache key (and optional field). Does
  /// not cascade synthetic sub-records — that's a follow-up PR.
  private func directDelete(cacheKey: CacheKey, fieldName: String? = nil) throws {
    let sql: String
    if fieldName == nil {
      sql = "DELETE FROM \(SQLiteSchema.recordsTableName) WHERE \(SQLiteSchema.Records.cacheKey) = ?"
    } else {
      sql = "DELETE FROM \(SQLiteSchema.recordsTableName) WHERE \(SQLiteSchema.Records.cacheKey) = ? AND \(SQLiteSchema.Records.fieldName) = ?"
    }
    let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare direct delete")
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, cacheKey, -1, SQLITE_TRANSIENT)
    if let fieldName {
      sqlite3_bind_text(stmt, 2, fieldName, -1, SQLITE_TRANSIENT)
    }
    let result = sqlite3_step(stmt)
    if result != SQLITE_DONE {
      throw SQLiteError.step(message: "Direct delete failed: \(sqliteErrorMessage())", resultCode: result)
    }
  }

  // MARK: - Row-per-element read assembly (test-only)

  /// Loads all rows for a batch of cache keys and groups them back
  /// into `Record` instances. Follows synthetic `child_key_value`
  /// pointers to materialize nested lists.
  private func loadRecordBatch(_ keys: Set<CacheKey>) throws -> [Record] {
    let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ", ")
    let sql = """
    SELECT
      \(SQLiteSchema.Records.cacheKey),
      \(SQLiteSchema.Records.fieldName),
      \(SQLiteSchema.Records.position),
      \(SQLiteSchema.Records.intValue),
      \(SQLiteSchema.Records.stringValue),
      \(SQLiteSchema.Records.floatValue),
      \(SQLiteSchema.Records.boolValue),
      \(SQLiteSchema.Records.childKeyValue),
      \(SQLiteSchema.Records.customScalarValue),
      \(SQLiteSchema.Records.writtenAt)
    FROM \(SQLiteSchema.recordsTableName)
    WHERE \(SQLiteSchema.Records.cacheKey) IN (\(placeholders))
    ORDER BY \(SQLiteSchema.Records.cacheKey),
             \(SQLiteSchema.Records.fieldName),
             \(SQLiteSchema.Records.position)
    """
    let stmt = try prepareStatement(sql, errorMessage: "Failed to prepare row-per-element select")
    defer { sqlite3_finalize(stmt) }

    var bindIdx: Int32 = 1
    for key in keys {
      sqlite3_bind_text(stmt, bindIdx, key, -1, SQLITE_TRANSIENT)
      bindIdx += 1
    }

    let rawRows = try readDecodedRows(stmt: stmt)
    return try assembleRecords(from: rawRows)
  }

  /// Iterates a prepared `SELECT` whose column order matches the
  /// row-per-element schema's `cache_key, field_name, position,
  /// int_value, string_value, float_value, bool_value, child_key_value,
  /// custom_scalar_value, written_at` projection and decodes each
  /// row into a `DecodedRow`.
  private func readDecodedRows(stmt: OpaquePointer?) throws -> [DecodedRow] {
    var rawRows: [DecodedRow] = []
    var step = sqlite3_step(stmt)
    while step == SQLITE_ROW {
      guard let cacheKeyPtr = sqlite3_column_text(stmt, 0) else {
        throw SQLiteError.step(message: "Unexpected NULL cache_key in row-per-element select", resultCode: SQLITE_NOMEM)
      }
      guard let fieldNamePtr = sqlite3_column_text(stmt, 1) else {
        throw SQLiteError.step(message: "Unexpected NULL field_name in row-per-element select", resultCode: SQLITE_NOMEM)
      }
      let cacheKey = String(cString: cacheKeyPtr)
      let fieldName = String(cString: fieldNamePtr)
      let position = sqlite3_column_int64(stmt, 2)
      let value: Record.Value
      if position == SQLiteSchema.Records.emptyListPositionValue {
        // Empty-list marker rows populate no value column; the
        // position alone carries the meaning.
        value = ([] as [Record.Value]) as Record.Value
      } else {
        value = try SQLiteFieldEncoding.decode(
          boolValue: Self.optionalInt64(stmt: stmt, column: 6),
          intValue: Self.optionalInt64(stmt: stmt, column: 3),
          floatValue: Self.optionalDouble(stmt: stmt, column: 5),
          stringValue: Self.optionalText(stmt: stmt, column: 4),
          childKeyValue: Self.optionalText(stmt: stmt, column: 7),
          customScalarValue: Self.optionalText(stmt: stmt, column: 8)
        )
      }
      let writtenAt = sqlite3_column_int64(stmt, 9)
      rawRows.append(DecodedRow(
        cacheKey: cacheKey, fieldName: fieldName, position: position,
        value: value, writtenAt: writtenAt
      ))
      step = sqlite3_step(stmt)
    }
    if step != SQLITE_DONE {
      throw SQLiteError.step(message: "Failed to step row-per-element select: \(sqliteErrorMessage())", resultCode: step)
    }
    return rawRows
  }

  /// Groups raw rows by cache_key, then by field_name, distinguishing
  /// scalar fields (single row at `position = -1`), empty lists
  /// (single marker row at `position = -2`), and list fields (rows at
  /// `position >= 0`, sorted), and recursively resolves any synthetic
  /// child_key_value references into their nested-list contents.
  private func assembleRecords(from rows: [DecodedRow]) throws -> [Record] {
    var byKey: [CacheKey: [DecodedRow]] = [:]
    for row in rows {
      byKey[row.cacheKey, default: []].append(row)
    }

    var records: [Record] = []
    for (key, keyRows) in byKey {
      // Returns ALL records, including synthetic sub-records. The
      // synthetic-key filter happens at the `selectRecords` boundary
      // for top-level reads; internal callers like
      // `resolveSyntheticIfNeeded` need synthetic sub-records here.
      var fields: Record.Fields = [:]
      let byField = Dictionary(grouping: keyRows, by: \.fieldName)
      for (fieldName, fieldRows) in byField {
        let sorted = fieldRows.sorted { $0.position < $1.position }

        if sorted.count == 1 && sorted[0].position == SQLiteSchema.Records.emptyListPositionValue {
          // Empty-list marker row — the value was decoded as `[]`.
          let row = sorted[0]
          fields[fieldName] = CachedField(value: row.value, writtenAt: row.writtenAt)
        } else if sorted.count == 1 && sorted[0].position == SQLiteSchema.Records.defaultPositionValue {
          let row = sorted[0]
          let resolved = try resolveSyntheticIfNeeded(row.value)
          fields[fieldName] = CachedField(value: resolved, writtenAt: row.writtenAt)
        } else {
          var elements: [Record.Value] = []
          var maxWrittenAt: Int64 = 0
          for row in sorted where row.position >= 0 {
            let resolved = try resolveSyntheticIfNeeded(row.value)
            elements.append(resolved)
            maxWrittenAt = max(maxWrittenAt, row.writtenAt)
          }
          fields[fieldName] = CachedField(value: elements as Record.Value, writtenAt: maxWrittenAt)
        }
      }
      records.append(Record(key: key, fields: fields))
    }
    return records
  }

  /// If `value` is a `CacheReference` whose key matches the synthetic-
  /// key suffix pattern, load the synthetic sub-record and return its
  /// inner list. Otherwise return the value unchanged.
  private func resolveSyntheticIfNeeded(_ value: Record.Value) throws -> Record.Value {
    guard let ref = value as? CacheReference, Self.isSyntheticKey(ref.key) else {
      return value
    }
    // Load the synthetic sub-record. Its rows are clustered under
    // field_name = "$" and live at the synthetic cache_key.
    let subRecords = try loadRecordBatch([ref.key])
    guard let subRecord = subRecords.first,
          let listField = subRecord.fields[SQLiteSchema.Records.syntheticFieldName] else {
      // Defensive: the synthetic key was referenced but the sub-
      // record's rows are missing. Return the reference unchanged
      // so the issue surfaces in the caller's assertion rather than
      // here as a silent empty list.
      return value
    }
    return listField.value
  }

  // MARK: - Row-per-element helpers

  private static func isSyntheticKey(_ key: CacheKey) -> Bool {
    key.range(of: SQLiteSchema.Records.syntheticKeySuffixPattern, options: .regularExpression) != nil
  }

  private static func optionalInt64(stmt: OpaquePointer?, column: Int32) -> Int64? {
    if sqlite3_column_type(stmt, column) == SQLITE_NULL { return nil }
    return sqlite3_column_int64(stmt, column)
  }

  private static func optionalDouble(stmt: OpaquePointer?, column: Int32) -> Double? {
    if sqlite3_column_type(stmt, column) == SQLITE_NULL { return nil }
    return sqlite3_column_double(stmt, column)
  }

  private static func optionalText(stmt: OpaquePointer?, column: Int32) -> String? {
    if sqlite3_column_type(stmt, column) == SQLITE_NULL { return nil }
    guard let ptr = sqlite3_column_text(stmt, column) else { return nil }
    return String(cString: ptr)
  }

  private struct DecodedRow {
    let cacheKey: CacheKey
    let fieldName: CacheKey
    let position: Int64
    let value: Record.Value
    let writtenAt: Int64
  }

}

// MARK: - Extensions

extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}

extension Set {
  func chunked(into size: Int) -> [[Element]] {
    Array(self).chunked(into: size)
  }
}

