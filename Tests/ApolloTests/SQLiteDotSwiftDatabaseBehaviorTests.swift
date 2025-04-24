import XCTest
@testable import ApolloSQLite
import ApolloInternalTestHelpers
import SQLite3

class SQLiteDotSwiftDatabaseBehaviorTests: XCTestCase {

  func testSelection_withForcedError_shouldThrow() throws {
    let sqliteFileURL = SQLiteTestCacheProvider.temporarySQLiteFileURL()
    let db = try! ApolloSQLiteDatabase(fileURL: sqliteFileURL)

    try! db.createRecordsTableIfNeeded()
    try! db.addOrUpdateRecordString("record", for: "key")

    var rows = [DatabaseRow]()
    XCTAssertNoThrow(rows = try db.selectRawRows(forKeys: ["key"]))
    XCTAssertEqual(rows.count, 1)

    // Use SQLite directly to manipulate the database (cannot be done with SQLiteDotSwiftDatabase)
    try dropSQLiteTable(dbURL: sqliteFileURL, tableName: ApolloSQLiteDatabase.tableName)

    XCTAssertThrowsError(try db.selectRawRows(forKeys: ["key"]))
  }
  
  private func dropSQLiteTable(dbURL: URL, tableName: String) throws {
    var db: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI
    if sqlite3_open_v2(dbURL.path, &db, flags, nil) != SQLITE_OK {
      throw SQLiteError.open(path: dbURL.path)
    }
    
    let sql = "DROP TABLE IF EXISTS \(tableName)"
    if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
      throw SQLiteError.execution(message: "Failed to drop table: \(tableName)")
    }
  }
}
