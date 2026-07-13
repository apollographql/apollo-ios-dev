@testable @_spi(Execution) import Apollo
@_spi(Internal) @_spi(Execution) import ApolloAPI
import ApolloInternalTestHelpers
import Foundation
import Nimble
import XCTest

final class FieldProjectionTests: XCTestCase {

  // MARK: - Construction

  func test__init__storesArgumentsVerbatim() {
    let projection = FieldProjection(
      cacheKey: "User:42",
      fieldName: "name"
    )
    expect(projection.cacheKey) == "User:42"
    expect(projection.fieldName) == "name"
  }

  // MARK: - Equatable

  func test__equality__givenSamePair__returnsTrue() {
    let a = FieldProjection(cacheKey: "User:1", fieldName: "age")
    let b = FieldProjection(cacheKey: "User:1", fieldName: "age")
    expect(a) == b
  }

  func test__equality__givenDifferentCacheKey__returnsFalse() {
    let a = FieldProjection(cacheKey: "User:1", fieldName: "age")
    let b = FieldProjection(cacheKey: "User:2", fieldName: "age")
    expect(a) != b
  }

  func test__equality__givenDifferentFieldName__returnsFalse() {
    let a = FieldProjection(cacheKey: "User:1", fieldName: "age")
    let b = FieldProjection(cacheKey: "User:1", fieldName: "height")
    expect(a) != b
  }

  // MARK: - Hashable

  func test__hashable__equalProjectionsProduceEqualHashes() {
    let a = FieldProjection(cacheKey: "User:1", fieldName: "age")
    let b = FieldProjection(cacheKey: "User:1", fieldName: "age")
    expect(a.hashValue) == b.hashValue
  }

  func test__hashable__usableInSet__deduplicatesEqualValues() {
    let a = FieldProjection(cacheKey: "User:1", fieldName: "age")
    let b = FieldProjection(cacheKey: "User:1", fieldName: "age")
    let set: Set<FieldProjection> = [a, b]
    expect(set.count) == 1
  }
}
