import XCTest
@testable @_spi(Internal) import Apollo
@_spi(Internal) import ApolloAPI
import ApolloInternalTestHelpers
import StarWarsAPI

class GraphQLOperationVariableEncodingTests: XCTestCase {

  private func serializeAndDeserialize(_ input: GraphQLOperation.Variables) -> NSDictionary {
    let data = try! JSONSerializationFormat.serialize(value: input._jsonEncodableObject._jsonObject)
    return try! JSONSerialization.jsonObject(with: data, options: []) as! NSDictionary
  }
  
  func testEncodeValue() {
    let map: GraphQLOperation.Variables = ["name": "Luke Skywalker"]
    XCTAssertEqual(serializeAndDeserialize(map), ["name": "Luke Skywalker"])
  }
  
  func testEncodeGraphQLNullableValue_withValue() {
    let map: GraphQLOperation.Variables = ["name": GraphQLNullable<String>.some("Luke Skywalker")]
    XCTAssertEqual(serializeAndDeserialize(map), ["name": "Luke Skywalker"])
  }
  
  func testEncodeOptionalValueWithExplicitNil() {
    let map: GraphQLOperation.Variables = ["name": GraphQLNullable<String>.none]
    XCTAssertEqual(serializeAndDeserialize(map), [:])
  }
  
  func testEncodeOptionalValueWithExplicitNull() {
    let map: GraphQLOperation.Variables = ["name": GraphQLNullable<String>.null]
    XCTAssertEqual(serializeAndDeserialize(map), ["name": NSNull()])
  }
  
  func testEncodeEnumValue() {
    let map: GraphQLOperation.Variables = ["favoriteEpisode": Episode.jedi]
    XCTAssertEqual(serializeAndDeserialize(map), ["favoriteEpisode": "JEDI"])
  }
  
  func testEncodeMap() {
    let map: GraphQLOperation.Variables = ["hero": ["name": "Luke Skywalker"]]
    XCTAssertEqual(serializeAndDeserialize(map), ["hero": ["name": "Luke Skywalker"]])
  }
  
  func testEncodeOptionalInputObjectWithValueMissing() {
    let map: GraphQLOperation.Variables = ["hero": GraphQLNullable<GraphQLOperation.Variables>.none]
    XCTAssertEqual(serializeAndDeserialize(map), [:])
  }
  
  func testEncodeList() {
    let map: GraphQLOperation.Variables = ["appearsIn": [.jedi, .empire] as [Episode]]
    XCTAssertEqual(serializeAndDeserialize(map), ["appearsIn": ["JEDI", "EMPIRE"]])
  }
  
  func testEncodeOptionalListWithValue() {
    let map: GraphQLOperation.Variables = ["appearsIn": GraphQLNullable<[Episode]>.some([.jedi, .empire])]
    XCTAssertEqual(serializeAndDeserialize(map), ["appearsIn": ["JEDI", "EMPIRE"]])
  }
  
  func testEncodeOptionalListWithExplicitNil() {
    let map: GraphQLOperation.Variables = ["appearsIn": GraphQLNullable<[Episode]>.none]
    XCTAssertEqual(serializeAndDeserialize(map), [:])
  }
  
  func testEncodeInputObject() {
    let review = ReviewInput(stars: 5, commentary: "This is a great movie!")
    let map: GraphQLOperation.Variables = ["review": review]
    XCTAssertEqual(serializeAndDeserialize(map), ["review": ["stars": 5, "commentary": "This is a great movie!"]])
  }
  
  func testEncodeInputObjectWithOptionalPropertyMissing() {
    let review = ReviewInput(stars: 5)
    let map: GraphQLOperation.Variables = ["review": review]
    XCTAssertEqual(serializeAndDeserialize(map), ["review": ["stars": 5]])
  }
  
  func testEncodeInputObjectWithExplicitNilForOptionalProperty() {
    let review = ReviewInput(stars: 5, commentary: nil)
    let map: GraphQLOperation.Variables = ["review": review]
    XCTAssertEqual(serializeAndDeserialize(map), ["review": ["stars": 5]])
  }
  
  func testEncodeInputObjectWithExplicitNullForOptionalProperty() {
    let review = ReviewInput(stars: 5, commentary: .null)
    let map: GraphQLOperation.Variables = ["review": review]
    XCTAssertEqual(serializeAndDeserialize(map), ["review": ["stars": 5, "commentary": NSNull()]])
  }
  
  func testEncodeInputObjectWithNestedInputObject() {
    let review = ReviewInput(stars: 5, favoriteColor: .some(ColorInput(red: 0, green: 0, blue: 0)))
    let map: GraphQLOperation.Variables = ["review": review]
    XCTAssertEqual(serializeAndDeserialize(map), ["review": ["stars": 5, "favorite_color": ["red": 0, "blue": 0, "green": 0]]])
  }
}
