import XCTest
import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

@testable import apollo_ios_pagination

final class QueryPagerTests: XCTestCase, CacheDependentTesting {

  var cacheType: TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  var cache: NormalizedCache!
  var server: MockGraphQLServer!
  var client: ApolloClient!

  override func setUpWithError() throws {
    try super.setUpWithError()

    cache = try makeNormalizedCache()
    let store = ApolloStore(cache: cache)

    server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(server: server, store: store)

    client = ApolloClient(networkTransport: networkTransport, store: store)
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object = IDCacheKeyProvider.resolver
  }

  override func tearDownWithError() throws {
    cache = nil
    server = nil
    client = nil

    try super.tearDownWithError()
  }

  private typealias Query = MockQuery<MockPaginatedSelectionSet>
  func test_fetchMultiplePages() {
    let query = Query()
    query.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    let pager = GraphQLQueryPager.makeForwardCursorQueryPager(client: client) { page in
      let query: Query = MockQuery()
      let after: GraphQLNullable<String>
      if let endCursor = page?.endCursor {
        after = .some(endCursor)
      } else {
        after = .none
      }
      query.__variables = [
        "id": "2001",
        "first": 2,
        "after": after
      ]
      return query
    } extractPageInfo: { data in
      CursorBasedPagination.ForwardPagination(
        hasNext: data.hero.friendsConnection.pageInfo.hasNextPage,
        endCursor: data.hero.friendsConnection.pageInfo.endCursor
      )
    }

    addTeardownBlock { pager.cancel() }

    var results: [Result<GraphQLQueryPager<Query, Query>.Output, Error>] = []

    pager.subscribe { result in
      results.append(result)
    }

    runActivity("Initial fetch from server") { _ in
      let serverExpectation = server.expect(MockQuery<MockPaginatedSelectionSet>.self) { _ in
        let pageInfo: [AnyHashable: AnyHashable] = [
          "__typename": "PageInfo",
          "endCursor": "Y3Vyc29yMg==",
          "hasNextPage": true
        ]
        let friends: [[String: AnyHashable]] = [
          [
            "__typename": "Human",
            "name": "Luke Skywalker",
            "id": "1000",
          ],
          [
            "__typename": "Human",
            "name": "Han Solo",
            "id": "1002",
          ]
        ]
        let friendsConnection: [String: AnyHashable] = [
          "__typename": "FriendsConnection",
          "totalCount": 3,
          "friends": friends,
          "pageInfo": pageInfo
        ]

        let hero: [String: AnyHashable] = [
          "__typename": "Droid",
          "id": "2001",
          "name": "R2-D2",
          "friendsConnection": friendsConnection
        ]

        let data: [String: AnyHashable] = [
          "hero": hero
        ]

        return [
          "data": data
        ]
      }

      pager.fetch()
      wait(for: [serverExpectation], timeout: 1.0)
    }
  }
}

private class MockPaginatedSelectionSet: MockSelectionSet {
  override class var __selections: [Selection] { [
    .field("hero", Hero?.self, arguments: ["id": .variable("id")])
  ]}

  var hero: Hero { __data["hero"] }

  class Hero: MockSelectionSet {
    override class var __selections: [Selection] {[
      .field("__typename", String.self),
      .field("id", String.self),
      .field("name", String.self),
      .field("friendsConnection", FriendsConnection.self, arguments: [
        "first": .variable("first"),
        "after": .variable("after")
      ])
    ]}

    var name: String { __data["name"] }
    var id: String { __data["id"] }
    var friendsConnection: FriendsConnection { __data["friendsConnection"] }

    class FriendsConnection: MockSelectionSet {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("totalCount", Int.self),
        .field("friends", [Character].self),
        .field("pageInfo", PageInfo.self)
      ]}

      var totalCount: Int { __data["totalCount"] }
      var friends: [Character] { __data["friends"] }
      var pageInfo: PageInfo { __data["pageInfo"] }

      class Character: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("id", String.self),
        ]}

        var name: String { __data["name"] }
        var id: String { __data["id"] }
      }

      class PageInfo: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("endCursor", Optional<String>.self),
          .field("hasNextPage", Bool.self)
        ]}

        var endCursor: String? { __data["endCursor"] }
        var hasNextPage: Bool { __data["hasNextPage"] }
      }
    }
  }
}
