import XCTest
import Nimble
import ApolloAPI

final class InputDictTests: XCTestCase {

  private struct OperationInput: InputObject {
    public private(set) var __data: InputDict

    public init(_ data: InputDict) {
      __data = data
    }

    public init(
      stringField: String,
      nullableField: GraphQLNullable<String> = nil
    ) {
      __data = InputDict([
        "stringField": stringField,
        "nullableField": nullableField
      ])
    }

    public var stringField: String {
      get { __data["stringField"] }
      set { __data["stringField"] = newValue }
    }

    public var nullableField: GraphQLNullable<String> {
      get { __data["nullableField"] }
      set { __data["nullableField"] = newValue }
    }
  }

  func test__accessor__givenInputObjectNullableFieldInitializedWithDefaultValue_whenAccessingField_shouldEqualNilOrGraphQLNullableNone() throws {
    // given
    let input = OperationInput(stringField: "Something")

    // when
    let stringValue = input.stringField
    let nullableValue = input.nullableField

    // then
    expect(stringValue).to(equal("Something"))

    expect(nullableValue).to(equal(GraphQLNullable<String>.none))
    expect(nullableValue.unwrapped).to(beNil())
    XCTAssertEqual(nullableValue, nil)
  }

  func test__accessor__givenInputObjectNullableFieldInitializedWithValue_whenAccessingField_shouldEqualnitializedValue() throws {
    // given
    let input = OperationInput(stringField: "Something", nullableField: "AnotherThing")

    // when
    let stringValue = input.stringField
    let nullableValue = input.nullableField

    // then
    expect(stringValue).to(equal("Something"))

    expect(nullableValue).to(equal(GraphQLNullable.some("AnotherThing")))
    expect(nullableValue).to(equal("AnotherThing"))
    expect(nullableValue.unwrapped).to(equal("AnotherThing"))
  }

  func test__accessor__givenInputObjectNullableFieldInitializedWithNullValue_whenAccessingField_shouldEqualGraphQLNullableNull() throws {
    // given
    let input = OperationInput(stringField: "Something", nullableField: .null)

    // when
    let stringValue = input.stringField
    let nullableValue = input.nullableField

    // then
    expect(stringValue).to(equal("Something"))

    expect(nullableValue).to(equal(GraphQLNullable<String>.null))
  }

}
