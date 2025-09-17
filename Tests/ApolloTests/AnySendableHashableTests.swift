@_spi(Internal) @_spi(Unsafe) import ApolloAPI
import XCTest
import Nimble

final class AnySendableHashableTests: XCTestCase {

  func test__equality__givenSameType_sameValue_returnsTrue() {
    let foo1: String = "foo"
    let foo2: String = "foo"

    expect(AnySendableHashable.equatableCheck(foo1, foo2)).to(beTrue())
  }

  func test__equality__givenSameType_differentValue_returnsFalse() {
    let foo: String = "foo"
    let bar: String = "bar"

    expect(AnySendableHashable.equatableCheck(foo, bar)).to(beFalse())
  }

  func test__equality__givenSameTypeWithOptionality_sameValue_returnsTrue() {
    let fooOptional: String? = "foo"
    let foo: String = "foo"

    expect(AnySendableHashable.equatableCheck(fooOptional, foo)).to(beTrue())
  }

  func test__equality__givenSameTypeWithOptionality_lhsNil_returnsFalse() {
    let optionalNil: String? = nil
    let foo: String = "foo"

    expect(AnySendableHashable.equatableCheck(optionalNil, foo)).to(beFalse())
  }

  func test__equality__givenNonEquatableType_returnsFalse() {
    let one: String = "1"
    let num: Int = 1

    expect(AnySendableHashable.equatableCheck(one, num)).to(beFalse())
  }

  func test__equality__givenNonEquatableType_withOptionality_lhsNil_returnsFalse() {
    let optionalNil: String? = nil
    let num: Int = 1

    expect(AnySendableHashable.equatableCheck(optionalNil, num)).to(beFalse())
  }

  func test__equality__givenDataDict_lhsBaseTypeOptional_sameValue_returnsTrue() {
    let fooOptional: String? = "foo"
    let lhs: DataDict = DataDict(data: ["key": fooOptional], fulfilledFragments: [])
    let foo: String = "foo"
    let rhs: DataDict = DataDict(data: ["key": foo], fulfilledFragments: [])

    expect(AnySendableHashable.equatableCheck(lhs, rhs)).to(beTrue())
  }

}
