@testable @_spi(Execution) import Apollo
import Foundation
import Nimble
import XCTest

/// Verifies the structured-dependency-key surface of `RecordSet.merge`
/// — the set the cache emits to subscribers when a publish lands.
/// This is the writer-side counterpart of the dependency-tracker tests:
/// PR-009f's correctness rests on both producers emitting matching
/// `(cacheKey, fieldName)` pairs.
final class RecordSetMergeTests: XCTestCase {

  // MARK: - New record

  func test__merge__givenNewRecord__returnsEveryFieldAsChanged() {
    var set = RecordSet()
    let changed = set.merge(record: Record(
      key: "Human:1000",
      ["__typename": "Human", "name": "Luke"]
    ))

    expect(changed) == [
      CacheDependentKey(cacheKey: "Human:1000", fieldName: "__typename"),
      CacheDependentKey(cacheKey: "Human:1000", fieldName: "name"),
    ]
  }

  // MARK: - Existing record, unchanged value

  func test__merge__givenExistingRecord_unchangedValue__omitsFieldFromChangedSet() {
    var set = RecordSet()
    _ = set.merge(record: Record(
      key: "Human:1000",
      ["__typename": "Human", "name": "Luke"]
    ))

    let changed = set.merge(record: Record(
      key: "Human:1000",
      ["__typename": "Human", "name": "Luke"]
    ))

    expect(changed).to(beEmpty())
  }

  // MARK: - Existing record, changed value

  func test__merge__givenExistingRecord_singleFieldChanged__returnsOnlyThatField() {
    var set = RecordSet()
    _ = set.merge(record: Record(
      key: "Human:1000",
      ["__typename": "Human", "name": "Luke"]
    ))

    let changed = set.merge(record: Record(
      key: "Human:1000",
      ["__typename": "Human", "name": "Han"]
    ))

    expect(changed) == [CacheDependentKey(cacheKey: "Human:1000", fieldName: "name")]
  }

  // MARK: - Multiple records

  func test__merge__givenMultipleNewRecords__returnsEveryFieldAcrossAllRecords() {
    var set = RecordSet()
    let changed = set.merge(records: RecordSet(records: [
      Record(key: "Human:1000", ["name": "Luke"]),
      Record(key: "Human:1002", ["name": "Han"]),
    ]))

    expect(changed) == [
      CacheDependentKey(cacheKey: "Human:1000", fieldName: "name"),
      CacheDependentKey(cacheKey: "Human:1002", fieldName: "name"),
    ]
  }

  // MARK: - Embedded sub-object record key

  func test__merge__givenEmbeddedSubObjectRecord__preservesDotInCacheKey() {
    // The writer normalizes an embedded sub-object (no `@typePolicy`)
    // to a record whose key carries the response path joined with `.`.
    // The merge surface preserves that boundary verbatim — `fieldName`
    // is the storage-layer field name only, never inheriting prefix
    // segments from the record key.
    var set = RecordSet()
    let changed = set.merge(record: Record(
      key: "QUERY_ROOT.animal",
      ["genus": "Canis"]
    ))

    expect(changed) == [CacheDependentKey(cacheKey: "QUERY_ROOT.animal", fieldName: "genus")]
  }
}
