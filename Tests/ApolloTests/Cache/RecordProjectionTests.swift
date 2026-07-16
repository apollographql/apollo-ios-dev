@testable @_spi(Execution) import Apollo
@_spi(Internal) @_spi(Execution) import ApolloAPI
import ApolloInternalTestHelpers
import Foundation
import Nimble
import XCTest

final class RecordProjectionTests: XCTestCase {

  // MARK: - Construction

  func test__init__storesArgumentsVerbatim() {
    let projection = RecordProjection(
      cacheKey: "User:42",
      fieldNames: ["name", "age"]
    )
    expect(projection.cacheKey) == "User:42"
    expect(projection.fieldNames) == ["name", "age"]
  }

  // MARK: - Equatable

  func test__equality__givenSameKeyAndFieldNames__returnsTrue() {
    let a = RecordProjection(cacheKey: "User:1", fieldNames: ["age", "name"])
    let b = RecordProjection(cacheKey: "User:1", fieldNames: ["name", "age"])
    expect(a) == b
  }

  func test__equality__givenDifferentCacheKey__returnsFalse() {
    let a = RecordProjection(cacheKey: "User:1", fieldNames: ["age"])
    let b = RecordProjection(cacheKey: "User:2", fieldNames: ["age"])
    expect(a) != b
  }

  func test__equality__givenDifferentFieldNames__returnsFalse() {
    // A projection is a transfer value, not an accumulator: same-key
    // projections with different field sets are distinct values.
    // APIs accepting `[RecordProjection]` merge them to the union of
    // their field names; accumulation code uses a
    // `[CacheKey: Set<String>]` dictionary instead of `Set`.
    let a = RecordProjection(cacheKey: "User:1", fieldNames: ["age"])
    let b = RecordProjection(cacheKey: "User:1", fieldNames: ["age", "name"])
    expect(a) != b
  }

  // MARK: - Hashable

  func test__hashable__equalProjectionsProduceEqualHashes() {
    let a = RecordProjection(cacheKey: "User:1", fieldNames: ["age", "name"])
    let b = RecordProjection(cacheKey: "User:1", fieldNames: ["name", "age"])
    expect(a.hashValue) == b.hashValue
  }

  func test__hashable__usableInSet__deduplicatesEqualValues() {
    let a = RecordProjection(cacheKey: "User:1", fieldNames: ["age"])
    let b = RecordProjection(cacheKey: "User:1", fieldNames: ["age"])
    let set: Set<RecordProjection> = [a, b]
    expect(set.count) == 1
  }
}
