import Foundation
import SQLite3
import ApolloSQLite

/// Storage-level assertions against a SQLite cache database file, made
/// through the inspector's own read-only connection so no test-only
/// query surface needs to live on the production database class.
///
/// Used by cascade-correctness tests to verify whether synthetic
/// sub-record rows exist after deletes and rewrites — the production
/// read paths deliberately filter synthetic keys out, so asserting
/// through them would pass regardless of cascade behavior.
public enum SQLiteTestDatabaseInspector {

  public enum InspectionError: Error {
    case openFailed(path: String)
    case prepareFailed(message: String)
    case stepFailed(message: String)
  }

  private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  /// Returns the number of rows whose `cache_key` exactly matches
  /// `cacheKey`, bypassing all production read paths and their
  /// synthetic-key filtering.
  public static func rowCount(inDatabaseAt url: URL, forCacheKey cacheKey: String) throws -> Int {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(db)
      throw InspectionError.openFailed(path: url.path)
    }
    defer { sqlite3_close(db) }

    let sql = """
    SELECT COUNT(*) FROM \(SQLiteSchema.recordsTableName)
    WHERE \(SQLiteSchema.Records.cacheKey) = ?
    """
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      throw InspectionError.prepareFailed(message: String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, cacheKey, -1, SQLITE_TRANSIENT)
    guard sqlite3_step(stmt) == SQLITE_ROW else {
      throw InspectionError.stepFailed(message: String(cString: sqlite3_errmsg(db)))
    }
    return Int(sqlite3_column_int64(stmt, 0))
  }

  /// Evaluates a SQL `LIKE` expression exactly as SQLite would —
  /// `SELECT ? LIKE ? ESCAPE ?` against an in-memory database — so
  /// tests can compare SQLite's `LIKE` semantics against Swift-side
  /// classifiers without reimplementing `LIKE` in Swift.
  public static func sqliteLIKEMatches(
    pattern: String,
    candidate: String,
    escape: String = "\\"
  ) throws -> Bool {
    var db: OpaquePointer?
    guard sqlite3_open(":memory:", &db) == SQLITE_OK else {
      sqlite3_close(db)
      throw InspectionError.openFailed(path: ":memory:")
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT ? LIKE ? ESCAPE ?", -1, &stmt, nil) == SQLITE_OK else {
      throw InspectionError.prepareFailed(message: String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, candidate, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 2, pattern, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 3, escape, -1, SQLITE_TRANSIENT)
    guard sqlite3_step(stmt) == SQLITE_ROW else {
      throw InspectionError.stepFailed(message: String(cString: sqlite3_errmsg(db)))
    }
    return sqlite3_column_int64(stmt, 0) == 1
  }
}
