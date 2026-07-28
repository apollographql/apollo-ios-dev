@_spi(Execution) import ApolloInternalTestHelpers
@testable @_spi(Execution) import Apollo
import Foundation
import Nimble
import XCTest

class LoadFieldsTests: XCTestCase, CacheDependentTesting {
  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  // CacheDependentTesting requires a `store` to share infrastructure with
  // other cache-dependent tests, but loadFields is a cache-level method
  // that the store doesn't expose yet (per ADR 0007's plan, the store
  // adopts the new API in PR-009e). These tests exercise the cache
  // directly via `makeNormalizedCache()`; the `store` slot stays nil.
  var store: ApolloStore!

  // MARK: - Empty input

  func test__loadFields__givenEmptyProjections__returnsEmptyDictionary() async throws {
    let (cache, _) = await cacheType.makeNormalizedCache()
    try await seed(cache: cache, records: [
      Record(key: "User:1", fields: ["name": CachedField(value: "Alice", writtenAt: 0)])
    ])

    let result = try await cache.loadFields([])
    expect(result.isEmpty) == true
  }

  func test__loadFields__givenEmptyCache__returnsEmptyDictionary() async throws {
    let (cache, _) = await cacheType.makeNormalizedCache()

    let result = try await cache.loadFields([
      RecordProjection(cacheKey: "User:1", fieldNames: ["name"])
    ])
    expect(result.isEmpty) == true
  }

  func test__loadFields__givenProjectionsForOnlyMissingKeys__returnsEmptyDictionary() async throws {
    let (cache, _) = await cacheType.makeNormalizedCache()
    try await seed(cache: cache, records: [
      Record(key: "User:1", fields: ["name": CachedField(value: "Alice", writtenAt: 0)])
    ])

    let result = try await cache.loadFields([
      RecordProjection(cacheKey: "User:2", fieldNames: ["name"]),
      RecordProjection(cacheKey: "User:3", fieldNames: ["name"]),
    ])
    expect(result.isEmpty) == true
  }

  // MARK: - Field projection (the core promise)

  func test__loadFields__givenProjectionForOneField__returnsOnlyThatField() async throws {
    let (cache, _) = await cacheType.makeNormalizedCache()
    try await seed(cache: cache, records: [
      Record(key: "User:1", fields: [
        "name": CachedField(value: "Alice", writtenAt: 0),
        "age": CachedField(value: 30, writtenAt: 0),
        "email": CachedField(value: "alice@example.com", writtenAt: 0),
      ])
    ])

    let result = try await cache.loadFields([
      RecordProjection(cacheKey: "User:1", fieldNames: ["name"])
    ])

    expect(result.count) == 1
    let record = try XCTUnwrap(result["User:1"])
    expect(record.fields.keys.sorted()) == ["name"]
    expect(record["name"] as? String) == "Alice"
  }

  func test__loadFields__givenMultipleProjectionsOnSameKey__returnsRequestedFieldsCombined() async throws {
    let (cache, _) = await cacheType.makeNormalizedCache()
    try await seed(cache: cache, records: [
      Record(key: "User:1", fields: [
        "name": CachedField(value: "Alice", writtenAt: 0),
        "age": CachedField(value: 30, writtenAt: 0),
        "email": CachedField(value: "alice@example.com", writtenAt: 0),
      ])
    ])

    let result = try await cache.loadFields([
      RecordProjection(cacheKey: "User:1", fieldNames: ["name"]),
      RecordProjection(cacheKey: "User:1", fieldNames: ["age"]),
    ])

    expect(result.count) == 1
    let record = try XCTUnwrap(result["User:1"])
    expect(record.fields.keys.sorted()) == ["age", "name"]
    expect(record["name"] as? String) == "Alice"
    expect(record["age"] as? Int) == 30
    // "email" was not requested even though it exists in storage.
    expect(record["email"]).to(beNil())
  }

  func test__loadFields__givenProjectionsAcrossMultipleKeys__partitionsByKey() async throws {
    let (cache, _) = await cacheType.makeNormalizedCache()
    try await seed(cache: cache, records: [
      Record(key: "User:1", fields: [
        "name": CachedField(value: "Alice", writtenAt: 0),
        "age": CachedField(value: 30, writtenAt: 0),
      ]),
      Record(key: "User:2", fields: [
        "name": CachedField(value: "Bob", writtenAt: 0),
        "email": CachedField(value: "bob@example.com", writtenAt: 0),
      ]),
    ])

    let result = try await cache.loadFields([
      RecordProjection(cacheKey: "User:1", fieldNames: ["name"]),
      RecordProjection(cacheKey: "User:2", fieldNames: ["email"]),
    ])

    expect(result.count) == 2
    let user1 = try XCTUnwrap(result["User:1"])
    expect(user1.fields.keys.sorted()) == ["name"]
    expect(user1["name"] as? String) == "Alice"

    let user2 = try XCTUnwrap(result["User:2"])
    expect(user2.fields.keys.sorted()) == ["email"]
    expect(user2["email"] as? String) == "bob@example.com"
  }

  // MARK: - Partial-presence behavior

  func test__loadFields__givenMixedPresentAndMissingKeys__returnsOnlyPresentKeys() async throws {
    let (cache, _) = await cacheType.makeNormalizedCache()
    try await seed(cache: cache, records: [
      Record(key: "User:1", fields: ["name": CachedField(value: "Alice", writtenAt: 0)])
    ])

    let result = try await cache.loadFields([
      RecordProjection(cacheKey: "User:1", fieldNames: ["name"]),
      RecordProjection(cacheKey: "User:99", fieldNames: ["name"]),
    ])

    expect(result.count) == 1
    expect(result["User:1"]).toNot(beNil())
    expect(result["User:99"]).to(beNil())
  }

  func test__loadFields__givenFieldMissingFromPresentRecord__returnsEmptyFieldsRecord() async throws {
    // A cache key whose record exists, but the *requested* field doesn't.
    // The contract — per the doc on `loadFields(_:)` — is that the
    // record-existence signal goes through verbatim: the key appears
    // in the result with an empty `fields` dictionary. The executor
    // relies on this distinction to wrap per-field `missingValue`
    // errors with response-path context (rather than failing the
    // whole record-level lookup at the cache boundary).
    let (cache, _) = await cacheType.makeNormalizedCache()
    try await seed(cache: cache, records: [
      Record(key: "User:1", fields: ["name": CachedField(value: "Alice", writtenAt: 0)])
    ])

    let result = try await cache.loadFields([
      RecordProjection(cacheKey: "User:1", fieldNames: ["nonExistentField"])
    ])

    expect(result.count) == 1
    let record = try XCTUnwrap(result["User:1"])
    expect(record.fields.isEmpty) == true
  }

  func test__loadFields__givenSomeFieldsPresentAndSomeAbsent__returnsOnlyPresentFields() async throws {
    let (cache, _) = await cacheType.makeNormalizedCache()
    try await seed(cache: cache, records: [
      Record(key: "User:1", fields: ["name": CachedField(value: "Alice", writtenAt: 0)])
    ])

    let result = try await cache.loadFields([
      RecordProjection(cacheKey: "User:1", fieldNames: ["name"]),
      RecordProjection(cacheKey: "User:1", fieldNames: ["missing"]),
    ])

    let record = try XCTUnwrap(result["User:1"])
    expect(record.fields.keys.sorted()) == ["name"]
  }

  // MARK: - Deduplication tolerance

  func test__loadFields__givenDuplicateProjections__coalescesIntoSingleFieldEntry() async throws {
    // The doc explicitly tolerates duplicate projections. The result
    // should have one entry per `(cacheKey, fieldName)` regardless of
    // how many times the same projection was supplied.
    let (cache, _) = await cacheType.makeNormalizedCache()
    try await seed(cache: cache, records: [
      Record(key: "User:1", fields: ["name": CachedField(value: "Alice", writtenAt: 0)])
    ])

    let projection = RecordProjection(cacheKey: "User:1", fieldNames: ["name"])

    let result = try await cache.loadFields([projection, projection, projection])

    expect(result.count) == 1
    let record = try XCTUnwrap(result["User:1"])
    expect(record.fields.count) == 1
    expect(record["name"] as? String) == "Alice"
  }

  // MARK: - List + reference fields round-trip

  func test__loadFields__givenListField__returnsArrayValue() async throws {
    let (cache, _) = await cacheType.makeNormalizedCache()
    try await seed(cache: cache, records: [
      Record(key: "User:1", fields: [
        "tags": CachedField(value: ["swift", "graphql"] as Record.Value, writtenAt: 0)
      ])
    ])

    let result = try await cache.loadFields([
      RecordProjection(cacheKey: "User:1", fieldNames: ["tags"])
    ])

    let record = try XCTUnwrap(result["User:1"])
    let tags = try XCTUnwrap(record["tags"] as? [String])
    expect(tags) == ["swift", "graphql"]
  }

  func test__loadFields__givenCacheReferenceField__returnsReference() async throws {
    let (cache, _) = await cacheType.makeNormalizedCache()
    try await seed(cache: cache, records: [
      Record(key: "Query.viewer", fields: [
        "user": CachedField(value: CacheReference("User:1") as Record.Value, writtenAt: 0)
      ])
    ])

    let result = try await cache.loadFields([
      RecordProjection(cacheKey: "Query.viewer", fieldNames: ["user"])
    ])

    let record = try XCTUnwrap(result["Query.viewer"])
    expect(record["user"] as? CacheReference) == CacheReference("User:1")
  }

  // MARK: - Helpers

  /// Writes the given records into the cache so they are observable to
  /// `loadFields`. Wraps `merge(records:)` so individual test bodies
  /// stay focused on the assertion.
  private func seed(
    cache: any NormalizedCache,
    records: [Record]
  ) async throws {
    let recordSet = RecordSet(records: records)
    _ = try await cache.merge(records: recordSet)
  }
}
