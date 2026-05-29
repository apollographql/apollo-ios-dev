import Foundation
import Apollo
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

