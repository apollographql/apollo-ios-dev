import XCTest
import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

@testable import apollo_ios_pagination

final class SubscribeTest: XCTestCase, CacheDependentTesting {
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

  private typealias Query = MockQuery<Mocks.Hero.FriendsQuery>

  func test_multipleSubscribers() throws {
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

    let initialFetchExpectation = expectation(description: "Results")
    initialFetchExpectation.assertForOverFulfill = false

    var results: [Result<GraphQLQueryPager<Query, Query>.Output, Error>] = []
    var otherResults: [Result<GraphQLQueryPager<Query, Query>.Output, Error>] = []
    pager.subscribe { result in
      results.append(result)
      initialFetchExpectation.fulfill()
    }

    pager.subscribe { result in
      otherResults.append(result)
    }

    try runActivity("Initial fetch from server") { _ in
      let serverExpectation = server.expect(Query.self) { _ in
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
      wait(for: [serverExpectation, initialFetchExpectation], timeout: 1.0)
      XCTAssertFalse(results.isEmpty)
      let result = try XCTUnwrap(results.first)
      XCTAssertSuccessResult(result) { value in
        let (first, next, source) = value
        XCTAssertTrue(next.isEmpty)
        XCTAssertEqual(first.hero.friendsConnection.friends.count, 2)
        XCTAssertEqual(first.hero.friendsConnection.totalCount, 3)
        XCTAssertEqual(source, .fetch)
        XCTAssertEqual(results.count, otherResults.count)
      }
    }
  }
}
