import XCTest
@testable @_spi(Execution) import Apollo
@testable import ApolloSQLite
import ApolloInternalTestHelpers

/// Cascade-correctness tests for the row-per-element schema.
///
/// Synthetic sub-records (`<parent>.<field>.$[N]`) are produced by
/// nested-list writes. When a record is deleted or one of its
/// nested-list fields is overwritten, every reachable synthetic
/// sub-record must be cleaned up so the database doesn't accumulate
/// unreachable orphan rows.
///
/// The tests in this suite verify orphan removal via
/// `SQLiteTestDatabaseInspector.rowCount(inDatabaseAt:forCacheKey:)`,
/// which opens its own connection and bypasses `selectRecords`'s
/// synthetic-key filter. An earlier draft of these tests went through
/// `selectRecords` and silently passed regardless of cascade behavior
/// because the filter masked the orphans — the raw row count makes
/// the assertions actually load-bearing.
class SQLiteRowPerElementCascadeDeleteTests: XCTestCase {

  // MARK: - Fixtures

  /// The file URL of the database created by `makeDatabase()`, used by
  /// `rowCount(forCacheKey:)` to inspect storage through the test
  /// inspector's own connection.
  private var databaseFileURL: URL!

  private func makeDatabase() throws -> ApolloSQLiteDatabase {
    let fileURL = SQLiteTestCacheProvider.temporarySQLiteFileURL()
    databaseFileURL = fileURL
    let db = try ApolloSQLiteDatabase(fileURL: fileURL)
    try db.createSchemaMetadataTableIfNeeded()
    try db.createNewRecordsTableIfNeeded()
    return db
  }

  /// Counts stored rows for `cacheKey` via `SQLiteTestDatabaseInspector`,
  /// bypassing the production read paths and their synthetic-key filter
  /// so orphan assertions stay load-bearing.
  private func rowCount(forCacheKey cacheKey: CacheKey) throws -> Int {
    try SQLiteTestDatabaseInspector.rowCount(inDatabaseAt: databaseFileURL, forCacheKey: cacheKey)
  }

  /// Wraps a value into a `Record` with one field. Lets the test
  /// helpers stay legible when constructing nested-list values.
  private func record(
    _ key: CacheKey,
    field: String,
    value: Record.Value,
    writtenAt: Int64 = 100
  ) -> Record {
    Record(
      key: key,
      fields: [field: CachedField(value: value, writtenAt: writtenAt)]
    )
  }

  // MARK: - deleteRecord(forKey:) cascade

  func test__deleteRecord_forKey__cascadesDepth1NestedListSyntheticSubRecords() throws {
    let db = try makeDatabase()
    // 2D: outer list with two inner-list elements. Each inner list
    // produces one synthetic sub-record at `Math:1.matrix.$[N]`.
    let row0: [Record.Value] = [1, 2]
    let row1: [Record.Value] = [3, 4]
    let matrix: [Record.Value] = [row0 as Record.Value, row1 as Record.Value]
    try db.insertOrUpdate(records: [record("Math:1", field: "matrix", value: matrix as Record.Value)])

    // Pre-check: synthetic sub-records exist.
    XCTAssertEqual(try rowCount(forCacheKey: "Math:1.matrix.$[0]"), 2)
    XCTAssertEqual(try rowCount(forCacheKey: "Math:1.matrix.$[1]"), 2)

    try db.deleteRecord(forKey: "Math:1")

    // Parent gone.
    XCTAssertEqual(try rowCount(forCacheKey: "Math:1"), 0)
    // Synthetic descendants gone.
    XCTAssertEqual(try rowCount(forCacheKey: "Math:1.matrix.$[0]"), 0,
                   "Depth-1 synthetic sub-record must cascade")
    XCTAssertEqual(try rowCount(forCacheKey: "Math:1.matrix.$[1]"), 0,
                   "Depth-1 synthetic sub-record must cascade")
  }

  func test__deleteRecord_forKey__cascadesDeeplyNestedSyntheticSubRecords() throws {
    let db = try makeDatabase()
    // 3D: `[[[5]]]`. Three levels of synthetic sub-records.
    let innermost: [Record.Value] = [5]
    let middle: [Record.Value] = [innermost as Record.Value]
    let outer: [Record.Value] = [middle as Record.Value]
    try db.insertOrUpdate(records: [record("Math:cube", field: "cube", value: outer as Record.Value)])

    // Pre-check: every level exists.
    XCTAssertEqual(try rowCount(forCacheKey: "Math:cube"), 1)
    XCTAssertEqual(try rowCount(forCacheKey: "Math:cube.cube.$[0]"), 1)
    XCTAssertEqual(try rowCount(forCacheKey: "Math:cube.cube.$[0].$[0]"), 1)

    try db.deleteRecord(forKey: "Math:cube")

    XCTAssertEqual(try rowCount(forCacheKey: "Math:cube"), 0)
    XCTAssertEqual(try rowCount(forCacheKey: "Math:cube.cube.$[0]"), 0,
                   "Level-2 synthetic sub-record must cascade")
    XCTAssertEqual(try rowCount(forCacheKey: "Math:cube.cube.$[0].$[0]"), 0,
                   "Level-3 synthetic sub-record must cascade — recursive walk must reach it")
  }

  func test__deleteRecord_forKey__cascadeIsolation_leavesOtherRecordsSyntheticSubRecords() throws {
    let db = try makeDatabase()
    // Two independent records, both with nested-list fields that
    // produce synthetic sub-records. Deleting one must not touch
    // the other.
    let matrixA: [Record.Value] = [[1, 2] as Record.Value]
    let matrixB: [Record.Value] = [[3, 4] as Record.Value]
    try db.insertOrUpdate(records: [
      record("Math:A", field: "matrix", value: matrixA as Record.Value),
      record("Math:B", field: "matrix", value: matrixB as Record.Value),
    ])

    try db.deleteRecord(forKey: "Math:A")

    // A is gone with its descendants.
    XCTAssertEqual(try rowCount(forCacheKey: "Math:A"), 0)
    XCTAssertEqual(try rowCount(forCacheKey: "Math:A.matrix.$[0]"), 0)
    // B is untouched.
    XCTAssertEqual(try rowCount(forCacheKey: "Math:B"), 1)
    XCTAssertEqual(try rowCount(forCacheKey: "Math:B.matrix.$[0]"), 2,
                   "Sibling record's synthetic sub-records must survive")
  }

  func test__deleteRecord_forKey__cascadesAcrossMultipleNestedListFieldsOnTheSameRecord() throws {
    let db = try makeDatabase()
    // One record with TWO list-of-list fields. Each field
    // produces its own synthetic sub-records. Deleting the record
    // must cascade through both.
    let matrix: [Record.Value] = [[1, 2] as Record.Value]
    let coords: [Record.Value] = [[3, 4] as Record.Value]
    let fields: Record.Fields = [
      "matrix": CachedField(value: matrix as Record.Value, writtenAt: 100),
      "coords": CachedField(value: coords as Record.Value, writtenAt: 100),
    ]
    try db.insertOrUpdate(records: [Record(key: "Math:multi", fields: fields)])

    XCTAssertGreaterThan(try rowCount(forCacheKey: "Math:multi.matrix.$[0]"), 0)
    XCTAssertGreaterThan(try rowCount(forCacheKey: "Math:multi.coords.$[0]"), 0)

    try db.deleteRecord(forKey: "Math:multi")

    XCTAssertEqual(try rowCount(forCacheKey: "Math:multi.matrix.$[0]"), 0,
                   "First nested-list field's sub-record must cascade")
    XCTAssertEqual(try rowCount(forCacheKey: "Math:multi.coords.$[0]"), 0,
                   "Second nested-list field's sub-record must cascade")
  }

  func test__deleteRecord_forKey__doesNotFollowRealCacheReferenceTargets() throws {
    let db = try makeDatabase()
    // QUERY_ROOT's `users` field is a list of *real* (non-synthetic)
    // CacheReferences pointing to User:1 and User:2. Deleting
    // QUERY_ROOT must remove QUERY_ROOT's rows but leave the User
    // records and their fields untouched — real references are not
    // part of the synthetic-sub-record cascade.
    let users: [Record.Value] = [
      CacheReference("User:1") as Record.Value,
      CacheReference("User:2") as Record.Value,
    ]
    try db.insertOrUpdate(records: [
      Record(key: "QUERY_ROOT", fields: ["users": CachedField(value: users as Record.Value, writtenAt: 100)]),
      Record(key: "User:1", fields: ["name": CachedField(value: "A" as Record.Value, writtenAt: 100)]),
      Record(key: "User:2", fields: ["name": CachedField(value: "B" as Record.Value, writtenAt: 100)]),
    ])

    try db.deleteRecord(forKey: "QUERY_ROOT")

    XCTAssertEqual(try rowCount(forCacheKey: "QUERY_ROOT"), 0)
    XCTAssertEqual(try rowCount(forCacheKey: "User:1"), 1,
                   "Real CacheReference target must not be cascade-deleted")
    XCTAssertEqual(try rowCount(forCacheKey: "User:2"), 1)
  }

  func test__deleteRecord_forKey__doesNotFollowRealCacheReferenceInsideSyntheticSubRecord() throws {
    let db = try makeDatabase()
    // Org has a list-of-list-of-references: `[[CacheReference]]`.
    // The outer list creates synthetic sub-records; each sub-record
    // holds an inner list of REAL CacheReferences to User:N records.
    // Deleting Org must cascade the synthetic sub-records but must
    // leave User:1 / User:2 alone — real references inside
    // synthetic sub-records still don't trigger cascade.
    let team: [Record.Value] = [
      CacheReference("User:1") as Record.Value,
      CacheReference("User:2") as Record.Value,
    ]
    let teams: [Record.Value] = [team as Record.Value]
    try db.insertOrUpdate(records: [
      Record(key: "Org:1", fields: ["teams": CachedField(value: teams as Record.Value, writtenAt: 100)]),
      Record(key: "User:1", fields: ["name": CachedField(value: "A" as Record.Value, writtenAt: 100)]),
      Record(key: "User:2", fields: ["name": CachedField(value: "B" as Record.Value, writtenAt: 100)]),
    ])

    XCTAssertGreaterThan(try rowCount(forCacheKey: "Org:1.teams.$[0]"), 0)

    try db.deleteRecord(forKey: "Org:1")

    XCTAssertEqual(try rowCount(forCacheKey: "Org:1"), 0)
    XCTAssertEqual(try rowCount(forCacheKey: "Org:1.teams.$[0]"), 0,
                   "Synthetic sub-record under Org:1.teams must cascade")
    XCTAssertEqual(try rowCount(forCacheKey: "User:1"), 1,
                   "Real CacheReference inside a synthetic sub-record must NOT be cascaded")
    XCTAssertEqual(try rowCount(forCacheKey: "User:2"), 1)
  }

  // MARK: - insertOrUpdate atomic-rewrite cascade

  func test__insertOrUpdate__atomicRewriteOfNestedListField_cleansSyntheticSubRecords() throws {
    let db = try makeDatabase()
    let matrix: [Record.Value] = [[1, 2] as Record.Value, [3, 4] as Record.Value]
    try db.insertOrUpdate(records: [record("Math:1", field: "matrix", value: matrix as Record.Value)])
    XCTAssertEqual(try rowCount(forCacheKey: "Math:1.matrix.$[0]"), 2)
    XCTAssertEqual(try rowCount(forCacheKey: "Math:1.matrix.$[1]"), 2)

    // Rewrite as a scalar — the prior synthetic sub-records must be
    // cleaned up, not orphaned.
    try db.insertOrUpdate(records: [record("Math:1", field: "matrix", value: "rewritten" as Record.Value, writtenAt: 200)])

    XCTAssertEqual(try rowCount(forCacheKey: "Math:1.matrix.$[0]"), 0,
                   "Atomic list→scalar rewrite must cascade synthetic sub-records")
    XCTAssertEqual(try rowCount(forCacheKey: "Math:1.matrix.$[1]"), 0)
  }

  func test__insertOrUpdate__atomicRewriteOfDeeplyNestedList_cleansAllSyntheticDescendants() throws {
    let db = try makeDatabase()
    // 3D first, then a single-element scalar.
    let cube: [Record.Value] = [[[5] as Record.Value] as Record.Value]
    try db.insertOrUpdate(records: [record("Math:cube", field: "cube", value: cube as Record.Value)])
    XCTAssertEqual(try rowCount(forCacheKey: "Math:cube.cube.$[0]"), 1)
    XCTAssertEqual(try rowCount(forCacheKey: "Math:cube.cube.$[0].$[0]"), 1)

    try db.insertOrUpdate(records: [record("Math:cube", field: "cube", value: "flat" as Record.Value, writtenAt: 200)])

    XCTAssertEqual(try rowCount(forCacheKey: "Math:cube.cube.$[0]"), 0,
                   "Level-2 synthetic sub-record must cascade on rewrite")
    XCTAssertEqual(try rowCount(forCacheKey: "Math:cube.cube.$[0].$[0]"), 0,
                   "Level-3 synthetic sub-record must cascade — recursive walk must reach it on rewrite too")
  }

  func test__insertOrUpdate__atomicRewriteOfOneField_preservesOtherFieldsSyntheticSubRecords() throws {
    let db = try makeDatabase()
    // Record with two nested-list fields. Rewriting ONE field must
    // not cascade-delete the OTHER field's synthetic sub-records.
    let matrix: [Record.Value] = [[1, 2] as Record.Value]
    let coords: [Record.Value] = [[3, 4] as Record.Value]
    let fields: Record.Fields = [
      "matrix": CachedField(value: matrix as Record.Value, writtenAt: 100),
      "coords": CachedField(value: coords as Record.Value, writtenAt: 100),
    ]
    try db.insertOrUpdate(records: [Record(key: "Math:multi", fields: fields)])
    XCTAssertEqual(try rowCount(forCacheKey: "Math:multi.matrix.$[0]"), 2)
    XCTAssertEqual(try rowCount(forCacheKey: "Math:multi.coords.$[0]"), 2)

    // Rewrite only `matrix`.
    try db.insertOrUpdate(records: [record("Math:multi", field: "matrix", value: "rewritten" as Record.Value, writtenAt: 200)])

    XCTAssertEqual(try rowCount(forCacheKey: "Math:multi.matrix.$[0]"), 0,
                   "Rewritten field's synthetic sub-record must cascade")
    XCTAssertEqual(try rowCount(forCacheKey: "Math:multi.coords.$[0]"), 2,
                   "Untouched field's synthetic sub-record must survive")
  }

  // MARK: - deleteRecords(matchingKey:) cascade

  func test__deleteRecords_matchingKey__cascadesSyntheticDescendantsOfMatchedRecords() throws {
    let db = try makeDatabase()
    // Two `Animal:` records with nested-list fields.
    let matrixA: [Record.Value] = [[1, 2] as Record.Value]
    let matrixB: [Record.Value] = [[3, 4] as Record.Value]
    try db.insertOrUpdate(records: [
      record("Animal:cat", field: "claws", value: matrixA as Record.Value),
      record("Animal:dog", field: "claws", value: matrixB as Record.Value),
    ])
    XCTAssertEqual(try rowCount(forCacheKey: "Animal:cat.claws.$[0]"), 2)
    XCTAssertEqual(try rowCount(forCacheKey: "Animal:dog.claws.$[0]"), 2)

    try db.deleteRecords(matchingKey: "Animal:")

    XCTAssertEqual(try rowCount(forCacheKey: "Animal:cat"), 0)
    XCTAssertEqual(try rowCount(forCacheKey: "Animal:dog"), 0)
    XCTAssertEqual(try rowCount(forCacheKey: "Animal:cat.claws.$[0]"), 0,
                   "Pattern-deleted record's synthetic sub-record must cascade")
    XCTAssertEqual(try rowCount(forCacheKey: "Animal:dog.claws.$[0]"), 0,
                   "Pattern-deleted record's synthetic sub-record must cascade")
  }

  func test__deleteRecords_matchingKey__doesNotCascadeUnmatchedRecordsSyntheticSubRecords() throws {
    let db = try makeDatabase()
    let matrixCat: [Record.Value] = [[1, 2] as Record.Value]
    let matrixUser: [Record.Value] = [[5, 6] as Record.Value]
    try db.insertOrUpdate(records: [
      record("Animal:cat", field: "matrix", value: matrixCat as Record.Value),
      record("User:1", field: "matrix", value: matrixUser as Record.Value),
    ])

    try db.deleteRecords(matchingKey: "Animal:")

    XCTAssertEqual(try rowCount(forCacheKey: "Animal:cat.matrix.$[0]"), 0,
                   "Matched record's synthetic sub-record must cascade")
    XCTAssertEqual(try rowCount(forCacheKey: "User:1"), 1)
    XCTAssertEqual(try rowCount(forCacheKey: "User:1.matrix.$[0]"), 2,
                   "Unmatched record's synthetic sub-record must survive")
  }

  func test__deleteRecords_matchingKey__patternMatchingSyntheticKeyButNotParent_leavesParentsListStorageIntact() throws {
    let db = try makeDatabase()
    // Synthetic keys embed the parent field name
    // (`User:1.claws.$[0]`), so the pattern "claws" matches the
    // synthetic key while the parent key `User:1` doesn't. The
    // pattern delete must not touch the synthetic rows in that case —
    // deleting them would amputate the internals of a list the caller
    // never asked to remove and leave `User:1`'s rows dangling.
    let claws: [Record.Value] = [[1, 2] as Record.Value, [3] as Record.Value]
    try db.insertOrUpdate(records: [record("User:1", field: "claws", value: claws as Record.Value)])
    XCTAssertEqual(try rowCount(forCacheKey: "User:1.claws.$[0]"), 2)
    XCTAssertEqual(try rowCount(forCacheKey: "User:1.claws.$[1]"), 1)

    try db.deleteRecords(matchingKey: "claws")

    XCTAssertEqual(try rowCount(forCacheKey: "User:1"), 2,
                   "Parent record's rows must survive a pattern that only matches its synthetic children")
    XCTAssertEqual(try rowCount(forCacheKey: "User:1.claws.$[0]"), 2,
                   "Synthetic rows must survive a pattern matching them but not their parent")
    XCTAssertEqual(try rowCount(forCacheKey: "User:1.claws.$[1]"), 1)

    // The nested list still reads back fully intact.
    let loaded = try db.selectRecords(forKeys: ["User:1"])
    let outer = loaded[0].fields["claws"]?.value as? [Any]
    XCTAssertEqual(outer?.count, 2)
    XCTAssertEqual((outer?[0] as? [Any])?.count, 2)
    XCTAssertEqual((outer?[1] as? [Any])?.count, 1)
  }

  func test__deleteRecords_matchingKey__patternMatchingParentAndSyntheticKeys_deletesBothViaCascade() throws {
    let db = try makeDatabase()
    // When the pattern matches the parent, the synthetic rows go with
    // it (via the cascade), even though the flat delete no longer
    // matches synthetic keys directly.
    let claws: [Record.Value] = [[1, 2] as Record.Value]
    try db.insertOrUpdate(records: [record("Animal:cat", field: "claws", value: claws as Record.Value)])

    try db.deleteRecords(matchingKey: "cat")

    XCTAssertEqual(try rowCount(forCacheKey: "Animal:cat"), 0)
    XCTAssertEqual(try rowCount(forCacheKey: "Animal:cat.claws.$[0]"), 0,
                   "Synthetic sub-records of a matched parent must still cascade")
  }
}
