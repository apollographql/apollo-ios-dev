@testable @_spi(Execution) import Apollo
import Foundation
import Nimble
import XCTest

final class CachedFieldTests: XCTestCase {

  // MARK: - Equatable

  func test__equality__givenSameValueAndTimestamp__returnsTrue() {
    let a = CachedField(value: "hello", writtenAt: 1_700_000_000)
    let b = CachedField(value: "hello", writtenAt: 1_700_000_000)
    expect(a) == b
  }

  func test__equality__givenDifferentTimestamp__returnsFalse() {
    let a = CachedField(value: "hello", writtenAt: 1_700_000_000)
    let b = CachedField(value: "hello", writtenAt: 1_700_000_001)
    expect(a) != b
  }

  func test__equality__givenDifferentValue__returnsFalse() {
    let a = CachedField(value: "hello", writtenAt: 1_700_000_000)
    let b = CachedField(value: "world", writtenAt: 1_700_000_000)
    expect(a) != b
  }

  func test__equality__acrossValueTypes__returnsFalse() {
    let intField = CachedField(value: 42, writtenAt: 100)
    let stringField = CachedField(value: "42", writtenAt: 100)
    expect(intField) != stringField
  }

  // MARK: - Hashable

  func test__hashable__equalValuesProduceEqualHashes() {
    let a = CachedField(value: 42, writtenAt: 100)
    let b = CachedField(value: 42, writtenAt: 100)
    expect(a.hashValue) == b.hashValue
  }

  func test__hashable__roundTripThroughSet__deduplicatesEqualValues() {
    let a = CachedField(value: "x", writtenAt: 1)
    let b = CachedField(value: "y", writtenAt: 1)
    let c = CachedField(value: "x", writtenAt: 1)  // equal to a
    let set: Set<CachedField> = [a, b, c]
    expect(set).to(haveCount(2))
    expect(set.contains(a)).to(beTrue())
    expect(set.contains(b)).to(beTrue())
  }

  func test__hashable__usableAsDictionaryKey() {
    let a = CachedField(value: "x", writtenAt: 1)
    let b = CachedField(value: "x", writtenAt: 2)  // different writtenAt
    var dict: [CachedField: String] = [:]
    dict[a] = "first"
    dict[b] = "second"
    expect(dict).to(haveCount(2))
    expect(dict[a]) == "first"
    expect(dict[b]) == "second"
  }

  // MARK: - Value-type round trips

  func test__init__supportsStringValues() {
    let field = CachedField(value: "hello", writtenAt: 0)
    expect(field.value as? String) == "hello"
  }

  func test__init__supportsIntValues() {
    let field = CachedField(value: 42, writtenAt: 0)
    expect(field.value as? Int) == 42
  }

  func test__init__supportsBoolValues() {
    let field = CachedField(value: true, writtenAt: 0)
    expect(field.value as? Bool) == true
  }

  func test__init__supportsDoubleValues() {
    let field = CachedField(value: 3.14, writtenAt: 0)
    expect(field.value as? Double) == 3.14
  }

  // MARK: - Date convenience init

  func test__initWithDate__truncatesToEpochSeconds() {
    let date = Date(timeIntervalSince1970: 1_700_000_000.789)
    let field = CachedField(value: "x", writtenAt: date)
    expect(field.writtenAt) == 1_700_000_000
  }

  func test__initWithDate__zeroDateIsEpochOrigin() {
    let field = CachedField(value: "x", writtenAt: Date(timeIntervalSince1970: 0))
    expect(field.writtenAt) == 0
  }

  // MARK: - Sendable

  /// Compile-time check: this test only builds if `CachedField` is
  /// `Sendable`-conformant. The runtime assertion is incidental.
  func test__sendable__crossActorTransferCompilesAndRoundTrips() async {
    let field = CachedField(value: "x", writtenAt: 1)
    let received = await withTaskGroup(of: CachedField.self, returning: CachedField.self) { group in
      group.addTask { field }
      var result: CachedField?
      for await delivered in group {
        result = delivered
      }
      return result!
    }
    expect(received) == field
  }

  // MARK: - CustomStringConvertible

  func test__description__includesValueAndTimestamp() {
    let field = CachedField(value: "hello", writtenAt: 42)
    expect(field.description) == "(hello @ 42)"
  }
}
