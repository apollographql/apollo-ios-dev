import XCTest
import Nimble
@testable @_spi(Execution) import Apollo
@testable import ApolloSQLite
import ApolloInternalTestHelpers

class SQLiteRowPerElementCRUDTests: XCTestCase {

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

  // MARK: - Per-scalar round-trip

  func test__roundTrip__stringValue() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["name": "Anthony"])])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(loaded[0].fields["name"]?.value as? String, "Anthony")
    XCTAssertEqual(loaded[0].fields["name"]?.writtenAt, 100)
  }

  func test__roundTrip__intValue() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["age": 42])])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertEqual(loaded[0].fields["age"]?.value as? Int, 42)
  }

  func test__roundTrip__doubleValue() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("Stock:AAPL", fields: ["price": 199.25])])

    let loaded = try db.selectRecords(forKeys: ["Stock:AAPL"])
    XCTAssertEqual(loaded[0].fields["price"]?.value as? Double, 199.25)
  }

  func test__roundTrip__boolValue_true() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["isActive": true])])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertEqual(loaded[0].fields["isActive"]?.value as? Bool, true)
  }

  func test__roundTrip__boolValue_false() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["isActive": false])])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertEqual(loaded[0].fields["isActive"]?.value as? Bool, false)
  }

  func test__roundTrip__cacheReference() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record(
      "QUERY_ROOT",
      fields: ["user": CacheReference("User:1")]
    )])

    let loaded = try db.selectRecords(forKeys: ["QUERY_ROOT"])
    XCTAssertEqual(loaded[0].fields["user"]?.value as? CacheReference, CacheReference("User:1"))
  }

  // MARK: - Lists (1D)

  func test__roundTrip__listOfStrings() throws {
    let db = try makeDatabase()
    let list: [Record.Value] = ["red", "green", "blue"]
    let original = Record(
      key: "User:1",
      fields: ["colors": CachedField(value: list as Record.Value, writtenAt: 100)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    let reloaded = loaded[0].fields["colors"]?.value as? [Any]
    XCTAssertEqual(reloaded?.count, 3)
    XCTAssertEqual(reloaded?[0] as? String, "red")
    XCTAssertEqual(reloaded?[1] as? String, "green")
    XCTAssertEqual(reloaded?[2] as? String, "blue")
  }

  func test__roundTrip__listOfCacheReferences() throws {
    let db = try makeDatabase()
    let list: [Record.Value] = [
      CacheReference("User:1"),
      CacheReference("User:2"),
    ]
    let original = Record(
      key: "QUERY_ROOT",
      fields: ["users": CachedField(value: list as Record.Value, writtenAt: 100)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["QUERY_ROOT"])
    let reloaded = loaded[0].fields["users"]?.value as? [Any]
    XCTAssertEqual(reloaded?.count, 2)
    XCTAssertEqual(reloaded?[0] as? CacheReference, CacheReference("User:1"))
    XCTAssertEqual(reloaded?[1] as? CacheReference, CacheReference("User:2"))
  }

  func test__roundTrip__listOfMixedScalars() throws {
    let db = try makeDatabase()
    let list: [Record.Value] = [1, "two", 3.0, true]
    let original = Record(
      key: "Mixed:1",
      fields: ["values": CachedField(value: list as Record.Value, writtenAt: 100)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["Mixed:1"])
    let reloaded = loaded[0].fields["values"]?.value as? [Any]
    XCTAssertEqual(reloaded?[0] as? Int, 1)
    XCTAssertEqual(reloaded?[1] as? String, "two")
    XCTAssertEqual(reloaded?[2] as? Double, 3.0)
    XCTAssertEqual(reloaded?[3] as? Bool, true)
  }

  func test__roundTrip__emptyList() throws {
    let db = try makeDatabase()
    let list: [Record.Value] = []
    let original = Record(
      key: "User:1",
      fields: ["colors": CachedField(value: list as Record.Value, writtenAt: 100)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    // An empty list writes a single marker row (`position = -2`) so
    // it stays distinguishable from a never-written field:
    // `colors: []` is cached, valid data — not a cache miss.
    expect(loaded).to(haveCount(1))
    let reloaded = loaded[0].fields["colors"]?.value as? [Any]
    expect(reloaded).toNot(beNil())
    expect(reloaded).to(beEmpty())
    expect(loaded[0].fields["colors"]?.writtenAt).to(equal(100))
  }

  func test__insertOrUpdate__overwritingNonEmptyListWithEmptyList__readsBackEmptyList() throws {
    let db = try makeDatabase()
    let full: [Record.Value] = ["red", "green"]
    try db.insertOrUpdate(records: [Record(
      key: "User:1",
      fields: ["colors": CachedField(value: full as Record.Value, writtenAt: 100)]
    )])

    let empty: [Record.Value] = []
    try db.insertOrUpdate(records: [Record(
      key: "User:1",
      fields: ["colors": CachedField(value: empty as Record.Value, writtenAt: 200)]
    )])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    expect(loaded).to(haveCount(1))
    let reloaded = loaded[0].fields["colors"]?.value as? [Any]
    expect(reloaded).toNot(beNil())
    expect(reloaded).to(beEmpty())
    expect(loaded[0].fields["colors"]?.writtenAt).to(equal(200))
  }

  func test__insertOrUpdate__overwritingEmptyListWithNonEmptyList__readsBackElements() throws {
    let db = try makeDatabase()
    let empty: [Record.Value] = []
    try db.insertOrUpdate(records: [Record(
      key: "User:1",
      fields: ["colors": CachedField(value: empty as Record.Value, writtenAt: 100)]
    )])

    let full: [Record.Value] = ["red", "green"]
    try db.insertOrUpdate(records: [Record(
      key: "User:1",
      fields: ["colors": CachedField(value: full as Record.Value, writtenAt: 200)]
    )])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    let reloaded = loaded[0].fields["colors"]?.value as? [Any]
    expect(reloaded).to(haveCount(2))
    expect(reloaded?[0] as? String).to(equal("red"))
    expect(reloaded?[1] as? String).to(equal("green"))
  }

  // MARK: - Nested lists (2D, 3D)

  func test__roundTrip__nestedList_2D() throws {
    let db = try makeDatabase()
    let row0: [Record.Value] = [1, 2]
    let row1: [Record.Value] = [3, 4]
    let matrix: [Record.Value] = [row0 as Record.Value, row1 as Record.Value]
    let original = Record(
      key: "Math:1",
      fields: ["matrix": CachedField(value: matrix as Record.Value, writtenAt: 100)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["Math:1"])
    let reloadedOuter = loaded[0].fields["matrix"]?.value as? [Any]
    XCTAssertEqual(reloadedOuter?.count, 2)
    let inner0 = reloadedOuter?[0] as? [Any]
    let inner1 = reloadedOuter?[1] as? [Any]
    XCTAssertEqual(inner0?.count, 2)
    XCTAssertEqual(inner0?[0] as? Int, 1)
    XCTAssertEqual(inner0?[1] as? Int, 2)
    XCTAssertEqual(inner1?[0] as? Int, 3)
    XCTAssertEqual(inner1?[1] as? Int, 4)
  }

  func test__roundTrip__nestedList_3D() throws {
    let db = try makeDatabase()
    // Cube `[[[5]]]` — exercises two levels of synthetic sub-record
    // indirection (level 1 uses `<parent>.<field>.$[N]`; level 2+
    // uses `<parent>.$[N]`).
    let innermost: [Record.Value] = [5]
    let middle: [Record.Value] = [innermost as Record.Value]
    let outer: [Record.Value] = [middle as Record.Value]
    let original = Record(
      key: "Math:cube",
      fields: ["cube": CachedField(value: outer as Record.Value, writtenAt: 100)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["Math:cube"])
    let level0 = loaded[0].fields["cube"]?.value as? [Any]
    let level1 = level0?[0] as? [Any]
    let level2 = level1?[0] as? [Any]
    XCTAssertEqual(level2?[0] as? Int, 5,
                   "3D nesting should round-trip through two synthetic sub-records")
  }

  func test__roundTrip__nestedList_containingEmptyInnerList() throws {
    let db = try makeDatabase()
    // `[[1, 2], []]` — the empty inner list must survive the
    // synthetic sub-record round-trip as `[]`, not leak a dangling
    // `CacheReference` to the (row-less) synthetic key.
    let row0: [Record.Value] = [1, 2]
    let row1: [Record.Value] = []
    let matrix: [Record.Value] = [row0 as Record.Value, row1 as Record.Value]
    let original = Record(
      key: "Math:1",
      fields: ["matrix": CachedField(value: matrix as Record.Value, writtenAt: 100)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["Math:1"])
    let reloadedOuter = loaded[0].fields["matrix"]?.value as? [Any]
    expect(reloadedOuter).to(haveCount(2))
    let inner0 = reloadedOuter?[0] as? [Any]
    expect(inner0?.count).to(equal(2))
    expect(inner0?[0] as? Int).to(equal(1))
    expect(reloadedOuter?[1] as? CacheReference).to(beNil())
    let inner1 = reloadedOuter?[1] as? [Any]
    expect(inner1).toNot(beNil())
    expect(inner1).to(beEmpty())
  }

  func test__roundTrip__nestedList_singleEmptyInnerList() throws {
    let db = try makeDatabase()
    // `[[]]` — a one-element outer list whose only element is empty.
    let inner: [Record.Value] = []
    let outer: [Record.Value] = [inner as Record.Value]
    let original = Record(
      key: "Math:1",
      fields: ["matrix": CachedField(value: outer as Record.Value, writtenAt: 100)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["Math:1"])
    let reloadedOuter = loaded[0].fields["matrix"]?.value as? [Any]
    expect(reloadedOuter).to(haveCount(1))
    let inner0 = reloadedOuter?[0] as? [Any]
    expect(inner0).toNot(beNil())
    expect(inner0).to(beEmpty())
  }

  func test__roundTrip__nestedList_listOfReferences() throws {
    let db = try makeDatabase()
    // `[[User:1, User:2], [User:3]]` — list-of-list-of-references.
    let group1: [Record.Value] = [CacheReference("User:1"), CacheReference("User:2")]
    let group2: [Record.Value] = [CacheReference("User:3")]
    let groups: [Record.Value] = [group1 as Record.Value, group2 as Record.Value]
    let original = Record(
      key: "Org:1",
      fields: ["teams": CachedField(value: groups as Record.Value, writtenAt: 100)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["Org:1"])
    let outer = loaded[0].fields["teams"]?.value as? [Any]
    XCTAssertEqual(outer?.count, 2)
    let team1 = outer?[0] as? [Any]
    let team2 = outer?[1] as? [Any]
    XCTAssertEqual(team1?[0] as? CacheReference, CacheReference("User:1"))
    XCTAssertEqual(team1?[1] as? CacheReference, CacheReference("User:2"))
    XCTAssertEqual(team2?[0] as? CacheReference, CacheReference("User:3"))
  }

  // MARK: - Record-level round-trip

  func test__roundTrip__multiFieldRecord_preservesAllFields() throws {
    let db = try makeDatabase()
    let list: [Record.Value] = ["a", "b"]
    let original = Record(
      key: "User:1",
      fields: [
        "id": CachedField(value: "1" as Record.Value, writtenAt: 555),
        "name": CachedField(value: "Anthony" as Record.Value, writtenAt: 555),
        "age": CachedField(value: 42 as Record.Value, writtenAt: 555),
        "isActive": CachedField(value: true as Record.Value, writtenAt: 555),
        "owner": CachedField(value: CacheReference("Org:42") as Record.Value, writtenAt: 555),
        "tags": CachedField(value: list as Record.Value, writtenAt: 555),
      ]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(loaded[0].fields.count, 6)
    XCTAssertEqual(loaded[0].fields["id"]?.value as? String, "1")
    XCTAssertEqual(loaded[0].fields["name"]?.value as? String, "Anthony")
    XCTAssertEqual(loaded[0].fields["age"]?.value as? Int, 42)
    XCTAssertEqual(loaded[0].fields["isActive"]?.value as? Bool, true)
    XCTAssertEqual(loaded[0].fields["owner"]?.value as? CacheReference, CacheReference("Org:42"))
    XCTAssertEqual((loaded[0].fields["tags"]?.value as? [Any])?.count, 2)
  }

  // MARK: - UPSERT semantics

  func test__insertOrUpdate__writingTwice_overwritesScalar() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["age": 42], writtenAt: 100)])
    try db.insertOrUpdate(records: [record("User:1", fields: ["age": 99], writtenAt: 200)])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertEqual(loaded[0].fields["age"]?.value as? Int, 99)
    XCTAssertEqual(loaded[0].fields["age"]?.writtenAt, 200)
  }

  func test__insertOrUpdate__changingScalarValueType_clearsPriorColumn() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["data": 42])])
    // Decoder reads int_value before string_value, so a stale
    // int_value would shadow the new string and the assertion below
    // would surface Int(42) instead of "forty-two".
    try db.insertOrUpdate(records: [record("User:1", fields: ["data": "forty-two"])])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertEqual(loaded[0].fields["data"]?.value as? String, "forty-two")
  }

  func test__insertOrUpdate__atomicListRewrite_shrinksLength() throws {
    let db = try makeDatabase()
    // Write a 4-element list, then a 2-element list. Without atomic
    // rewrite, the trailing elements from the longer list would
    // remain as orphaned rows and the reader would see a 4-element
    // list with the first two overwritten.
    let listLong: [Record.Value] = ["a", "b", "c", "d"]
    let listShort: [Record.Value] = ["x", "y"]
    try db.insertOrUpdate(records: [Record(
      key: "User:1",
      fields: ["colors": CachedField(value: listLong as Record.Value, writtenAt: 100)]
    )])
    try db.insertOrUpdate(records: [Record(
      key: "User:1",
      fields: ["colors": CachedField(value: listShort as Record.Value, writtenAt: 200)]
    )])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    let reloaded = loaded[0].fields["colors"]?.value as? [Any]
    XCTAssertEqual(reloaded?.count, 2, "Shorter list rewrite should leave exactly 2 elements")
    XCTAssertEqual(reloaded?[0] as? String, "x")
    XCTAssertEqual(reloaded?[1] as? String, "y")
  }

  // MARK: - Delete operations

  func test__deleteRecord_forKey__removesOnlyMatchingRows() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [
      record("User:1", fields: ["name": "A", "age": 1]),
      record("User:2", fields: ["name": "B", "age": 2]),
    ])

    try db.deleteRecord(forKey: "User:1")

    let loaded = try db.selectRecords(forKeys: ["User:1", "User:2"])
    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(loaded[0].key, "User:2")
  }

  func test__deleteRecord_forKey__givenNonExistentKey_isNoOp() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["name": "A"])])

    XCTAssertNoThrow(try db.deleteRecord(forKey: "User:does-not-exist"))

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertEqual(loaded.count, 1)
  }

  func test__deleteRecords_matchingKey__removesMatchingPrefixes() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [
      record("Animal:cat", fields: ["name": "Whiskers"]),
      record("Animal:dog", fields: ["name": "Rex"]),
      record("User:1", fields: ["name": "Anthony"]),
    ])

    try db.deleteRecords(matchingKey: "Animal")

    let remaining = try db.selectRecords(forKeys: ["Animal:cat", "Animal:dog", "User:1"])
    XCTAssertEqual(remaining.count, 1)
    XCTAssertEqual(remaining[0].key, "User:1")
  }

  func test__deleteRecords_matchingKey__givenEmptyPattern_isNoOp() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["name": "A"])])

    XCTAssertNoThrow(try db.deleteRecords(matchingKey: ""))

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertEqual(loaded.count, 1)
  }

  func test__deleteRecords_matchingKey__escapesUnderscoreWildcard() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [
      record("User_admin", fields: ["name": "literal-underscore"]),
      record("UserA",      fields: ["name": "no-underscore"]),
      record("User:1",     fields: ["name": "colon-not-underscore"]),
    ])

    try db.deleteRecords(matchingKey: "User_")

    let remaining = try db.selectRecords(forKeys: ["User_admin", "UserA", "User:1"])
    let remainingKeys = Set(remaining.map(\.key))
    XCTAssertEqual(remainingKeys, ["UserA", "User:1"],
                   "Only literal 'User_' substring should match; \"_\" wildcard should be escaped")
  }

  func test__deleteRecords_matchingKey__escapesPercentWildcard() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [
      record("100%-coverage", fields: ["name": "literal-percent"]),
      record("UserA",         fields: ["name": "no-percent"]),
    ])

    try db.deleteRecords(matchingKey: "100%")

    let remaining = try db.selectRecords(forKeys: ["100%-coverage", "UserA"])
    let remainingKeys = Set(remaining.map(\.key))
    XCTAssertEqual(remainingKeys, ["UserA"])
  }

  // MARK: - Transactional behavior

  func test__insertOrUpdate__whenScalarEncodingFails_rollsBackEntireBatch() throws {
    let db = try makeDatabase()
    try db.insertOrUpdate(records: [record("User:1", fields: ["name": "A"])])

    struct Unencodable: Hashable, Sendable { let raw: String }
    let bad = record("User:2", fields: ["weird": Unencodable(raw: "bang")])
    let alsoGood = record("User:3", fields: ["name": "C"])

    XCTAssertThrowsError(try db.insertOrUpdate(records: [bad, alsoGood]))

    let loaded = try db.selectRecords(forKeys: ["User:1", "User:2", "User:3"])
    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(loaded[0].key, "User:1")
  }

  func test__insertOrUpdate__listWithUnencodableElement_throwsSwiftErrorNotAbort() throws {
    let db = try makeDatabase()
    // A `[Unencodable]` list. Each element triggers the encoder's
    // custom-scalar path which probes `isValidJSONObject` before
    // calling `JSONSerialization.data` — so the failure surfaces as
    // a Swift error (catchable) rather than an `NSException` abort
    // (uncatchable, would terminate the test process).
    struct Unencodable: Hashable, Sendable { let raw: String }
    let list: [Record.Value] = [Unencodable(raw: "bang") as Record.Value]
    let bad = Record(
      key: "QUERY_ROOT",
      fields: ["items": CachedField(value: list as Record.Value, writtenAt: 0)]
    )

    XCTAssertThrowsError(try db.insertOrUpdate(records: [bad])) { error in
      XCTAssertTrue(error is SQLiteFieldEncodingError)
    }
  }

  // MARK: - Custom-scalar (NSNull, generic dict, $reference disambig)

  func test__roundTrip__nsNull_atTopLevel() throws {
    let db = try makeDatabase()
    let original = Record(
      key: "User:1",
      fields: ["middleName": CachedField(value: NSNull(), writtenAt: 0)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertTrue(loaded[0].fields["middleName"]?.value is NSNull)
  }

  func test__roundTrip__genericDictionary() throws {
    let db = try makeDatabase()
    let dict: [String: Record.Value] = ["a": 1, "b": "two", "c": true]
    let original = Record(
      key: "Custom:1",
      fields: ["payload": CachedField(value: dict as Record.Value, writtenAt: 0)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["Custom:1"])
    let reloaded = loaded[0].fields["payload"]?.value as? [String: Any]
    XCTAssertEqual(reloaded?["a"] as? Int, 1)
    XCTAssertEqual(reloaded?["b"] as? String, "two")
    XCTAssertEqual(reloaded?["c"] as? Bool, true)
  }

  func test__roundTrip__dollarReferenceWithExtraKeys_treatedAsGenericDict() throws {
    let db = try makeDatabase()
    let dict: [String: Record.Value] = [
      "$reference": "not-actually-a-ref",
      "meta": 42,
    ]
    let original = Record(
      key: "Custom:1",
      fields: ["payload": CachedField(value: dict as Record.Value, writtenAt: 0)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["Custom:1"])
    let reloaded = loaded[0].fields["payload"]?.value as? [String: Any]
    XCTAssertEqual(reloaded?.count, 2,
                   "Both keys must survive — extra key was dropped under the lenient match")
    XCTAssertEqual(reloaded?["$reference"] as? String, "not-actually-a-ref")
    XCTAssertEqual(reloaded?["meta"] as? Int, 42)
    XCTAssertNil(loaded[0].fields["payload"]?.value as? CacheReference)
  }

  // MARK: - NSNumber Bool/numeric routing

  func test__roundTrip__nsNumberWrappedBool_staysBool() throws {
    let db = try makeDatabase()
    let original = Record(
      key: "User:1",
      fields: ["isActive": CachedField(value: NSNumber(value: true), writtenAt: 0)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertEqual(loaded[0].fields["isActive"]?.value as? Bool, true)
  }

  func test__roundTrip__nsNumberWrappedInt_staysInt() throws {
    let db = try makeDatabase()
    // `NSNumber(value: 1)` previously satisfied `as Bool` first and
    // landed in `bool_value`. CFType-aware routing must keep it in
    // `int_value` and round-trip as Int(1).
    let original = Record(
      key: "User:1",
      fields: ["count": CachedField(value: NSNumber(value: 1), writtenAt: 0)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["User:1"])
    XCTAssertEqual(loaded[0].fields["count"]?.value as? Int, 1)
    XCTAssertNil(loaded[0].fields["count"]?.value as? Bool,
                 "Integer NSNumber must not collapse to Bool")
  }

  func test__roundTrip__nsNumberWrappedDouble_staysDouble() throws {
    let db = try makeDatabase()
    let original = Record(
      key: "Stock:AAPL",
      fields: ["price": CachedField(value: NSNumber(value: 199.25), writtenAt: 0)]
    )

    try db.insertOrUpdate(records: [original])

    let loaded = try db.selectRecords(forKeys: ["Stock:AAPL"])
    XCTAssertEqual(loaded[0].fields["price"]?.value as? Double, 199.25)
  }

  // MARK: - Reserved-key audit (ADR 0006)

  func test__insertOrUpdate__givenKeyContainingReservedSyntheticToken__throwsAndWritesNothing() throws {
    let db = try makeDatabase()
    // `.$[` is reserved for synthetic sub-record keys. A user key
    // containing it (even without the trailing-digits shape the regex
    // classifier requires) must be rejected so the SQL `LIKE`
    // classifier can never match a stored user record.
    let reserved = record("Order:receipt.$[final]", fields: ["total": 10])

    expect { try db.insertOrUpdate(records: [reserved]) }.to(throwError { error in
      guard case SQLiteError.reservedCacheKey(let key) = error else {
        fail("Expected SQLiteError.reservedCacheKey, got \(error)")
        return
      }
      expect(key).to(equal("Order:receipt.$[final]"))
    })

    expect(try db.selectRecords(forKeys: ["Order:receipt.$[final]"])).to(beEmpty())
  }

  func test__insertOrUpdate__givenReservedKeyAnywhereInBatch__writesNoRecordsFromBatch() throws {
    let db = try makeDatabase()
    let good = record("User:1", fields: ["name": "Anthony"])
    let reserved = record("Item:x.$[3]", fields: ["qty": 1])

    expect { try db.insertOrUpdate(records: [good, reserved]) }.to(throwError())

    // The audit runs before the transaction opens: the valid record
    // in the same batch is not written either.
    expect(try db.selectRecords(forKeys: ["User:1"])).to(beEmpty())
  }

  // MARK: - Documented empty-record behavior

  func test__insertOrUpdate__emptyRecord_producesNoRows() throws {
    let db = try makeDatabase()
    let empty = Record(key: "User:empty", fields: [:])

    try db.insertOrUpdate(records: [empty])

    let loaded = try db.selectRecords(forKeys: ["User:empty"])
    XCTAssertEqual(loaded.count, 0)
  }

}
