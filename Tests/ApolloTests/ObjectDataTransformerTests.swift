import XCTest
import Nimble
import ApolloAPI

class ObjectDataTransformerTests: XCTestCase {

  fileprivate struct DataTransformer: _ObjectData_Transformer {
    func transform(_ value: any Hashable & Sendable) -> (any ScalarType)? {
      switch value {
      case let scalar as any ScalarType:
        return scalar
      default:
        return nil
      }
    }

    // Empty until needed in tests
    func transform(_ value: any Hashable & Sendable) -> ObjectData? { return nil }
    func transform(_ value: any Hashable & Sendable) -> ListData? { return nil }
  }

  // MARK: ObjectData Tests

  func test__ObjectData_subscript_ScalarType__givenData_asInt_equalToBoolFalse_shouldReturnInt32Type() {
    // given
    let dataTransformer = ObjectData(
      _transformer: DataTransformer(),
      _rawData: ["intKey": 0]
    )

    // when
    let actual = dataTransformer["intKey"]

    // then
    expect(actual).to(beAnInstanceOf(Int32.self))
  }

  func test__ObjectData_subscript_ScalarType__givenData_asInt_equalToBoolTrue_shouldReturnInt32Type() {
    // given
    let dataTransformer = ObjectData(
      _transformer: DataTransformer(),
      _rawData: ["intKey": 1]
    )

    // when
    let actual = dataTransformer["intKey"]

    // then
    expect(actual).to(beAnInstanceOf(Int32.self))
  }

  func test__ObjectData_subscript_ScalarType__givenData_asInt_outsideBoolRange_shouldReturnInt32Type() {
    // given
    let dataTransformer = ObjectData(
      _transformer: DataTransformer(),
      _rawData: ["intKey": 2]
    )

    // when
    let actual = dataTransformer["intKey"]

    // then
    expect(actual).to(beAnInstanceOf(Int32.self))
  }

  func test__ObjectData_subscript_ScalarType__givenData_asBool_true_shouldReturnBoolType() {
    // given
    let dataTransformer = ObjectData(
      _transformer: DataTransformer(),
      _rawData: ["boolKey": true]
    )

    // when
    let actual = dataTransformer["boolKey"]

    // then
    expect(actual).to(beAnInstanceOf(Bool.self))
  }

  func test__ObjectData_subscript_ScalarType__givenData_asBool_false_shouldReturnBoolType() {
    // given
    let dataTransformer = ObjectData(
      _transformer: DataTransformer(),
      _rawData: ["boolKey": false]
    )

    // when
    let actual = dataTransformer["boolKey"]

    // then
    expect(actual).to(beAnInstanceOf(Bool.self))
  }

  // MARK: ListData Tests

  func test__ListData_subscript_ScalarType__givenData_asInt_equalToBoolFalse_shouldReturnInt32Type() {
    // given
    let dataTransformer = ListData(_transformer: DataTransformer(), _rawData: [0])

    // when
    let actual = dataTransformer[0]

    // then
    expect(actual).to(beAnInstanceOf(Int32.self))
  }

  func test__ListData_subscript_ScalarType__givenData_asInt_equalToBoolTrue_shouldReturnInt32Type() {
    // given
    let dataTransformer = ListData(_transformer: DataTransformer(), _rawData: [1])

    // when
    let actual = dataTransformer[0]

    // then
    expect(actual).to(beAnInstanceOf(Int32.self))
  }

  func test__ListData_subscript_ScalarType__givenData_asInt_outsideBoolRange_shouldReturnInt32Type() {
    // given
    let dataTransformer = ListData(_transformer: DataTransformer(), _rawData: [2])

    // when
    let actual = dataTransformer[0]

    // then
    expect(actual).to(beAnInstanceOf(Int32.self))
  }

  func test__ListData_subscript_ScalarType__givenData_asBool_true_shouldReturnBoolType() {
    // given
    let dataTransformer = ListData(_transformer: DataTransformer(), _rawData: [true])

    // when
    let actual = dataTransformer[0]

    // then
    expect(actual).to(beAnInstanceOf(Bool.self))
  }

  func test__ListData_subscript_ScalarType__givenData_asBool_false_shouldReturnBoolType() {
    // given
    let dataTransformer = ListData(_transformer: DataTransformer(), _rawData: [false])

    // when
    let actual = dataTransformer[0]

    // then
    expect(actual).to(beAnInstanceOf(Bool.self))
  }
}
