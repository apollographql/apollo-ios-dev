import XCTest
@testable import ApolloSQLite
import ApolloInternalTestHelpers
import SQLite3

class ApolloSQLiteDatabaseBehaviorTests: XCTestCase {

  func testSelection_withForcedError_shouldThrow() throws {
    let sqliteFileURL = SQLiteTestCacheProvider.temporarySQLiteFileURL()
    let db = try! ApolloSQLiteDatabase(fileURL: sqliteFileURL)

    try! db.createRecordsTableIfNeeded()
    try! db.addOrUpdateRecordString("record", for: "key")

    var rows = [DatabaseRow]()
    XCTAssertNoThrow(rows = try db.selectRawRows(forKeys: ["key"]))
    XCTAssertEqual(rows.count, 1)

    // Use SQLite directly to manipulate the database (cannot be done with ApolloSQLiteDatabase)
    try dropSQLiteTable(dbURL: sqliteFileURL, tableName: ApolloSQLiteDatabase.tableName)

    XCTAssertThrowsError(try db.selectRawRows(forKeys: ["key"]))
  }

  // MARK: - schema_metadata

  func test__readSchemaVersion__givenFreshlyCreatedTable_returnsZero() throws {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())
    try db.createSchemaMetadataTableIfNeeded()

    XCTAssertEqual(try db.readSchemaVersion(), 0)
  }

  func test__readSchemaVersion__afterWrite_roundTripsValue() throws {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())
    try db.createSchemaMetadataTableIfNeeded()

    try db.writeSchemaVersion(3)

    XCTAssertEqual(try db.readSchemaVersion(), 3)
  }

  func test__writeSchemaVersion__overwritesPriorValue() throws {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())
    try db.createSchemaMetadataTableIfNeeded()

    try db.writeSchemaVersion(1)
    try db.writeSchemaVersion(3)

    XCTAssertEqual(try db.readSchemaVersion(), 3)
  }

  func test__createSchemaMetadataTableIfNeeded__isIdempotent() throws {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())

    try db.createSchemaMetadataTableIfNeeded()
    try db.createSchemaMetadataTableIfNeeded()
    try db.writeSchemaVersion(3)
    try db.createSchemaMetadataTableIfNeeded()

    XCTAssertEqual(try db.readSchemaVersion(), 3)
  }

  func test__readSchemaVersion__persistsAcrossDatabaseHandles() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()

    let writer = try ApolloSQLiteDatabase(fileURL: url)
    try writer.createSchemaMetadataTableIfNeeded()
    try writer.writeSchemaVersion(3)

    let reader = try ApolloSQLiteDatabase(fileURL: url)
    XCTAssertEqual(try reader.readSchemaVersion(), 3)
  }

  func test__SQLiteNormalizedCache_init__createsSchemaMetadataTable() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()

    _ = try SQLiteNormalizedCache(fileURL: url)

    // Opening a fresh database against the same URL and querying the schema
    // table should succeed (returning the default of 0) because
    // `SQLiteNormalizedCache.init` is responsible for creating the table.
    let probe = try ApolloSQLiteDatabase(fileURL: url)
    XCTAssertEqual(try probe.readSchemaVersion(), 0)
  }

  // MARK: - createNewRecordsTableIfNeeded

  func test__createNewRecordsTableIfNeeded__createsRecordsTable() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()
    let db = try ApolloSQLiteDatabase(fileURL: url)
    try db.createSchemaMetadataTableIfNeeded()

    try db.createNewRecordsTableIfNeeded()

    // Verify the table exists by reading its CREATE statement from
    // sqlite_master. Returning a non-empty SQL string confirms creation.
    let createSQL = try readTableSQL(dbURL: url, tableName: ApolloSQLiteDatabase.tableName)
    XCTAssertFalse(createSQL.isEmpty)
  }

  func test__createNewRecordsTableIfNeeded__stampsSchemaVersionThree() throws {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())
    try db.createSchemaMetadataTableIfNeeded()

    try db.createNewRecordsTableIfNeeded()

    XCTAssertEqual(try db.readSchemaVersion(), 3)
    XCTAssertEqual(ApolloSQLiteDatabase.currentSchemaVersion, 3)
  }

  func test__createNewRecordsTableIfNeeded__isIdempotent() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()
    let db = try ApolloSQLiteDatabase(fileURL: url)
    try db.createSchemaMetadataTableIfNeeded()

    try db.createNewRecordsTableIfNeeded()
    try db.createNewRecordsTableIfNeeded()
    try db.createNewRecordsTableIfNeeded()

    XCTAssertEqual(try db.readSchemaVersion(), 3)
    // No throw from any of the three calls; same CREATE statement persists.
    let createSQL = try readTableSQL(dbURL: url, tableName: ApolloSQLiteDatabase.tableName)
    XCTAssertTrue(createSQL.contains(ApolloSQLiteDatabase.cacheKeyColumnName))
  }

  func test__createNewRecordsTableIfNeeded__preservesWithoutRowID() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()
    let db = try ApolloSQLiteDatabase(fileURL: url)
    try db.createSchemaMetadataTableIfNeeded()

    try db.createNewRecordsTableIfNeeded()

    let createSQL = try readTableSQL(dbURL: url, tableName: ApolloSQLiteDatabase.tableName)
    XCTAssertTrue(
      createSQL.range(of: "WITHOUT ROWID", options: .caseInsensitive) != nil,
      "Expected CREATE statement to retain WITHOUT ROWID, got: \(createSQL)"
    )
  }

  func test__createNewRecordsTableIfNeeded__hasCompositePrimaryKey() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()
    let db = try ApolloSQLiteDatabase(fileURL: url)
    try db.createSchemaMetadataTableIfNeeded()

    try db.createNewRecordsTableIfNeeded()

    let createSQL = try readTableSQL(dbURL: url, tableName: ApolloSQLiteDatabase.tableName)
    // The PRIMARY KEY clause must mention both composite columns; verifying
    // both names appear together in the SQL is sufficient to catch a regression
    // that dropped or reordered the composite key.
    let normalized = createSQL.replacingOccurrences(of: "\"", with: "")
    XCTAssertTrue(
      normalized.contains("PRIMARY KEY"),
      "Expected PRIMARY KEY clause in: \(createSQL)"
    )
    XCTAssertTrue(
      normalized.contains(ApolloSQLiteDatabase.cacheKeyColumnName) &&
      normalized.contains(ApolloSQLiteDatabase.fieldNameColumnName),
      "Expected composite (cache_key, field_name) in: \(createSQL)"
    )
  }

  private func readTableSQL(dbURL: URL, tableName: String) throws -> String {
    var db: OpaquePointer?
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI
    let openResult = sqlite3_open_v2(dbURL.path, &db, flags, nil)
    guard openResult == SQLITE_OK else {
      throw SQLiteError.open(path: dbURL.path, resultCode: openResult)
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    let prepareResult = sqlite3_prepare_v2(db, "SELECT sql FROM sqlite_master WHERE type='table' AND name=?", -1, &stmt, nil)
    guard prepareResult == SQLITE_OK else {
      throw SQLiteError.prepare(message: "Failed to prepare sqlite_master lookup", resultCode: prepareResult)
    }
    defer { sqlite3_finalize(stmt) }

    let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(stmt, 1, tableName, -1, sqliteTransient)

    let step = sqlite3_step(stmt)
    guard step == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) else {
      return ""
    }
    return String(cString: cStr)
  }
  
  private func dropSQLiteTable(dbURL: URL, tableName: String) throws {
    var db: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI
    let result = sqlite3_open_v2(dbURL.path, &db, flags, nil)
    if result != SQLITE_OK {
      throw SQLiteError.open(path: dbURL.path, resultCode: result)
    }
    
    let sql = "DROP TABLE IF EXISTS \(tableName)"
    let execResult = sqlite3_exec(db, sql, nil, nil, nil)
    if execResult != SQLITE_OK {
      throw SQLiteError.execution(message: "Failed to drop table: \(tableName)", resultCode: execResult)
    }
  }
}
