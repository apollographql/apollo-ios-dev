import XCTest
@testable @_spi(Execution) import Apollo
@testable @_spi(Execution) import ApolloSQLite
import ApolloInternalTestHelpers

/// Covers the projection-aware `selectFields(_:)` read on
/// `ApolloSQLiteDatabase`. Companion to `SQLiteRowPerElementCRUDTests`
/// — uses `insertOrUpdate(records:)` to seed the database and
/// verifies `selectFields` returns the expected partial records under
/// PR-009f's `loadFields` contract: a cache key appears in the result
/// if and only if the *record* exists, regardless of whether the
/// projected fields are present on it.
final class SQLiteSelectFieldsTests: XCTestCase {

  // MARK: - Helpers

  private func makeDatabase() throws -> ApolloSQLiteDatabase {
    let db = try ApolloSQLiteDatabase(fileURL: SQLiteTestCacheProvider.temporarySQLiteFileURL())
    try db.createSchemaMetadataTableIfNeeded()
    try db.createNewRecordsTableIfNeeded()
    return db
  }

  private func record(
    _ key: CacheKey,
    fields: [CacheKey: any Hashable & Sendable],
    writtenAt: Int64 = 100
  ) -> Record {
    Record(
      key: key,
      fields: fields.mapValues { CachedField(value: $0, writtenAt: writtenAt) }
    )
  }

  private func projection(
    _ cacheKey: CacheKey,
    _ fieldName: String
  ) -> RecordProjection {
    RecordProjection(
      cacheKey: cacheKey,
      fieldNames: [fieldName]
    )
  }

  // MARK: - Empty input

  func test__selectFields__givenEmptyProjections__returnsEmptyDictionary() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["name": "Anthony"])])

    let result = try db.selectFields([])
    XCTAssertTrue(result.isEmpty)
  }

  // MARK: - Single record, single field

  func test__selectFields__givenSingleField__returnsThatField() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: [
      "name": "Anthony",
      "age": 42,
    ])])

    let result = try db.selectFields([projection("User:1", "name")])

    XCTAssertEqual(result.count, 1)
    let record = try XCTUnwrap(result["User:1"])
    XCTAssertEqual(record.fields.count, 1)
    XCTAssertEqual(record.fields["name"]?.value as? String, "Anthony")
    XCTAssertNil(record.fields["age"])
  }

  func test__selectFields__givenMultipleFieldsOnOneRecord__returnsAllRequested() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: [
      "name": "Anthony",
      "age": 42,
      "city": "Brooklyn",
    ])])

    let result = try db.selectFields([
      projection("User:1", "name"),
      projection("User:1", "age"),
    ])

    let record = try XCTUnwrap(result["User:1"])
    XCTAssertEqual(record.fields.count, 2)
    XCTAssertEqual(record.fields["name"]?.value as? String, "Anthony")
    XCTAssertEqual(record.fields["age"]?.value as? Int, 42)
    XCTAssertNil(record.fields["city"])
  }

  // MARK: - Multi-record projection

  func test__selectFields__givenProjectionsAcrossRecords__returnsEachRecordPartial() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [
      record("User:1", fields: ["name": "Anthony", "age": 42]),
      record("User:2", fields: ["name": "Sarah", "age": 36]),
    ])

    let result = try db.selectFields([
      projection("User:1", "name"),
      projection("User:2", "age"),
    ])

    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result["User:1"]?.fields["name"]?.value as? String, "Anthony")
    XCTAssertNil(result["User:1"]?.fields["age"])
    XCTAssertEqual(result["User:2"]?.fields["age"]?.value as? Int, 36)
    XCTAssertNil(result["User:2"]?.fields["name"])
  }

  // MARK: - Existence contract

  func test__selectFields__givenRecordAbsentFromDB__omitsKeyFromResult() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["name": "Anthony"])])

    let result = try db.selectFields([
      projection("User:1", "name"),
      projection("User:2", "name"),
    ])

    XCTAssertEqual(result.count, 1)
    XCTAssertNotNil(result["User:1"])
    XCTAssertNil(result["User:2"])
  }

  func test__selectFields__givenRecordPresentButFieldMissing__returnsEmptyFieldsForRecord() throws {
    // Per `ReadOnlyNormalizedCache/loadFields(_:)`: a record that
    // exists but holds none of the requested fields surfaces as
    // present-with-empty-fields, not absent. This is what lets the
    // executor distinguish a per-field `missingValue` from a
    // record-level miss.
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["name": "Anthony"])])

    let result = try db.selectFields([projection("User:1", "homePlanet")])

    XCTAssertEqual(result.count, 1)
    let record = try XCTUnwrap(result["User:1"])
    XCTAssertTrue(record.fields.isEmpty)
  }

  // MARK: - Dedupe

  func test__selectFields__givenDuplicateProjections__readsRowOnce() throws {
    // Repeated projections of the same record merge to the union of
    // their field names, coalescing to one SQL bind per
    // (cacheKey, fieldName) pair. The read succeeds and returns the
    // single stored value.
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["name": "Anthony"])])

    let result = try db.selectFields([
      projection("User:1", "name"),
      projection("User:1", "name"),
    ])

    XCTAssertEqual(result["User:1"]?.fields["name"]?.value as? String, "Anthony")
  }

  // MARK: - List field

  func test__selectFields__givenListField__returnsAssembledList() throws {
    let db = try makeDatabase()
    let colors: [Record.Value] = ["red", "green", "blue"]
    try db.insertOrUpdate(records: [Record(
      key: "User:1",
      fields: ["colors": CachedField(value: colors as Record.Value, writtenAt: 100)]
    )])

    let result = try db.selectFields([
      projection("User:1", "colors"),
    ])

    let assembled = result["User:1"]?.fields["colors"]?.value as? [Any]
    XCTAssertEqual(assembled?.count, 3)
    XCTAssertEqual(assembled?[0] as? String, "red")
    XCTAssertEqual(assembled?[2] as? String, "blue")
  }

  // MARK: - Nested list synthetic resolution

  func test__selectFields__givenNestedListField__resolvesSyntheticSubRecord() throws {
    // A nested list (`[[Int]]`) is stored as a parent row with a
    // `child_key_value` pointing at a synthetic sub-record. The SELECT
    // returns only the parent row; `selectFields` must follow the
    // child reference to materialize the inner list.
    let db = try makeDatabase()
    let outer: [Record.Value] = [
      [1, 2] as Record.Value,
      [3, 4] as Record.Value,
    ]
    try db.insertOrUpdate(records: [Record(
      key: "Grid:1",
      fields: ["rows": CachedField(value: outer as Record.Value, writtenAt: 100)]
    )])

    let result = try db.selectFields([
      projection("Grid:1", "rows"),
    ])

    let outerLoaded = result["Grid:1"]?.fields["rows"]?.value as? [Any]
    XCTAssertEqual(outerLoaded?.count, 2)
    let row0 = outerLoaded?[0] as? [Any]
    let row1 = outerLoaded?[1] as? [Any]
    XCTAssertEqual(row0?[0] as? Int, 1)
    XCTAssertEqual(row0?[1] as? Int, 2)
    XCTAssertEqual(row1?[0] as? Int, 3)
    XCTAssertEqual(row1?[1] as? Int, 4)
  }

  // MARK: - WrittenAt preserved

  func test__selectFields__givenWriteWithTimestamp__preservesWrittenAt() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record(
      "User:1",
      fields: ["name": "Anthony"],
      writtenAt: 1_700_000_000
    )])

    let result = try db.selectFields([projection("User:1", "name")])

    XCTAssertEqual(result["User:1"]?.fields["name"]?.writtenAt, 1_700_000_000)
  }
}
