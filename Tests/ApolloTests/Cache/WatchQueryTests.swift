@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

class WatchQueryTests: XCTestCase, CacheDependentTesting, @unchecked Sendable {

  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  static let defaultWaitTimeout: TimeInterval = 1

  var store: ApolloStore!
  var server: MockGraphQLServer!
  var client: ApolloClient!

  override func setUp() async throws {
    try await super.setUp()

    store = try await makeTestStore()

    server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(mockServer: server, store: store)

    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  override func tearDownWithError() throws {
    store = nil
    server = nil
    client = nil

    try super.tearDownWithError()
  }

  // MARK: - Tests

  func testRefetchWatchedQueryFromServerThroughWatcherReturnsRefetchedResults() async throws {
    class SimpleMockSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    let watchedQuery = MockQuery<SimpleMockSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(client: client, query: watchedQuery, resultHandler: resultObserver.handler)
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation =
    await server.expect(MockQuery<SimpleMockSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "R2-D2",
              "__typename": "Droid",
            ]
          ]
        ]
      }

    let initialWatcherResultExpectation =
    await resultObserver.expectation(
        description: "Watcher received initial result from server"
      ) { result in
        try XCTAssertSuccessResult(result) { graphQLResult in
          XCTAssertEqual(graphQLResult.source, .server)
          XCTAssertNil(graphQLResult.errors)

          let data = try XCTUnwrap(graphQLResult.data)
          XCTAssertEqual(data.hero?.name, "R2-D2")
        }
      }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Refetch from server
    let refetchServerRequestExpectation =
    await server.expect(MockQuery<SimpleMockSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "Artoo",
              "__typename": "Droid",
            ]
          ]
        ]
      }

    let refetchedWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received refetched result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "Artoo")
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [refetchServerRequestExpectation, refetchedWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )
  }

  func testWatchedQueryGetsUpdatedAfterFetchingSameQueryWithChangedData() async throws {
    class SimpleMockSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    let watchedQuery = MockQuery<SimpleMockSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(client: client, query: watchedQuery, resultHandler: resultObserver.handler)
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation =
    await server.expect(MockQuery<SimpleMockSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "R2-D2",
              "__typename": "Droid",
            ]
          ]
        ]
      }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Fetch same query from server returning changed data
    let refetchServerRequestExpectation =
    await server.expect(MockQuery<SimpleMockSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "Artoo",
              "__typename": "Droid",
            ]
          ]
        ]
      }

    let updatedWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received updated result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "Artoo")
      }
    }

    _ = try await client.fetch(query: MockQuery<SimpleMockSelectionSet>(), cachePolicy: .networkOnly)

    await fulfillment(
      of: [refetchServerRequestExpectation, updatedWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )
  }

  func testWatchedQueryDoesNotRefetchAfterSameQueryWithDifferentArgument() async throws {
    class GivenMockSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self, arguments: ["episode": .variable("episode")])
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    let watchedQuery = MockQuery<GivenMockSelectionSet>()
    watchedQuery.__variables = ["episode": "EMPIRE"]

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(client: client, query: watchedQuery, resultHandler: resultObserver.handler)
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation =
    await server.expect(MockQuery<GivenMockSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "R2-D2",
              "__typename": "Droid",
            ]
          ]
        ]
      }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Fetch same query from server with different argument
    let secondServerRequestExpectation =
    await server.expect(MockQuery<GivenMockSelectionSet>.self) { request in
        expect(request.operation.__variables?["episode"] as? String).to(equal("JEDI"))

        return [
          "data": [
            "hero": [
              "name": "Artoo",
              "__typename": "Droid",
            ]
          ]
        ]
      }

    let noUpdatedResultExpectation = await resultObserver.expectation(
      description: "Other query shouldn't trigger refetch"
    ) { _ in }
    noUpdatedResultExpectation.isInverted = true

    let newQuery = MockQuery<GivenMockSelectionSet>()
    newQuery.__variables = ["episode": "JEDI"]

    _ = try await client.fetch(query: newQuery, cachePolicy: .networkOnly)

    await fulfillment(
      of: [secondServerRequestExpectation, noUpdatedResultExpectation],
      timeout: Self.defaultWaitTimeout
    )
  }

  func testWatchedQueryGetsUpdatedWhenSameObjectHasChangedInAnotherQueryWithDifferentVariables() async throws {
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self, arguments: ["episode": .variable("episode")])
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    await MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let watchedQuery = MockQuery<GivenSelectionSet>()
    watchedQuery.__variables = ["episode": "EMPIRE"]

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(
      client: client,
      query: watchedQuery,
      resultHandler: resultObserver.handler
    )
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation = await server.expect(MockQuery<GivenSelectionSet>.self) { @Sendable request in
      expect(request.operation.__variables?["episode"] as? String).to(equal("EMPIRE"))
      return [
        "data": [
          "hero": [
            "id": "2001",
            "name": "R2-D2",
            "__typename": "Droid",
          ]
        ]
      ]
    }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result"
    ) {
      result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.id, "2001")
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Fetch same query from server with different argument but returning same object with changed data
    let secondServerRequestExpectation = await server.expect(MockQuery<GivenSelectionSet>.self) { @Sendable request in
      expect(request.operation.__variables?["episode"] as? String).to(equal("JEDI"))
      return [
        "data": [
          "hero": [
            "id": "2001",
            "name": "Artoo",
            "__typename": "Droid",
          ]
        ]
      ]
    }

    let updatedWatcherResultExpectation = await resultObserver.expectation(
      description: "Updated result after refetching query"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "Artoo")
      }
    }

    let query = MockQuery<GivenSelectionSet>()
    query.__variables = ["episode": "JEDI"]

    _ = try await client.fetch(query: query, cachePolicy: .networkOnly)

    await fulfillment(
      of: [secondServerRequestExpectation, updatedWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )
  }

  func testWatchedQueryGetsUpdatedWhenOverlappingQueryReturnsChangedData() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    class HeroAndFriendsNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero?.self)
        ]
      }

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("name", String.self),
            ]
          }

          var name: String { __data["name"] }
        }
      }
    }

    let watchedQuery = MockQuery<HeroAndFriendsNameSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(
      client: client,
      query: watchedQuery,
      resultHandler: resultObserver.handler
    )
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation =
    await server.expect(MockQuery<HeroAndFriendsNameSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "R2-D2",
              "__typename": "Droid",
              "friends": [
                ["__typename": "Human", "name": "Luke Skywalker"],
                ["__typename": "Human", "name": "Han Solo"],
                ["__typename": "Human", "name": "Leia Organa"],
              ],
            ]
          ] as JSONValue
        ]
      }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
        let friendsNames = data.hero?.friends?.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Fetch overlapping query from server
    let secondServerRequestExpectation =
    await server.expect(MockQuery<HeroNameSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "Artoo",
              "__typename": "Droid",
            ]
          ]
        ]
      }

    let updatedWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received updated result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "Artoo")
        let friendsNames = data.hero?.friends?.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }

    _ = try await client.fetch(query: MockQuery<HeroNameSelectionSet>(), cachePolicy: .networkOnly)

    await fulfillment(
      of: [secondServerRequestExpectation, updatedWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )
  }

  @MainActor
  func testListInWatchedQueryGetsUpdatedByListOfKeysFromOtherQuery() async throws {
    class HeroAndFriendsIdsSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero?.self)
        ]
      }

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
            ]
          }
        }
      }
    }

    class HeroAndFriendsNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero?.self)
        ]
      }

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
              .field("name", String.self),
            ]
          }

          var name: String { __data["name"] }
        }
      }
    }

    MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let watchedQuery = MockQuery<HeroAndFriendsNameSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(
      client: client,
      query: watchedQuery,
      resultHandler: resultObserver.handler
    )
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation = await server.expect(MockQuery<HeroAndFriendsNameSelectionSet>.self) { @Sendable request in
      [
        "data": [
          "hero": [
            "id": "2001",
            "name": "R2-D2",
            "__typename": "Droid",
            "friends": [
              ["__typename": "Human", "id": "1000", "name": "Luke Skywalker"],
              ["__typename": "Human", "id": "1002", "name": "Han Solo"],
              ["__typename": "Human", "id": "1003", "name": "Leia Organa"],
            ],
          ]
        ] as JSONValue
      ]
    }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
        let friendsNames = data.hero?.friends?.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Fetch other query with list of updated keys from server
    let secondServerRequestExpectation =
    await server.expect(MockQuery<HeroAndFriendsIdsSelectionSet>.self) { @Sendable request in
        [
          "data": [
            "hero": [
              "id": "2001",
              "name": "Artoo",
              "__typename": "Droid",
              "friends": [
                ["__typename": "Human", "id": "1003"],
                ["__typename": "Human", "id": "1000"],
              ],
            ]
          ] as JSONValue
        ]
      }

    let updatedWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received updated result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "Artoo")
        let friendsNames = data.hero?.friends?.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Leia Organa", "Luke Skywalker"])
      }
    }

    _ = try await client.fetch(query: MockQuery<HeroAndFriendsIdsSelectionSet>(), cachePolicy: .networkOnly)

    await fulfillment(
      of: [secondServerRequestExpectation, updatedWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )
  }

  @MainActor
  func testWatchedQueryRefetchesFromServerAfterOtherQueryUpdatesListWithIncompleteObject() async throws {
    class HeroAndFriendsIDsSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero?.self)
        ]
      }

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
            ]
          }
        }
      }
    }

    class HeroAndFriendsNameWithIDsSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero?.self)
        ]
      }

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
              .field("name", String.self),
            ]
          }

          var name: String { __data["name"] }
        }
      }
    }

    MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let watchedQuery = MockQuery<HeroAndFriendsNameWithIDsSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(
      client: client,
      query: watchedQuery,
      resultHandler: resultObserver.handler
    )
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation =
    await server.expect(MockQuery<HeroAndFriendsNameWithIDsSelectionSet>.self) { @Sendable request in
        [
          "data": [
            "hero": [
              "id": "2001",
              "name": "R2-D2",
              "__typename": "Droid",
              "friends": [
                ["__typename": "Human", "id": "1000", "name": "Luke Skywalker"],
                ["__typename": "Human", "id": "1002", "name": "Han Solo"],
                ["__typename": "Human", "id": "1003", "name": "Leia Organa"],
              ],
            ]
          ] as JSONValue
        ]
      }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
        let friendsNames = data.hero?.friends?.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Fetch other query with list of updated keys from server
    let secondServerRequestExpectation =
    await server.expect(MockQuery<HeroAndFriendsIDsSelectionSet>.self) { @Sendable request in
        [
          "data": [
            "hero": [
              "id": "2001",
              "name": "Artoo",
              "__typename": "Droid",
              "friends": [
                ["__typename": "Human", "id": "1003"],
                ["__typename": "Human", "id": "1004"],
                ["__typename": "Human", "id": "1000"],
              ],
            ]
          ] as JSONValue
        ]
      }

    let refetchServerRequestExpectation =
    await server.expect(MockQuery<HeroAndFriendsNameWithIDsSelectionSet>.self) { @Sendable request in
        [
          "data": [
            "hero": [
              "id": "2001",
              "name": "Artoo",
              "__typename": "Droid",
              "friends": [
                ["__typename": "Human", "id": "1003", "name": "Leia Organa"],
                ["__typename": "Human", "id": "1004", "name": "Wilhuff Tarkin"],
                ["__typename": "Human", "id": "1000", "name": "Luke Skywalker"],
              ],
            ]
          ] as JSONValue
        ]
      }

    let updatedWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received updated result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "Artoo")
        let friendsNames = data.hero?.friends?.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Leia Organa", "Wilhuff Tarkin", "Luke Skywalker"])
      }
    }

    _ = try await client.fetch(query: MockQuery<HeroAndFriendsIDsSelectionSet>(), cachePolicy: .networkOnly)

    await fulfillment(
      of: [
        secondServerRequestExpectation,
        refetchServerRequestExpectation,
        updatedWatcherResultExpectation,
      ],
      timeout: Self.defaultWaitTimeout
    )
  }

  @MainActor
  func
    testWatchedQuery_givenRefetchOnFailedUpdates_false_doesNotRefetchFromServerAfterOtherQueryUpdatesListWithIncompleteObject()
    async throws
  {
    class HeroAndFriendsIDsSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero?.self)
        ]
      }

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
            ]
          }
        }
      }
    }

    class HeroAndFriendsNameWithIDsSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero?.self)
        ]
      }

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
              .field("name", String.self),
            ]
          }

          var name: String { __data["name"] }
        }
      }
    }

    MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let watchedQuery = MockQuery<HeroAndFriendsNameWithIDsSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(
      client: client,
      query: watchedQuery,
      refetchOnFailedUpdates: false,
      resultHandler: resultObserver.handler
    )

    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation =
    await server.expect(MockQuery<HeroAndFriendsNameWithIDsSelectionSet>.self) { @Sendable request in
        [
          "data": [
            "hero": [
              "id": "2001",
              "name": "R2-D2",
              "__typename": "Droid",
              "friends": [
                ["__typename": "Human", "id": "1000", "name": "Luke Skywalker"],
                ["__typename": "Human", "id": "1002", "name": "Han Solo"],
                ["__typename": "Human", "id": "1003", "name": "Leia Organa"],
              ],
            ]
          ] as JSONValue
        ]
      }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
        let friendsNames = data.hero?.friends?.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Fetch other query with list of updated keys from server
    let secondServerRequestExpectation =
    await server.expect(MockQuery<HeroAndFriendsIDsSelectionSet>.self) { @Sendable request in
        [
          "data": [
            "hero": [
              "id": "2001",
              "name": "Artoo",
              "__typename": "Droid",
              "friends": [
                ["__typename": "Human", "id": "1003"],
                ["__typename": "Human", "id": "1004"],
                ["__typename": "Human", "id": "1000"],
              ],
            ]
          ] as JSONValue
        ]
      }

    let updatedWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received updated result from cache"
    ) { _ in }
    updatedWatcherResultExpectation.isInverted = true

    _ = try await client.fetch(query: MockQuery<HeroAndFriendsIDsSelectionSet>(), cachePolicy: .networkOnly)

    await fulfillment(
      of: [secondServerRequestExpectation, updatedWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )
  }

  func testWatchedQueryGetsUpdatedWhenObjectIsChangedByDirectStoreUpdate() async throws {
    struct HeroAndFriendsNamesSelectionSet: MockMutableRootSelectionSet {
      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] {
        [
          .field("hero", Hero?.self)
        ]
      }

      var hero: Hero? {
        get { __data["hero"] }
        set { __data["hero"] = newValue }
      }

      struct Hero: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        var friends: [Friend]? {
          get { __data["friends"] }
          set { __data["friends"] = newValue }
        }

        struct Friend: MockMutableRootSelectionSet {
          public var __data: DataDict = .empty()
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("name", String.self),
            ]
          }

          var name: String {
            get { __data["name"] }
            set { __data["name"] = newValue }
          }
        }
      }
    }

    let watchedQuery = MockQuery<HeroAndFriendsNamesSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(
      client: client,
      query: watchedQuery,
      resultHandler: resultObserver.handler
    )
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation =
    await server.expect(MockQuery<HeroAndFriendsNamesSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "R2-D2",
              "__typename": "Droid",
              "friends": [
                ["__typename": "Human", "name": "Luke Skywalker"],
                ["__typename": "Human", "name": "Han Solo"],
                ["__typename": "Human", "name": "Leia Organa"],
              ],
            ]
          ] as JSONValue
        ]
      }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
        let friendsNames: [String] = try XCTUnwrap(
          data.hero?.friends?.compactMap { $0.name }
        )
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Update object directly in store
    let updatedWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received updated result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "Artoo")

        let friendsNames = data.hero?.friends?.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }

    try await client.store.withinReadWriteTransaction({ transaction in
      let cacheMutation = MockLocalCacheMutation<HeroAndFriendsNamesSelectionSet>()
      try await transaction.update(cacheMutation) { data in
        data.hero?.name = "Artoo"
      }
    })

    await fulfillment(of: [updatedWatcherResultExpectation], timeout: Self.defaultWaitTimeout)
  }

  @MainActor
  func
    testWatchedQuery_givenFetchBehavior_CacheOnly_doesNotRefetchFromServerAfterOtherQueryUpdatesListWithIncompleteObject()
    async throws
  {
    // given
    struct HeroAndFriendsNamesSelectionSet: MockMutableRootSelectionSet {
      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      var hero: Hero {
        get { __data["hero"] }
        set { __data["hero"] = newValue }
      }

      struct Hero: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
            .field("friends", [Friend].self),
          ]
        }

        var id: String {
          get { __data["id"] }
          set { __data["id"] = newValue }
        }

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        var friends: [Friend] {
          get { __data["friends"] }
          set { __data["friends"] = newValue }
        }

        struct Friend: MockMutableRootSelectionSet {
          public var __data: DataDict = .empty()
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
              .field("name", String.self),
            ]
          }

          var id: String {
            get { __data["id"] }
            set { __data["id"] = newValue }
          }

          var name: String {
            get { __data["name"] }
            set { __data["name"] = newValue }
          }
        }
      }
    }

    struct HeroAndFriendsIDsOnlySelectionSet: MockMutableRootSelectionSet {
      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      var hero: Hero {
        get { __data["hero"] }
        set { __data["hero"] = newValue }
      }

      struct Hero: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("friends", [Friend].self),
          ]
        }

        var id: String {
          get { __data["id"] }
          set { __data["id"] = newValue }
        }

        var friends: [Friend] {
          get { __data["friends"] }
          set { __data["friends"] = newValue }
        }

        struct Friend: MockMutableRootSelectionSet {
          public var __data: DataDict = .empty()
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
            ]
          }

          var id: String {
            get { __data["id"] }
            set { __data["id"] = newValue }
          }
        }
      }
    }

    MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let watchedQuery = MockQuery<HeroAndFriendsNamesSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(client: client, query: watchedQuery, resultHandler: resultObserver.handler)
    addTeardownBlock { watcher.cancel() }

    // Write data to cache
    try await client.store.withinReadWriteTransaction({ transaction in
      let data = try! await HeroAndFriendsNamesSelectionSet(
        data: [
          "hero": [
            "id": "2001",
            "name": "R2-D2",
            "__typename": "Droid",
            "friends": [
              ["__typename": "Human", "id": "1000", "name": "Luke Skywalker"],
              ["__typename": "Human", "id": "1002", "name": "Han Solo"],
              ["__typename": "Human", "id": "1003", "name": "Leia Organa"],
            ],
          ]
        ],
        variables: nil
      )

      let cacheMutation = MockLocalCacheMutation<HeroAndFriendsNamesSelectionSet>()
      try await transaction.write(data: data, for: cacheMutation)
    })

    // Initial fetch from cache
    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero.name, "R2-D2")
        let friendsNames = data.hero.friends.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }

    await watcher.fetch(fetchBehavior: .CacheOnly)

    await fulfillment(of: [initialWatcherResultExpectation], timeout: Self.defaultWaitTimeout)

    // Fetch other query with list of updated keys from server
    let secondServerRequestExpectation = await server.expect(
      MockQuery<HeroAndFriendsIDsOnlySelectionSet>.self
    ) { @Sendable request in
      [
        "data": [
          "hero": [
            "id": "2001",
            "name": "Artoo",
            "__typename": "Droid",
            "friends": [
              ["__typename": "Human", "id": "1003"],
              ["__typename": "Human", "id": "1004"],
              ["__typename": "Human", "id": "1000"],
            ],
          ]
        ] as JSONValue
      ]
    }

    let noRefetchExpectation = await resultObserver.expectation(
      description: "Initial query shouldn't trigger refetch"
    ) { _ in
    }
    noRefetchExpectation.isInverted = true

    let query = MockQuery<HeroAndFriendsIDsOnlySelectionSet>()
    _ = try await client.fetch(query: query, cachePolicy: .networkOnly)

    await fulfillment(
      of: [secondServerRequestExpectation, noRefetchExpectation],
      timeout: Self.defaultWaitTimeout
    )
  }

  func testWatchedQueryIsOnlyUpdatedOnceIfConcurrentFetchesAllReturnTheSameResult() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    let watchedQuery = MockQuery<HeroNameSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(client: client, query: watchedQuery, resultHandler: resultObserver.handler)
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation =
    await server.expect(MockQuery<HeroNameSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "R2-D2",
              "__typename": "Droid",
            ]
          ]
        ]
      }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Fetch same query concurrently 10 times
    let numberOfFetches = 10
    let secondServerRequestExpectation =
    await server.expect(MockQuery<HeroNameSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "Artoo",
              "__typename": "Droid",
            ]
          ]
        ]
      }

    secondServerRequestExpectation.expectedFulfillmentCount = numberOfFetches

    let updatedWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received updated result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "Artoo")
      }
    }

    let otherFetchesCompletedExpectation = expectation(description: "Other fetches completed")
    otherFetchesCompletedExpectation.expectedFulfillmentCount = numberOfFetches

    try await withThrowingTaskGroup { group in
      for _ in 0..<numberOfFetches {
        group.addTask {
          _ = try await self.client.fetch(query: MockQuery<HeroNameSelectionSet>(), cachePolicy: .networkOnly)
          otherFetchesCompletedExpectation.fulfill()
        }
      }

      try await group.waitForAll()
    }

    await fulfillment(
      of: [secondServerRequestExpectation, otherFetchesCompletedExpectation, updatedWatcherResultExpectation],
      timeout: 3
    )

    XCTAssertEqual(updatedWatcherResultExpectation.numberOfFulfillments, 1)
  }

  func testWatchedQueryIsUpdatedMultipleTimesIfConcurrentFetchesReturnChangedData() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }

        var name: String { __data["name"] }
      }
    }

    let watchedQuery = MockQuery<HeroNameSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(
      client: client,
      query: watchedQuery,
      resultHandler: resultObserver.handler
    )
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation =
    await server.expect(MockQuery<HeroNameSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "R2-D2",
              "__typename": "Droid",
            ]
          ]
        ]
      }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero.name, "R2-D2")
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Fetch same query concurrently 10 times
    let numberOfFetches = 10
    let secondServerRequestExpectation =
    await server.expect(MockQuery<HeroNameSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "Artoo #\(UUID())",
              "__typename": "Droid",
            ]
          ]
        ]
      }

    secondServerRequestExpectation.expectedFulfillmentCount = numberOfFetches

    let updatedWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received updated result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertTrue(try XCTUnwrap(data.hero.name).hasPrefix("Artoo"))
      }
    }

    updatedWatcherResultExpectation.expectedFulfillmentCount = numberOfFetches

    let otherFetchesCompletedExpectation = expectation(description: "Other fetches completed")
    otherFetchesCompletedExpectation.expectedFulfillmentCount = numberOfFetches

    try await withThrowingTaskGroup { group in
      for _ in 0..<numberOfFetches {
        group.addTask {
          _ = try await self.client.fetch(query: MockQuery<HeroNameSelectionSet>(), cachePolicy: .networkOnly)
          otherFetchesCompletedExpectation.fulfill()
        }
      }

      try await group.waitForAll()
    }

    await fulfillment(
      of: [secondServerRequestExpectation, otherFetchesCompletedExpectation, updatedWatcherResultExpectation],
      timeout: 3
    )

    XCTAssertEqual(updatedWatcherResultExpectation.numberOfFulfillments, numberOfFetches)
  }

  @MainActor
  func testWatchedQueryDependentKeysAreUpdatedAfterDirectStoreUpdate() async throws {
    // given
    struct HeroAndFriendsNamesWithIDsSelectionSet: MockMutableRootSelectionSet {
      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      var hero: Hero {
        get { __data["hero"] }
        set { __data["hero"] = newValue }
      }

      struct Hero: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
            .field("friends", [Friend].self),
          ]
        }

        var id: String {
          get { __data["id"] }
          set { __data["id"] = newValue }
        }

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        var friends: [Friend] {
          get { __data["friends"] }
          set { __data["friends"] = newValue }
        }

        struct Friend: MockMutableRootSelectionSet {
          public var __data: DataDict = .empty()
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
              .field("name", String.self),
            ]
          }

          var id: String {
            get { __data["id"] }
            set { __data["id"] = newValue }
          }

          var name: String {
            get { __data["name"] }
            set { __data["name"] = newValue }
          }
        }
      }
    }

    MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    typealias HeroAndFriendsNamesWithIDsQuery = MockQuery<HeroAndFriendsNamesWithIDsSelectionSet>
    let watchedQuery = HeroAndFriendsNamesWithIDsQuery()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(client: client, query: watchedQuery, resultHandler: resultObserver.handler)
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation = await server.expect(HeroAndFriendsNamesWithIDsQuery.self) { @Sendable request in
      [
        "data": [
          "hero": [
            "id": "2001",
            "name": "R2-D2",
            "__typename": "Droid",
            "friends": [
              ["__typename": "Human", "id": "1000", "name": "Luke Skywalker"]
            ],
          ]
        ] as JSONValue
      ]
    }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)

        XCTAssertEqual(data.hero.name, "R2-D2")

        let friendsNames = data.hero.friends.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker"])

        let expectedDependentKeys: Set = [
          "Droid:2001.__typename",
          "Droid:2001.friends",
          "Droid:2001.id",
          "Droid:2001.name",
          "Human:1000.__typename",
          "Human:1000.id",
          "Human:1000.name",
          "QUERY_ROOT.hero",
        ]
        let actualDependentKeys = try XCTUnwrap(graphQLResult.dependentKeys)
        expect(actualDependentKeys).to(equal(expectedDependentKeys))
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Update same query directly in store
    let updatedWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received updated result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)

        XCTAssertEqual(data.hero.name, "R2-D2")

        let friendsNames = data.hero.friends.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo"])

        let expectedDependentKeys: Set = [
          "Droid:2001.__typename",
          "Droid:2001.friends",
          "Droid:2001.id",
          "Droid:2001.name",
          "Human:1000.__typename",
          "Human:1000.id",
          "Human:1000.name",
          "Human:1002.__typename",
          "Human:1002.id",
          "Human:1002.name",
          "QUERY_ROOT.hero",
        ]
        let actualDependentKeys = try XCTUnwrap(graphQLResult.dependentKeys)
        expect(actualDependentKeys).to(equal(expectedDependentKeys))
      }
    }

    let cacheMutation = MockLocalCacheMutation<HeroAndFriendsNamesWithIDsSelectionSet>()
    try await client.store.withinReadWriteTransaction({ transaction in
      try await transaction.update(cacheMutation) { data in
        var human = HeroAndFriendsNamesWithIDsSelectionSet.Hero.Friend()
        human.__typename = "Human"
        human.id = "1002"
        human.name = "Han Solo"
        data.hero.friends.append(human)
      }
    })

    await fulfillment(of: [updatedWatcherResultExpectation], timeout: Self.defaultWaitTimeout)
  }

  @MainActor
  func testWatchedQueryDependentKeysAreUpdatedAfterOtherFetchReturnsChangedData() async throws {
    class HeroAndFriendsNameWithIDsSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero?.self)
        ]
      }

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
              .field("name", String.self),
            ]
          }

          var name: String { __data["name"] }
        }
      }
    }

    MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let watchedQuery = MockQuery<HeroAndFriendsNameWithIDsSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    let watcher = await GraphQLQueryWatcher(client: client, query: watchedQuery, resultHandler: resultObserver.handler)
    addTeardownBlock { watcher.cancel() }

    // Initial fetch from server
    let serverRequestExpectation =
    await server.expect(MockQuery<HeroAndFriendsNameWithIDsSelectionSet>.self) { @Sendable request in
        [
          "data": [
            "hero": [
              "id": "2001",
              "name": "R2-D2",
              "__typename": "Droid",
              "friends": [
                ["__typename": "Human", "id": "1000", "name": "Luke Skywalker"]
              ],
            ]
          ] as JSONValue
        ]
      }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)

        XCTAssertEqual(data.hero?.name, "R2-D2")

        let friendsNames = data.hero?.friends?.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker"])

        let expectedDependentKeys: Set = [
          "Droid:2001.__typename",
          "Droid:2001.friends",
          "Droid:2001.id",
          "Droid:2001.name",
          "Human:1000.__typename",
          "Human:1000.id",
          "Human:1000.name",
          "QUERY_ROOT.hero",
        ]
        let actualDependentKeys = try XCTUnwrap(graphQLResult.dependentKeys)
        XCTAssertEqual(actualDependentKeys, expectedDependentKeys)
      }
    }

    await watcher.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Fetch other query from server
    let secondServerRequestExpectation =
    await server.expect(MockQuery<HeroAndFriendsNameWithIDsSelectionSet>.self) { @Sendable request in
        [
          "data": [
            "hero": [
              "id": "2001",
              "name": "R2-D2",
              "__typename": "Droid",
              "friends": [
                ["__typename": "Human", "id": "1000", "name": "Luke Skywalker"],
                ["__typename": "Human", "id": "1002", "name": "Han Solo"],
              ],
            ]
          ] as JSONValue
        ]
      }

    let updatedWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received updated result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)

        XCTAssertEqual(data.hero?.name, "R2-D2")

        let friendsNames = data.hero?.friends?.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo"])

        let expectedDependentKeys: Set = [
          "Droid:2001.__typename",
          "Droid:2001.friends",
          "Droid:2001.id",
          "Droid:2001.name",
          "Human:1000.__typename",
          "Human:1000.id",
          "Human:1000.name",
          "Human:1002.__typename",
          "Human:1002.id",
          "Human:1002.name",
          "QUERY_ROOT.hero",
        ]
        let actualDependentKeys = try XCTUnwrap(graphQLResult.dependentKeys)
        XCTAssertEqual(actualDependentKeys, expectedDependentKeys)
      }
    }

    _ = try await client.fetch(query: MockQuery<HeroAndFriendsNameWithIDsSelectionSet>(), cachePolicy: .networkOnly)

    await fulfillment(
      of: [secondServerRequestExpectation, updatedWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )
  }

  @MainActor
  func testQueryWatcherDoesNotHaveARetainCycle() async {
    class HeroAndFriendsNameWithIDsSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero?.self)
        ]
      }

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
              .field("name", String.self),
            ]
          }

          var name: String { __data["name"] }
        }
      }
    }
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let watchedQuery = MockQuery<HeroAndFriendsNameWithIDsSelectionSet>()

    let resultObserver = makeResultObserver(for: watchedQuery)

    var watcher: GraphQLQueryWatcher<MockQuery<HeroAndFriendsNameWithIDsSelectionSet>>? =
    await GraphQLQueryWatcher(
        client: client,
        query: watchedQuery,
        resultHandler: resultObserver.handler
      )

    weak var weakWatcher = watcher

    // Initial fetch from server
    let serverRequestExpectation =
    await server.expect(MockQuery<HeroAndFriendsNameWithIDsSelectionSet>.self) { @Sendable request in
        [
          "data": [
            "hero": [
              "id": "2001",
              "name": "R2-D2",
              "__typename": "Droid",
              "friends": [
                ["__typename": "Human", "id": "1000", "name": "Luke Skywalker"]
              ],
            ]
          ] as JSONValue
        ]
      }

    let initialWatcherResultExpectation = await resultObserver.expectation(
      description: "Watcher received initial result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)

        XCTAssertEqual(data.hero?.name, "R2-D2")

        let friendsNames = data.hero?.friends?.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker"])

        let expectedDependentKeys: Set = [
          "Droid:2001.__typename",
          "Droid:2001.friends",
          "Droid:2001.id",
          "Droid:2001.name",
          "Human:1000.__typename",
          "Human:1000.id",
          "Human:1000.name",
          "QUERY_ROOT.hero",
        ]
        let actualDependentKeys = try XCTUnwrap(graphQLResult.dependentKeys)
        XCTAssertEqual(actualDependentKeys, expectedDependentKeys)
      }
    }

    await watcher!.fetch(fetchBehavior: .NetworkOnly)

    await fulfillment(
      of: [serverRequestExpectation, initialWatcherResultExpectation],
      timeout: Self.defaultWaitTimeout
    )

    // Make sure it gets released
    watcher = nil
    store = nil
    server = nil
    client = nil

    XCTAssertTrueEventually(weakWatcher == nil, message: "Watcher was not released.")
  }
}
