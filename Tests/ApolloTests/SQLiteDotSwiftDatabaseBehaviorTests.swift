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
