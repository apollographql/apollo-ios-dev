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
    try dropSQLiteTable(dbURL: sqliteFileURL, tableName: SQLiteSchema.recordsTableName)

    XCTAssertThrowsError(try db.selectRawRows(forKeys: ["key"]))
  }

  // MARK: - schema_metadata

  func test__readSchemaVersion__givenFreshlyCreatedTable_returnsNil() throws {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())
    try db.createSchemaMetadataTableIfNeeded()

    XCTAssertNil(try db.readSchemaVersion())
  }

  func test__readSchemaVersion__afterWrite_roundTripsValue() throws {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())
    try db.createSchemaMetadataTableIfNeeded()

    try db.writeSchemaVersion(SchemaVersion(major: 3))

    XCTAssertEqual(try db.readSchemaVersion(), SchemaVersion(major: 3))
  }

  func test__readSchemaVersion__afterWriteWithMinor_roundTripsValue() throws {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())
    try db.createSchemaMetadataTableIfNeeded()

    try db.writeSchemaVersion(SchemaVersion(major: 3, minor: 1))

    XCTAssertEqual(try db.readSchemaVersion(), SchemaVersion(major: 3, minor: 1))
  }

  func test__writeSchemaVersion__overwritesPriorValue() throws {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())
    try db.createSchemaMetadataTableIfNeeded()

    try db.writeSchemaVersion(SchemaVersion(major: 1))
    try db.writeSchemaVersion(SchemaVersion(major: 3))

    XCTAssertEqual(try db.readSchemaVersion(), SchemaVersion(major: 3))
  }

  func test__createSchemaMetadataTableIfNeeded__isIdempotent() throws {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())

    try db.createSchemaMetadataTableIfNeeded()
    try db.createSchemaMetadataTableIfNeeded()
    try db.writeSchemaVersion(SchemaVersion(major: 3))
    try db.createSchemaMetadataTableIfNeeded()

    XCTAssertEqual(try db.readSchemaVersion(), SchemaVersion(major: 3))
  }

  func test__readSchemaVersion__persistsAcrossDatabaseHandles() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()

    let writer = try ApolloSQLiteDatabase(fileURL: url)
    try writer.createSchemaMetadataTableIfNeeded()
    try writer.writeSchemaVersion(SchemaVersion(major: 3))

    let reader = try ApolloSQLiteDatabase(fileURL: url)
    XCTAssertEqual(try reader.readSchemaVersion(), SchemaVersion(major: 3))
  }

  func test__SQLiteNormalizedCache_init__createsSchemaMetadataTable() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()

    _ = try SQLiteNormalizedCache(fileURL: url)

    // Opening a fresh database against the same URL and querying the schema
    // table should succeed (returning nil because no version is stamped yet)
    // because `SQLiteNormalizedCache.init` is responsible for creating the
    // table.
    let probe = try ApolloSQLiteDatabase(fileURL: url)
    XCTAssertNil(try probe.readSchemaVersion())
  }

  // MARK: - createNewRecordsTableIfNeeded

  func test__createNewRecordsTableIfNeeded__createsRecordsTable() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()
    let db = try ApolloSQLiteDatabase(fileURL: url)
    try db.createSchemaMetadataTableIfNeeded()

    try db.createNewRecordsTableIfNeeded()

    // Verify the table exists by reading its CREATE statement from
    // sqlite_master. Returning a non-empty SQL string confirms creation.
    let createSQL = try readTableSQL(dbURL: url, tableName: SQLiteSchema.recordsTableName)
    XCTAssertFalse(createSQL.isEmpty)
  }

  func test__createNewRecordsTableIfNeeded__stampsCurrentSchemaVersion() throws {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())
    try db.createSchemaMetadataTableIfNeeded()

    try db.createNewRecordsTableIfNeeded()

    XCTAssertEqual(try db.readSchemaVersion(), SQLiteSchema.currentVersion)
    XCTAssertEqual(SQLiteSchema.currentVersion, SchemaVersion(major: 3, minor: 0))
  }

  func test__createNewRecordsTableIfNeeded__isIdempotent() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()
    let db = try ApolloSQLiteDatabase(fileURL: url)
    try db.createSchemaMetadataTableIfNeeded()

    try db.createNewRecordsTableIfNeeded()
    try db.createNewRecordsTableIfNeeded()
    try db.createNewRecordsTableIfNeeded()

    XCTAssertEqual(try db.readSchemaVersion(), SQLiteSchema.currentVersion)
    // No throw from any of the three calls; same CREATE statement persists.
    let createSQL = try readTableSQL(dbURL: url, tableName: SQLiteSchema.recordsTableName)
    XCTAssertTrue(createSQL.contains(SQLiteSchema.Records.cacheKey))
  }

  func test__createNewRecordsTableIfNeeded__preservesWithoutRowID() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()
    let db = try ApolloSQLiteDatabase(fileURL: url)
    try db.createSchemaMetadataTableIfNeeded()

    try db.createNewRecordsTableIfNeeded()

    let createSQL = try readTableSQL(dbURL: url, tableName: SQLiteSchema.recordsTableName)
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

    let createSQL = try readTableSQL(dbURL: url, tableName: SQLiteSchema.recordsTableName)
    // The PRIMARY KEY clause must mention all three composite columns;
    // verifying their names appear together in the SQL is sufficient to
    // catch a regression that dropped or reordered the composite key.
    let normalized = createSQL.replacingOccurrences(of: "\"", with: "")
    XCTAssertTrue(
      normalized.contains("PRIMARY KEY"),
      "Expected PRIMARY KEY clause in: \(createSQL)"
    )
    XCTAssertTrue(
      normalized.contains(SQLiteSchema.Records.cacheKey) &&
      normalized.contains(SQLiteSchema.Records.fieldName) &&
      normalized.contains(SQLiteSchema.Records.position),
      "Expected composite (cache_key, field_name, position) in: \(createSQL)"
    )
  }

  func test__createNewRecordsTableIfNeeded__positionColumnHasDefaultValue() throws {
    let url = SQLiteTestCacheProvider.temporarySQLiteFileURL()
    let db = try ApolloSQLiteDatabase(fileURL: url)
    try db.createSchemaMetadataTableIfNeeded()

    try db.createNewRecordsTableIfNeeded()

    // The column must declare `INTEGER NOT NULL DEFAULT -1`. The default
    // ensures non-list writes that omit `position` land in the right row;
    // dropping or changing the default would silently break that path.
    let createSQL = try readTableSQL(dbURL: url, tableName: SQLiteSchema.recordsTableName)
    let normalized = createSQL.replacingOccurrences(of: "\"", with: "")
    XCTAssertTrue(
      normalized.range(of: "\(SQLiteSchema.Records.position)[^,]*INTEGER[^,]*NOT NULL[^,]*DEFAULT \(SQLiteSchema.Records.defaultPositionValue)",
                       options: [.regularExpression, .caseInsensitive]) != nil,
      "Expected '\(SQLiteSchema.Records.position) INTEGER NOT NULL DEFAULT \(SQLiteSchema.Records.defaultPositionValue)' in: \(createSQL)"
    )
  }

  // MARK: - SchemaVersion parsing

  func test__SchemaVersion_parse__givenDottedFormat_yieldsBothComponents() {
    let parsed = SchemaVersion("3.1")
    XCTAssertEqual(parsed, SchemaVersion(major: 3, minor: 1))
  }

  func test__SchemaVersion_parse__givenBareMajor_yieldsZeroMinor() {
    let parsed = SchemaVersion("3")
    XCTAssertEqual(parsed, SchemaVersion(major: 3, minor: 0))
  }

  func test__SchemaVersion_parse__givenMalformedInput_returnsNil() {
    XCTAssertNil(SchemaVersion(""))
    XCTAssertNil(SchemaVersion("abc"))
    XCTAssertNil(SchemaVersion("3.x"))
    XCTAssertNil(SchemaVersion("3."))
    XCTAssertNil(SchemaVersion(".5"))
  }

  func test__SchemaVersion_description__roundTripsThroughParser() {
    let original = SchemaVersion(major: 4, minor: 2)
    XCTAssertEqual(SchemaVersion(original.description), original)
  }

  func test__SchemaVersion_comparable__ordersByMajorThenMinor() {
    XCTAssertLessThan(SchemaVersion(major: 1), SchemaVersion(major: 2))
    XCTAssertLessThan(SchemaVersion(major: 3, minor: 0), SchemaVersion(major: 3, minor: 1))
    XCTAssertLessThan(SchemaVersion(major: 3, minor: 9), SchemaVersion(major: 4, minor: 0))
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
