@testable @_spi(Execution) import Apollo
import Foundation
import Nimble
import XCTest

final class CacheDependentKeyTests: XCTestCase {

  // MARK: - Equatable / Hashable

  func test__equality__givenSameCacheKeyAndFieldName__returnsTrue() {
    let a = CacheDependentKey(cacheKey: "Human:1000", fieldName: "name")
    let b = CacheDependentKey(cacheKey: "Human:1000", fieldName: "name")
    expect(a) == b
  }

  func test__equality__givenDifferentCacheKey__returnsFalse() {
    let a = CacheDependentKey(cacheKey: "Human:1000", fieldName: "name")
    let b = CacheDependentKey(cacheKey: "Human:1001", fieldName: "name")
    expect(a) != b
  }

  func test__equality__givenDifferentFieldName__returnsFalse() {
    let a = CacheDependentKey(cacheKey: "Human:1000", fieldName: "name")
    let b = CacheDependentKey(cacheKey: "Human:1000", fieldName: "homePlanet")
    expect(a) != b
  }

  func test__hashable__equalValuesProduceEqualHashes() {
    let a = CacheDependentKey(cacheKey: "Human:1000", fieldName: "name")
    let b = CacheDependentKey(cacheKey: "Human:1000", fieldName: "name")
    expect(a.hashValue) == b.hashValue
  }

  func test__hashable__usableInSet__deduplicatesEqualValues() {
    let key = CacheDependentKey(cacheKey: "Human:1000", fieldName: "name")
    let set: Set<CacheDependentKey> = [key, key]
    expect(set).to(haveCount(1))
  }

  // MARK: - CustomStringConvertible

  func test__description__formatsAsCacheKeyDotFieldName() {
    let key = CacheDependentKey(cacheKey: "Human:1000", fieldName: "name")
    expect(key.description) == "Human:1000.name"
  }

  func test__description__preservesEmbeddedRecordPath() {
    // Embedded sub-objects synthesize a multi-segment record key
    // (the writer joins the response path with `.`); the description
    // round-trips that verbatim.
    let key = CacheDependentKey(cacheKey: "QUERY_ROOT.animal", fieldName: "genus")
    expect(key.description) == "QUERY_ROOT.animal.genus"
  }
}
