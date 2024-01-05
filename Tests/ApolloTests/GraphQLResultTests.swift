import XCTest
import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import StarWarsAPI

final class GraphQLResultTests: XCTestCase {

  override func setUpWithError() throws {
    try super.setUpWithError()
  }

  override func tearDownWithError() throws {
    try super.tearDownWithError()
  }
  
  // MARK: JSON conversion tests

  func test__result__givenResponseWithData_convertsToJSON() throws {
    let jsonObj: [String: AnyHashable] = [
      "hero": [
        "name": "Luke Skywalker",
        "__typename": "Human"
      ]
    ]
    let heroData = try StarWarsAPI.HeroNameQuery.Data(data: jsonObj)
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
    
    let convertedJSON = result.asJSONDictionary()
    XCTAssertEqual(convertedJSON, expectedJSON)
  }
  
  func test__result__givenResponseWithNullData_convertsToJSON() throws {
    let jsonObj: [String: AnyHashable] = [
      "hero": NSNull()
    ]
    let heroData = try StarWarsAPI.HeroNameQuery.Data(data: jsonObj)
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
    
    let convertedJSON = result.asJSONDictionary()
    XCTAssertEqual(convertedJSON, expectedJSON)
  }
  
  func test__result__givenResponseWithErrors_convertsToJSON() throws {
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
    
    let error = GraphQLError(jsonObj)
    let result = GraphQLResult<HeroNameQuery.Data>(
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
    
    let convertedJSON = result.asJSONDictionary()
    XCTAssertEqual(convertedJSON, expectedJSON)
  }

  // MARK: Incremental merging tests

  // TODO: Need more incremental merging tests here

}
