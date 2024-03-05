import XCTest
import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

final class GraphQLResultTests: XCTestCase {

  // given
  class Data: MockSelectionSet {
    override class var __selections: [Selection] { [
      .field("hero", Hero?.self)
    ]}

    public var hero: Hero? { __data["hero"] }

    class Hero: MockSelectionSet {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("name", String.self)
      ]}

      var name: String { __data["name"] }
    }
  }

  // MARK: JSON conversion tests

  func test__result__givenResponseWithData_convertsToJSON() throws {
    // given
    let jsonObj: [String: AnyHashable] = [
      "hero": [
        "name": "Luke Skywalker",
        "__typename": "Human"
      ]
    ]

    // when
    let heroData = try Data(data: jsonObj)
    let result = GraphQLResult(
      data: heroData,
      extensions: nil,
      errors: nil,
      source: .server,
      dependentKeys: nil
    )

    let expectedJSON: [String: Any] = [
      "data": [
        "hero": [
          "name": "Luke Skywalker",
          "__typename": "Human"
        ]
      ]
    ]

    // then
    let convertedJSON = result.asJSONDictionary()
    XCTAssertEqual(convertedJSON, expectedJSON)
  }
  
  func test__result__givenResponseWithNullData_convertsToJSON() throws {
    // given
    let jsonObj: [String: AnyHashable] = [
      "hero": NSNull()
    ]

    // when
    let heroData = try Data(data: jsonObj)
    let result = GraphQLResult(
      data: heroData,
      extensions: nil,
      errors: nil,
      source: .server,
      dependentKeys: nil
    )

    let expectedJSON: [String: Any] = [
      "data": [
        "hero": NSNull()
      ]
    ]

    // then
    let convertedJSON = result.asJSONDictionary()
    XCTAssertEqual(convertedJSON, expectedJSON)
  }
  
  func test__result__givenResponseWithErrors_convertsToJSON() throws {
    // given
    let jsonObj: [String: AnyHashable] = [
      "message": "Sample error message",
      "locations": [
        "line": 1,
        "column": 1
      ],
      "path": [
        "TestPath"
      ],
      "extensions": [
        "test": "extension"
      ]
    ]

    // when
    let error = GraphQLError(jsonObj)
    let result = GraphQLResult<Data>(
      data: nil,
      extensions: nil,
      errors: [error],
      source: .server,
      dependentKeys: nil
    )

    let expectedJSON: [String: Any] = [
      "errors": [
        [
          "message": "Sample error message",
          "locations": [
            "line": 1,
            "column": 1
          ],
          "path": [
            "TestPath"
          ],
          "extensions": [
            "test": "extension"
          ]
        ]
      ]
    ]

    // then
    let convertedJSON = result.asJSONDictionary()
    XCTAssertEqual(convertedJSON, expectedJSON)
  }

}
