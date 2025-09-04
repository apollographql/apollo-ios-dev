@_spi(Internal) @_spi(Unsafe) import ApolloAPI
import Nimble
import XCTest

final class InputDictTests: XCTestCase {

  /// ```graphql
  /// input OperationInput {
  ///   stringField: String!
  ///   nullableField: String
  ///   requiredFieldWithDefaultValue: String! = "Default"
  ///   nullableFieldWithDefaultValue: String = "Default"
  /// }
  /// ```
  private struct OperationInput: InputObject {
    public private(set) var __data: InputDict

    public init(_ data: InputDict) {
      __data = data
    }

    public init(
      stringField: String,
      nullableField: GraphQLNullable<String> = nil,
      requiredFieldWithDefaultValue: String? = nil,
      nullableFieldWithDefaultValue: GraphQLNullable<String> = nil
    ) {
      __data = InputDict([
        "stringField": stringField,
        "nullableField": nullableField,
        "requiredFieldWithDefaultValue": requiredFieldWithDefaultValue ?? GraphQLNullable.none,
        "nullableFieldWithDefaultValue": nullableFieldWithDefaultValue,
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

    public var requiredFieldWithDefaultValue: String? {
      get { __data["requiredFieldWithDefaultValue"] }
      set { __data["requiredFieldWithDefaultValue"] = newValue }
    }

    public var nullableFieldWithDefaultValue: GraphQLNullable<String> {
      get { __data["nullableFieldWithDefaultValue"] }
      set { __data["nullableFieldWithDefaultValue"] = newValue }
    }

  }

  // MARK: - Field Accessor Tests

  func
    test__accessor__given_nullableField_initializedWithDefaultValue_whenAccessingField_shouldEqualNilOrGraphQLNullableNone()
    throws
  {
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

  func test__accessor__given_nullableField_initializedWithValue_whenAccessingField_shouldEqualnitializedValue() throws {
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

  func test__accessor__given_nullableField_initializedWithNullValue_whenAccessingField_shouldEqualGraphQLNullableNull()
    throws
  {
    // given
    let input = OperationInput(stringField: "Something", nullableField: .null)

    // when
    let stringValue = input.stringField
    let nullableValue = input.nullableField

    // then
    expect(stringValue).to(equal("Something"))

    expect(nullableValue).to(equal(GraphQLNullable<String>.null))
  }

  func
    test__accessor__given_requiredFieldWithDefaultValue_using_defaultValue_whenAccessingField_should_beNil()
    throws
  {
    // given
    let input = OperationInput(
      stringField: "Something"
    )

    // when
    let value = input.requiredFieldWithDefaultValue

    // then
    expect(value).to(beNil())
  }

  func
    test__accessor__given_requiredFieldWithDefaultValue_initializedWith_nil_whenAccessingField_should_beNil()
    throws
  {
    // given
    let input = OperationInput(
      stringField: "Something",
      requiredFieldWithDefaultValue: nil
    )

    // when
    let value = input.requiredFieldWithDefaultValue

    // then
    expect(value).to(beNil())
  }

  func
    test__accessor__given_requiredFieldWithDefaultValue_initializedWith_newValue_whenAccessingField_should_haveNewValue()
    throws
  {
    // given
    let expected = "TestValue"

    let input = OperationInput(
      stringField: "Something",
      requiredFieldWithDefaultValue: expected
    )

    // when
    let value = input.requiredFieldWithDefaultValue

    // then
    expect(value).to(equal(expected))
  }

  func
    test__accessor__given_nullableFieldWithDefaultValue_using_defaultValue_whenAccessingField_should_be_none()
    throws
  {
    // given
    let input = OperationInput(
      stringField: "Something"
    )

    // when
    let value = input.nullableFieldWithDefaultValue

    // then
    expect(value).to(equal(GraphQLNullable.none))
  }

  func
    test__accessor__given_nullableFieldWithDefaultValue_initializedWith_nil_whenAccessingField_should_be_none()
    throws
  {
    // given
    let input = OperationInput(
      stringField: "Something",
      nullableFieldWithDefaultValue: nil
    )

    // when
    let value = input.nullableFieldWithDefaultValue

    // then
    expect(value).to(equal(GraphQLNullable.none))
  }

  func
    test__accessor__given_nullableFieldWithDefaultValue_initializedWith_newValue_whenAccessingField_should_haveNewValue()
    throws
  {
    // given
    let expected = "TestValue"

    let input = OperationInput(
      stringField: "Something",
      nullableFieldWithDefaultValue: .some(expected)
    )

    // when
    let value = input.nullableFieldWithDefaultValue

    // then
    expect(value.unwrapped).to(equal(expected))
  }

  // MARK: - Setter Tests

  func
    test__setter__given_nullableField_setTo_value_whenAccessingField_shouldEqualValue()
    throws
  {
    // given
    let expected = "TestValue"
    var input = OperationInput(stringField: "Something")

    // when
    input.stringField = expected
    input.nullableField = .some(expected)

    // then
    expect(input.stringField).to(equal(expected))
    expect(input.nullableField.unwrapped).to(equal(expected))
  }

  func test__setter__given_nullableField_setTo_null_whenAccessingField_shouldEqual_null() throws {
    // given
    var input = OperationInput(stringField: "Something", nullableField: "AnotherThing")

    // when
    input.nullableField = .null

    // then
    expect(input.nullableField).to(equal(GraphQLNullable.null))
  }

  func test__setter__given_nullableField_setTo_none_whenAccessingField_shouldEqual_none() throws {
    // given
    var input = OperationInput(stringField: "Something", nullableField: "AnotherThing")

    // when
    input.nullableField = .none

    // then
    expect(input.nullableField).to(equal(GraphQLNullable.none))
  }

  func
    test__setter__given_requiredFieldWithDefaultValue_setTo_nil_whenAccessingField_should_beNil()
    throws
  {
    // given
    var input = OperationInput(
      stringField: "Something"
    )

    // when
    input.requiredFieldWithDefaultValue = nil

    // then
    expect(input.requiredFieldWithDefaultValue).to(beNil())
  }

  func
    test__setter__given_requiredFieldWithDefaultValue_setTo_newValue_whenAccessingField_should_haveNewValue()
    throws
  {
    // given
    let expected = "TestValue"

    var input = OperationInput(
      stringField: "Something"
    )

    // when
    input.requiredFieldWithDefaultValue = expected

    // then
    expect(input.requiredFieldWithDefaultValue).to(equal(expected))
  }

  func
    test__setter__given_nullableFieldWithDefaultValue_setTo_nil_whenAccessingField_should_beNil()
    throws
  {
    // given
    var input = OperationInput(
      stringField: "Something"
    )

    // when
    input.nullableFieldWithDefaultValue = nil

    // then
    expect(input.nullableFieldWithDefaultValue).to(equal(GraphQLNullable.none))
  }

  func
    test__setter__given_nullableFieldWithDefaultValue_setTo_null_whenAccessingField_should_beNil()
    throws
  {
    // given
    var input = OperationInput(
      stringField: "Something"
    )

    // when
    input.nullableFieldWithDefaultValue = .null

    // then
    expect(input.nullableFieldWithDefaultValue).to(equal(.null))
  }

  func
    test__setter__given_nullableFieldWithDefaultValue_setTo_newValue_whenAccessingField_should_haveNewValue()
    throws
  {
    // given
    let expected = "TestValue"

    var input = OperationInput(
      stringField: "Something"
    )

    // when
    input.nullableFieldWithDefaultValue = .some(expected)

    // then
    expect(input.nullableFieldWithDefaultValue.unwrapped).to(equal(expected))
  }

  // MARK: - jsonEncodableValue Tests

  func
    test__jsonEncodableValue__given_requiredFieldWithDefaultValue_using_defaultValue_whenAccessingField_shouldEqualGraphQLNullable_none()
    throws
  {
    // given
    let input = OperationInput(
      stringField: "Something"
    )

    // when
    let jsonObject = input._jsonEncodableValue as? JSONObject
    let value: Any? = jsonObject?["requiredFieldWithDefaultValue"]

    // then
    expect(value).to(beNil())
  }

  func
    test__jsonEncodableValue__given_requiredFieldWithDefaultValue_initializedWith_nil_whenAccessingField_shouldEqualGraphQLNullable_none()
    throws
  {
    // given
    let input = OperationInput(
      stringField: "Something",
      requiredFieldWithDefaultValue: nil
    )

    // when
    let jsonObject = input._jsonEncodableValue as? JSONObject
    let value: Any? = jsonObject?["requiredFieldWithDefaultValue"]

    // then
    expect(value).to(beNil())
  }

  func
    test__jsonEncodableValue__given_requiredFieldWithDefaultValue_initializedWith_newValue_whenAccessingField_should_haveNewValue()
    throws
  {
    // given
    let expected = "TestValue"

    let input = OperationInput(
      stringField: "Something",
      requiredFieldWithDefaultValue: expected
    )

    // when
    let jsonObject = input._jsonEncodableValue?._jsonValue as? JSONObject
    let value: Any? = jsonObject?["requiredFieldWithDefaultValue"]

    // then
    expect(value as? String).to(equal(expected))
  }

  func
    test__jsonEncodableValue__given_nullableFieldWithDefaultValue_using_defaultValue_whenAccessingField_shouldEqualGraphQLNullable_none()
    throws
  {
    // given
    let input = OperationInput(
      stringField: "Something"
    )

    // when
    let jsonObject = input._jsonEncodableValue as? JSONObject
    let value: Any? = jsonObject?["nullableFieldWithDefaultValue"]

    // then
    expect(value).to(beNil())
  }

  func
    test__jsonEncodableValue__given_nullableFieldWithDefaultValue_initializedWith_nil_whenAccessingField_shouldEqualGraphQLNullable_none()
    throws
  {
    // given
    let input = OperationInput(
      stringField: "Something",
      nullableFieldWithDefaultValue: nil
    )

    // when
    let jsonObject = input._jsonEncodableValue as? JSONObject
    let value: Any? = jsonObject?["nullableFieldWithDefaultValue"]

    // then
    expect(value).to(beNil())
  }

  func
    test__jsonEncodableValue__given_nullableFieldWithDefaultValue_initializedWith_newValue_whenAccessingField_should_haveNewValue()
    throws
  {
    // given
    let expected = "TestValue"

    let input = OperationInput(
      stringField: "Something",
      nullableFieldWithDefaultValue: .some(expected)
    )

    // when
    let jsonObject = input._jsonEncodableValue?._jsonValue as? JSONObject
    let value: Any? = jsonObject?["nullableFieldWithDefaultValue"]

    // then
    expect(value as? String).to(equal(expected))
  }

}
