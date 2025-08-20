import XCTest
@testable import Apollo
@_spi(Unsafe) import ApolloAPI
import ApolloInternalTestHelpers

final class GraphQLResultTests: XCTestCase {

  // given
  private class MockHeroQuery: MockQuery<MockHeroQuery.Data>, @unchecked Sendable {
    class Data: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero?.self)
      ]}

      public var hero: Hero? { __data["hero"] }

      class Hero: AbstractMockSelectionSet<Hero.Fragments, MockSchemaMetadata>, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .deferred(DeferredFriends.self, label: "deferredFriends"),
        ]}

        var name: String { __data["name"] }

        struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredFriends = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredFriends: DeferredFriends?
        }

        class DeferredFriends: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {[
            .field("friends", [String].self)
          ]}

          var friends: [String] { __data["friends"] }
        }
      }
    }
  }

  // MARK: JSON conversion tests

  func test__result__givenResponseWithData_convertsToJSON() async throws {
    // given
    let heroData = try await MockHeroQuery.Data(data: [
      "hero": [
        "name": "Luke Skywalker",
        "__typename": "Human"
      ]
    ])

    // when
    let result = GraphQLResponse<MockHeroQuery>(
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
  
  func test__result__givenResponseWithNullData_convertsToJSON() async throws {
    // given
    let heroData = try await MockHeroQuery.Data(data: [
      "hero": NSNull()
    ])

    // when
    let result = GraphQLResponse<MockHeroQuery>(
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
    let error = GraphQLError([
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
    ])

    // when
    let result = GraphQLResponse<MockHeroQuery>(
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

  // MARK: Incremental merging tests

  func test__merging__givenIncrementalData_shouldMergeData() async throws {
    // given
    let resultData = try await MockHeroQuery.Data(data: [
      "hero": [
        "__typename": "Human",
        "name": "Luke Skywalker",
      ]
    ])

    let incrementalData = try await MockHeroQuery.Data.Hero.DeferredFriends(
      data: [
        "friends": [
          "Obi-Wan Kenobi",
          "Han Solo",
        ],
      ],
      in: MockHeroQuery.self
    )

    // when
    let result = GraphQLResponse<MockHeroQuery>(
      data: resultData,
      extensions: nil,
      errors: nil,
      source: .server,
      dependentKeys: nil
    )

    let incremental = IncrementalGraphQLResult(
      label: "deferredFriends",
      path: [.field("hero")],
      data: incrementalData,
      extensions: nil,
      errors: nil,
      dependentKeys: nil
    )

    let merged = try result.merging(incremental)

    let expected = [
      "data": [
        "hero": [
          "__typename": "Human",
          "name": "Luke Skywalker",
          "friends": [
            "Obi-Wan Kenobi",
            "Han Solo",
          ],
        ]
      ]
    ]

    // then
    XCTAssertEqual(merged.asJSONDictionary(), expected)
    XCTAssertEqual(merged.source, GraphQLResponse<MockHeroQuery>.Source.server)

    XCTAssertNil(merged.extensions)
    XCTAssertNil(merged.errors)
    XCTAssertNil(merged.dependentKeys)
  }

  func test__merging__givenIncrementalErrors_shouldMergeErrors() throws {
    // given
    let result = GraphQLResponse<MockHeroQuery>(
      data: nil,
      extensions: nil,
      errors: [GraphQLError("Base Error")],
      source: .server,
      dependentKeys: nil
    )

    let incremental = IncrementalGraphQLResult(
      label: "deferredFriends",
      path: [],
      data: nil,
      extensions: nil,
      errors: [GraphQLError("Incremental Error")],
      dependentKeys: nil
    )

    // when
    let merged = try result.merging(incremental)

    let expected = [
      GraphQLError("Base Error"),
      GraphQLError("Incremental Error"),
    ]

    // then
    XCTAssertEqual(merged.errors, expected)

    XCTAssertNil(merged.data)
    XCTAssertNil(merged.extensions)
    XCTAssertNil(merged.dependentKeys)
  }

  func test__merging__givenIncrementalExtensions_shouldMergeExtensions() throws {
    // given
    let result = GraphQLResponse<MockHeroQuery>(
      data: nil,
      extensions: ["FeatureA": true],
      errors: nil,
      source: .server,
      dependentKeys: nil
    )

    let incremental = IncrementalGraphQLResult(
      label: "deferredFriends",
      path: [],
      data: nil,
      extensions: ["FeatureZ": false],
      errors: nil,
      dependentKeys: nil
    )

    let merged = try result.merging(incremental)

    let expected = [
      "FeatureA": true,
      "FeatureZ": false,
    ]

    // then
    XCTAssertEqual(merged.extensions, expected)

    XCTAssertNil(merged.data)
    XCTAssertNil(merged.errors)
    XCTAssertNil(merged.dependentKeys)
  }

  func test__merging__givenIncrementalDependentKeys_shouldMergeDependentKeys() throws {
    // given
    let result = GraphQLResponse<MockHeroQuery>(
      data: nil,
      extensions: nil,
      errors: nil,
      source: .server,
      dependentKeys: [try CacheKey(_jsonValue: "SomeKey")]
    )

    let incremental = IncrementalGraphQLResult(
      label: "deferredFriends",
      path: [],
      data: nil,
      extensions: nil,
      errors: nil,
      dependentKeys: [try CacheKey(_jsonValue: "AnotherKey")]
    )

    let merged = try result.merging(incremental)

    let expected: Set<CacheKey> = [
      try CacheKey(_jsonValue: "SomeKey"),
      try CacheKey(_jsonValue: "AnotherKey"),
    ]

    // then
    XCTAssertEqual(merged.dependentKeys, expected)

    XCTAssertNil(merged.data)
    XCTAssertNil(merged.errors)
    XCTAssertNil(merged.extensions)
  }

}
