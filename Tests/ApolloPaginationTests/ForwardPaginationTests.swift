import XCTest
import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

@testable import ApolloPagination

final class ForwardPaginationTests: XCTestCase, CacheDependentTesting {

  private typealias Query = MockQuery<Mocks.Hero.FriendsQuery>

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

  func test_fetchMultiplePages() throws {
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
    let nextPageExpectation = expectation(description: "Next Page")
    nextPageExpectation.expectedFulfillmentCount = 2
    
    var results: [Result<GraphQLQueryPager<Query, Query>.Output, Error>] = []
    var counter = 0
    pager.subscribe { result in
      results.append(result)
      initialFetchExpectation.fulfill()
      nextPageExpectation.fulfill()
      counter += 1
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
        XCTAssertEqual(counter, 1)
      }
    }

    try runActivity("Fetch second page") { _ in
      let secondPageExpectation = server.expect(Query.self) { _ in
        let pageInfo: [AnyHashable: AnyHashable] = [
          "__typename": "PageInfo",
          "endCursor": "Y3Vyc29yMw==",
          "hasNextPage": false
        ]
        let friends: [[String: AnyHashable]] = [
          [
            "__typename": "Human",
            "name": "Leia Organa",
            "id": "1003",
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

      pager.loadMore()
      wait(for: [secondPageExpectation, nextPageExpectation], timeout: 1.0)
      XCTAssertFalse(results.isEmpty)
      let result = try XCTUnwrap(results.last)
      try XCTAssertSuccessResult(result) { [pager] value in
        let (_, next, source) = value
        // Assert first page is unchanged
        XCTAssertEqual(try? results.first?.get().0, try? results.last?.get().0)

        XCTAssertEqual(counter, 2)
        XCTAssertFalse(next.isEmpty)
        XCTAssertEqual(next.count, 1)
        let page = try XCTUnwrap(next.first)
        XCTAssertEqual(page.hero.friendsConnection.friends.count, 1)
        XCTAssertEqual(pager.varMap.values.count, 1)
        XCTAssertEqual(source, .fetch)
      }
    }
  }

  func test_fetchMultiplePages_noCache() throws {
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
    let nextPageExpectation = expectation(description: "Next Page")
    nextPageExpectation.expectedFulfillmentCount = 2

    var results: [Result<GraphQLQueryPager<Query, Query>.Output, Error>] = []
    var counter = 0
    pager.subscribe { result in
      results.append(result)
      initialFetchExpectation.fulfill()
      nextPageExpectation.fulfill()
      counter += 1
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

      pager.fetch(cachePolicy: .fetchIgnoringCacheData)
      wait(for: [serverExpectation, initialFetchExpectation], timeout: 1.0)
      XCTAssertFalse(results.isEmpty)
      let result = try XCTUnwrap(results.first)
      XCTAssertSuccessResult(result) { value in
        let (first, next, source) = value
        XCTAssertTrue(next.isEmpty)
        XCTAssertEqual(first.hero.friendsConnection.friends.count, 2)
        XCTAssertEqual(first.hero.friendsConnection.totalCount, 3)
        XCTAssertEqual(source, .fetch)
        XCTAssertEqual(counter, 1)
      }
    }

    try runActivity("Fetch second page") { _ in
      let secondPageExpectation = server.expect(Query.self) { _ in
        let pageInfo: [AnyHashable: AnyHashable] = [
          "__typename": "PageInfo",
          "endCursor": "Y3Vyc29yMw==",
          "hasNextPage": false
        ]
        let friends: [[String: AnyHashable]] = [
          [
            "__typename": "Human",
            "name": "Leia Organa",
            "id": "1003",
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

      pager.loadMore(cachePolicy: .fetchIgnoringCacheData)
      wait(for: [secondPageExpectation, nextPageExpectation], timeout: 1.0)
      XCTAssertFalse(results.isEmpty)
      let result = try XCTUnwrap(results.last)
      try XCTAssertSuccessResult(result) { [pager] value in
        let (_, next, source) = value
        // Assert first page is unchanged
        XCTAssertEqual(try? results.first?.get().0, try? results.last?.get().0)

        XCTAssertEqual(counter, 2)
        XCTAssertFalse(next.isEmpty)
        XCTAssertEqual(next.count, 1)
        let page = try XCTUnwrap(next.first)
        XCTAssertEqual(page.hero.friendsConnection.friends.count, 1)
        XCTAssertEqual(pager.varMap.values.count, 1)
        XCTAssertEqual(source, .fetch)
      }
    }
  }

  func test_fetchMultiplePages_mutateHero() throws {
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
    let nextPageExpectation = expectation(description: "Next Page")
    nextPageExpectation.expectedFulfillmentCount = 2
    nextPageExpectation.assertForOverFulfill = false
    let mutationFulfillment = expectation(description: "Mutation")
    mutationFulfillment.expectedFulfillmentCount = 4
    nextPageExpectation.assertForOverFulfill = false

    var results: [Result<GraphQLQueryPager<Query, Query>.Output, Error>] = []
    var counter = 0
    pager.subscribe { result in
      results.append(result)
      initialFetchExpectation.fulfill()
      nextPageExpectation.fulfill()
      mutationFulfillment.fulfill()
      counter += 1
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
        XCTAssertEqual(counter, 1)
      }
    }

    try runActivity("Fetch second page") { _ in
      let secondPageExpectation = server.expect(Query.self) { _ in
        let pageInfo: [AnyHashable: AnyHashable] = [
          "__typename": "PageInfo",
          "endCursor": "Y3Vyc29yMw==",
          "hasNextPage": false
        ]
        let friends: [[String: AnyHashable]] = [
          [
            "__typename": "Human",
            "name": "Leia Organa",
            "id": "1003",
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

      pager.loadMore()
      wait(for: [secondPageExpectation, nextPageExpectation], timeout: 1.0)
      XCTAssertFalse(results.isEmpty)
      let result = try XCTUnwrap(results.last)
      try XCTAssertSuccessResult(result) { [pager] value in
        let (_, next, source) = value
        // Assert first page is unchanged
        XCTAssertEqual(try? results.first?.get().0, try? results.last?.get().0)

        XCTAssertEqual(counter, 2)
        XCTAssertFalse(next.isEmpty)
        XCTAssertEqual(next.count, 1)
        let page = try XCTUnwrap(next.first)
        XCTAssertEqual(page.hero.friendsConnection.friends.count, 1)
        XCTAssertEqual(pager.varMap.values.count, 1)
        XCTAssertEqual(source, .fetch)
      }
    }

    try runActivity("Local Cache Mutation") { _ in
      client.store.withinReadWriteTransaction { transaction in
        let cacheMutation = MockLocalCacheMutation<Mocks.Hero.NameCacheMutation>()
        cacheMutation.__variables = ["id": "2001"]
        try! transaction.update(cacheMutation) { data in
          data.hero?.name = "C3PO"
        }
      }

      wait(for: [mutationFulfillment], timeout: 1.0)
      XCTAssertEqual(results.count, 4)
      let finalResult = try XCTUnwrap(results.last)
      XCTAssertSuccessResult(finalResult) { value in
        XCTAssertEqual(value.0.hero.name, "C3PO")
        value.1.forEach { page in
          XCTAssertEqual(page.hero.name, "C3PO")
        }
      }
    }
  }
}
