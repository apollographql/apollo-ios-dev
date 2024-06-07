import XCTest
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

class JSONTests: XCTestCase {
  func testMissingValueMatchable() {
    let value = JSONDecodingError.missingValue

    XCTAssertTrue(value ~= JSONDecodingError.missingValue)
    XCTAssertFalse(value ~= JSONDecodingError.nullValue)
    XCTAssertFalse(value ~= JSONDecodingError.wrongType)
    XCTAssertFalse(value ~= JSONDecodingError.couldNotConvert(value: 123, to: Int.self))
  }

  func testNullValueMatchable() {
    let value = JSONDecodingError.nullValue

    XCTAssertTrue(value ~= JSONDecodingError.nullValue)
    XCTAssertFalse(value ~= JSONDecodingError.missingValue)
    XCTAssertFalse(value ~= JSONDecodingError.wrongType)
    XCTAssertFalse(value ~= JSONDecodingError.couldNotConvert(value: 123, to: Int.self))
  }

  func testWrongTypeMatchable() {
    let value = JSONDecodingError.wrongType

    XCTAssertTrue(value ~= JSONDecodingError.wrongType)
    XCTAssertFalse(value ~= JSONDecodingError.nullValue)
    XCTAssertFalse(value ~= JSONDecodingError.missingValue)
    XCTAssertFalse(value ~= JSONDecodingError.couldNotConvert(value: 123, to: Int.self))
  }

  func testCouldNotConvertMatchable() {
    let value = JSONDecodingError.couldNotConvert(value: 123, to: Int.self)

    XCTAssertTrue(value ~= JSONDecodingError.couldNotConvert(value: 123, to: Int.self))
    XCTAssertTrue(value ~= JSONDecodingError.couldNotConvert(value: "abc", to: String.self))
    XCTAssertFalse(value ~= JSONDecodingError.wrongType)
    XCTAssertFalse(value ~= JSONDecodingError.nullValue)
    XCTAssertFalse(value ~= JSONDecodingError.missingValue)
  }
  
  func testJSONDictionaryEncodingAndDecoding() throws {
    let jsonString = """
      {
        "a_dict": {
          "a_bool": true,
          "another_dict" : {
            "a_double": 23.1,
            "an_int": 8,
            "a_string": "LOL wat"
          },
          "an_array": [
            "one",
            "two",
            "three"
          ],
          "a_null": null
        }
      }
      """
    let data = try XCTUnwrap(jsonString.data(using: .utf8))
    let json = try JSONSerializationFormat.deserialize(data: data)
    XCTAssertNotNil(json)
    
    let dict = try JSONObject(_jsonValue: json)
    XCTAssertNotNil(dict)
    
    let reserialized = try JSONSerializationFormat.serialize(value: dict)
    XCTAssertNotNil(reserialized)
    
    let stringFromReserialized = try XCTUnwrap(String(bytes: reserialized, encoding: .utf8))
    XCTAssertEqual(stringFromReserialized, """
      {"a_dict":{"a_bool":true,"a_null":null,"an_array":["one","two","three"],"another_dict":{"a_double":23.100000000000001,"a_string":"LOL wat","an_int":8}}}
      """)
  }

  func testEncodingNSNullDoesNotCrash() throws {
    let nsNull: JSONObject = ["aWeirdNull": NSNull()]
    let serialized = try JSONSerializationFormat.serialize(value: nsNull)
    let stringFromSerialized = try XCTUnwrap(String(data: serialized, encoding: .utf8))

    XCTAssertEqual(stringFromSerialized, #"{"aWeirdNull":null}"#)
  }

  func testEncodingOptionalNSNullDoesNotCrash() throws {
    let optionalNSNull: JSONObject = ["aWeirdNull": Optional.some(NSNull())]
    let serialized = try JSONSerializationFormat.serialize(value: optionalNSNull as JSONObject)
    let stringFromSerialized = try XCTUnwrap(String(data: serialized, encoding: .utf8))

    XCTAssertEqual(stringFromSerialized, #"{"aWeirdNull":null}"#)
  }

  func testEncodingDoubleOptionalsDoesNotCrash() throws {
    let doubleOptional: JSONObject = ["aWeirdNull": Optional.some(Optional<Int>.none)]
    let serialized = try JSONSerializationFormat.serialize(value: doubleOptional as JSONObject)
    let stringFromSerialized = try XCTUnwrap(String(data: serialized, encoding: .utf8))

    XCTAssertEqual(stringFromSerialized, #"{"aWeirdNull":null}"#)
  }
  
  func testJSONConvertSelectionSetEncoding() throws {
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata
      
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("name", String?.self)
      ]}
      
      var name: String? { __data["name"] }
    }
    
    let expected: JSONObject = [
      "__typename": "Human",
      "name": "Johnny Tsunami"
    ]
    
    let converted = try JSONConverter.convert(Hero(data: expected))
    XCTAssertEqual(converted, expected)
  }
  
  func testJSONConvertGraphQLResultEncoding() throws {
    class MockData: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("hero", Hero?.self)
      ]}

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet {
        typealias Schema = MockSchemaMetadata

        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String?.self)
        ]}

        var name: String? { __data["name"] }
      }
    }

    let jsonObj: [String: AnyHashable] = [
      "hero": [
        "name": "Luke Skywalker",
        "__typename": "Human"
      ]
    ]
    
    let heroData = try MockData(data: jsonObj)

    let result = GraphQLResult(
      data: heroData,
      extensions: nil,
      errors: nil,
      source: .server,
      dependentKeys: nil
    )
    
    let expected: [String: Any] = [
      "data": [
        "hero": [
          "name": "Luke Skywalker",
          "__typename": "Human"
        ]
      ]
    ]
    
    let converted = JSONConverter.convert(result)
    XCTAssertEqual(converted, expected)
  }
}
