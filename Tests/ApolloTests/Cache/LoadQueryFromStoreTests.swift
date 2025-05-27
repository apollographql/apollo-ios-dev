import XCTest
@testable import Apollo
import ApolloAPI
#if canImport(ApolloSQLite)
import ApolloSQLite
#endif
import ApolloInternalTestHelpers

class LoadQueryFromStoreTests: XCTestCase, CacheDependentTesting, StoreLoading, MockResponseProvider {
  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  static let defaultWaitTimeout: TimeInterval = 5.0

  var cache: (any NormalizedCache)!
  var store: ApolloStore!
  
  override func setUp() async throws {
    try await super.setUp()

    cache = try await makeNormalizedCache()
    store = ApolloStore(cache: cache)
  }
  
  override func tearDown() async throws {
    cache = nil
    store = nil

    await Self.cleanUpRequestHandlers()
    try await super.tearDown()
  }
  
  func testLoadingHeroNameQuery() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }
  }
  
  func testLoadingHeroNameQueryWithVariable() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["episode": .variable("episode")])
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero(episode:JEDI)": CacheReference("hero(episode:JEDI)")],
      "hero(episode:JEDI)": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // when
    let query = MockQuery<GivenSelectionSet>()
    query.__variables = ["episode": "JEDI"]
    
    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }
  }
  
  func testLoadingHeroNameQueryWithMissingName_throwsMissingValueError() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid"]
    ])

    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      XCTAssertThrowsError(try result.get()) { error in
        if let error = error as? GraphQLExecutionError {
          XCTAssertEqual(error.path, ["hero", "name"])
          XCTAssertMatch(error.underlying, JSONDecodingError.missingValue)
        } else {
          XCTFail("Unexpected error: \(error)")
        }
      }
    }
  }
  
  func testLoadingHeroNameQueryWithNullName_throwsNullValueError() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid", "name": NSNull()]
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      XCTAssertThrowsError(try result.get()) { error in
        if let error = error as? GraphQLExecutionError {
          XCTAssertEqual(error.path, ["hero", "name"])
          XCTAssertMatch(error.underlying, JSONDecodingError.nullValue)
        } else {
          XCTFail("Unexpected error: \(error)")
        }
      }
    }
  }
  
  func testLoadingHeroAndFriendsNamesQueryWithoutIDs() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend].self)
        ]}
        var friends: [Friend] { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self)
          ]}
          var name: String { __data["name"] }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": [
          CacheReference("hero.friends.0"),
          CacheReference("hero.friends.1"),
          CacheReference("hero.friends.2")
        ]
      ],
      "hero.friends.0": ["__typename": "Human", "name": "Luke Skywalker"],
      "hero.friends.1": ["__typename": "Human", "name": "Han Solo"],
      "hero.friends.2": ["__typename": "Human", "name": "Leia Organa"],
    ])

    // when
    let query = MockQuery<GivenSelectionSet>()

    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero.name, "R2-D2")
        let friendsNames = data.hero.friends.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }
  }
  
  func testLoadingHeroAndFriendsNamesQueryWithIDs() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend].self)
        ]}
        var friends: [Friend] { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self)
          ]}
          var name: String { __data["name"] }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": [
          CacheReference("1000"),
          CacheReference("1002"),
          CacheReference("1003"),
        ]
      ],
      "1000": ["__typename": "Human", "name": "Luke Skywalker"],
      "1002": ["__typename": "Human", "name": "Han Solo"],
      "1003": ["__typename": "Human", "name": "Leia Organa"],
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()

    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero.name, "R2-D2")
        let friendsNames = data.hero.friends.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }
  }
  
  func testLoadingHeroAndFriendsNamesQuery_withOptionalFriendsSelection_withNullFriends() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend]?.self)
        ]}
        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self)
          ]}
          var name: String { __data["name"] }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": NSNull(),
      ]
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero.name, "R2-D2")
        XCTAssertNil(data.hero.friends)
      }
    }
  }

  func testLoadingHeroAndFriendsNamesQuery_withOptionalFriendsSelection_withNullFriendListItem() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend?]?.self)
        ]}
        var friends: [Friend?]? { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self)
          ]}
          var name: String { __data["name"] }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": [
          CacheReference("hero.friends.0"),
          NSNull(),
        ] as JSONValue
      ],
      "hero.friends.0": ["__typename": "Human", "name": "Luke Skywalker"],
    ])

    // when
    let query = MockQuery<GivenSelectionSet>()

    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero.name, "R2-D2")

        XCTAssertEqual(data.hero.friends?.count, 2)
        XCTAssertEqual(data.hero.friends![0]!.name, "Luke Skywalker")
        XCTAssertNil(data.hero.friends![1]) // Null friend at position 2
      }
    }
  }
  
  func testLoadingHeroAndFriendsNamesQuery_withOptionalFriendsSelection_withFriendsNotInCache_throwsMissingValueError() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend]?.self)
        ]}
        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self)
          ]}
          var name: String { __data["name"] }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid", "name": "R2-D2"]
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      XCTAssertThrowsError(try result.get()) { error in
        if let error = error as? GraphQLExecutionError {
          XCTAssertEqual(error.path, ["hero", "friends"])
          XCTAssertMatch(error.underlying, JSONDecodingError.missingValue)
        } else {
          XCTFail("Unexpected error: \(error)")
        }
      }
    }
  }
  
  func testLoadingWithBadCacheSerialization() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend]?.self)
        ]}
        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self)
          ]}
          var name: String { __data["name"] }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": [
          CacheReference("1000"),
          CacheReference("1002"),
          CacheReference("1003")
        ]
      ],
      "1000": ["__typename": "Human", "name": ["dictionary": "badValues", "nested bad val": ["subdictionary": "some value"] ] as JSONValue
      ],
      "1002": ["__typename": "Human", "name": "Han Solo"],
      "1003": ["__typename": "Human", "name": "Leia Organa"],
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      XCTAssertThrowsError(try result.get()) { error in
        // then
        if let error = error as? GraphQLExecutionError,
           case JSONDecodingError.couldNotConvert(_, let expectedType) = error.underlying {
          XCTAssertEqual(error.path, ["hero", "friends", "0", "name"])
          XCTAssertTrue(expectedType == String.self)
        } else {
          XCTFail("Unexpected error: \(error)")
        }
      }
    }
  }
  
  func testLoadingQueryWithFloats() async throws {
    // given
    let starshipLength: Float = 1234.5
    let coordinates: [[Double]] = [[38.857150, -94.798464]]

    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("starshipCoordinates", Starship.self)
      ]}

      class Starship: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("length", Float.self),
          .field("coordinates", [[Double]].self)
        ]}
      }
    }
    
    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["starshipCoordinates": CacheReference("starshipCoordinates")],
      "starshipCoordinates": ["__typename": "Starship",
                              "name": "Millennium Falcon",
                              "length": starshipLength,
                              "coordinates": coordinates]
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        let coordinateData: GivenSelectionSet.Starship? = data.starshipCoordinates
        XCTAssertEqual(coordinateData?.name, "Millennium Falcon")
        XCTAssertEqual(coordinateData?.length, starshipLength)
        XCTAssertEqual(coordinateData?.coordinates, coordinates)
      }
    }
  }

  @MainActor func testLoadingHeroAndFriendsNamesQuery_withOptionalFriendsSelection_withNullFriendListItem_usingRequestChain() async throws {
    // given
    struct Types {
      static let Hero = Object(typename: "Hero", implementedInterfaces: [])
      static let Friend = Object(typename: "Friend", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Hero":
        return Types.Hero
      case "Friend":
        return Types.Friend
      default:
        XCTFail()
        return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("name", String.self),
        .field("friends", [Friend?]?.self)
      ]}

      public var name: String? { __data["name"] }
      public var friends: [Friend?]? { __data["friends"] }

      convenience init(
        name: String? = nil,
        friends: [Friend?]? = nil
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": Types.Hero.typename,
            "name": name,
            "friends": friends
          ],
          fulfilledFragments: [ObjectIdentifier(Self.self)]
        ))
      }

      class Friend: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
        var name: String { __data["name"] }
      }
    }

    // given
    await Self.registerRequestHandler(for: TestURL.mockServer.url) { _ in
      return (
        .mock(
          url: TestURL.mockServer.url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        ),
      """
      {
        "data": {
          "__typename": "Hero",
          "name": "R2-D2",
          "friends": [
            {
              "__typename": "Friend",
              "name": "Luke Skywalker"
            },
            null,
            {
              "__typename": "Friend",
              "name": "Obi-Wan Kenobi"
            }
          ]
        }
      }
      """.data(using: .utf8)
      )
    }

    let urlSession: MockURLSession = MockURLSession(responseProvider: Self.self)

    let requestChain = RequestChain<JSONRequest<MockQuery<Hero>>>(
      urlSession: urlSession,
      interceptors: [
        JSONResponseParsingInterceptor(),
      ],
      cacheInterceptor: DefaultCacheInterceptor(store: self.store),
      errorInterceptor: nil
    )

    let request = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url
    )    

    // when
    let resultStream = requestChain.kickoff(request: request)

    _ = try await resultStream.getAllValues()

    loadFromStore(operation: MockQuery<Hero>()) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.name, "R2-D2")

        XCTAssertEqual(data.friends?.count, 3)
        XCTAssertEqual(data.friends![0]!.name, "Luke Skywalker")
        XCTAssertNil(data.friends![1]) // Null friend at position 2
        XCTAssertEqual(data.friends![2]!.name, "Obi-Wan Kenobi")
      }
    }
  }
}
