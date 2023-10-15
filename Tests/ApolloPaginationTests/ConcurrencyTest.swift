import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Combine
import XCTest

@testable import ApolloPagination

final class ConcurrencyTests: XCTestCase {
  private typealias Query = MockQuery<Mocks.Hero.FriendsQuery>

  private var store: ApolloStore!
  private var server: MockGraphQLServer!
  private var networkTransport: MockNetworkTransport!
  private var client: ApolloClient!

  override func setUp() {
    super.setUp()
    store = ApolloStore(cache: InMemoryNormalizedCache())
    server = MockGraphQLServer()
    networkTransport = MockNetworkTransport(server: server, store: store)
    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  func test_concatenatesPages_matchingInitialAndPaginated() throws {
    let pager = createPager()
    let firstPageExpectation = expectation(description: "Firstpage")
    let subscription = pager.subscribe { _ in
      firstPageExpectation.fulfill()
    }
    fetchFirstPage(pager: pager)
    wait(for: [firstPageExpectation], timeout: 1)
    subscription.cancel()

    Task {
      var results: [Result<(Query.Data, [Query.Data], UpdateSource), Error>] = []
      var completionCount = 0

      fetchFirstPage(pager: pager)
      pager.subscribe { result in
        results.append(result)
        completionCount += 1
      }
      await loadDataFromManyThreads(pager: pager)

      XCTAssertEqual(results.count, 2)
      XCTAssertEqual(completionCount, 1)
    }

  }

  private func loadDataFromManyThreads(
    pager: GraphQLQueryPager<Query, Query>
  ) async {
    await withTaskGroup(of: Void.self) { group in
      (1...10).forEach { _ in
        group.addTask { try? pager.loadMore() }
      }
      await group.waitForAll()
    }
  }

  // MARK: - Test helpers

  private func createPager() -> GraphQLQueryPager<Query, Query> {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return GraphQLQueryPager<Query, Query>(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: { data in
        switch data {
        case .initial(let data), .paginated(let data):
          return CursorBasedPagination.ForwardPagination(
            hasNext: data.hero.friendsConnection.pageInfo.hasNextPage,
            endCursor: data.hero.friendsConnection.pageInfo.endCursor
          )
        }
      },
      nextPageResolver: { pageInfo in
        let nextQuery = Query()
        nextQuery.__variables = [
          "id": "2001",
          "first": 2,
          "after": pageInfo.endCursor,
        ]
        return nextQuery
      }
    )
  }

  private func fetchFirstPage(pager: GraphQLQueryPager<Query, Query>) {
    let serverExpectation = server.expect(Query.self) { _ in
      let pageInfo: [AnyHashable: AnyHashable] = [
        "__typename": "PageInfo",
        "endCursor": "Y3Vyc29yMg==",
        "hasNextPage": true,
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
        ],
      ]
      let friendsConnection: [String: AnyHashable] = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
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

  private func fetchSecondPage(pager: GraphQLQueryPager<Query, Query>) throws {
    let serverExpectation = server.expect(Query.self) { _ in
      let pageInfo: [AnyHashable: AnyHashable] = [
        "__typename": "PageInfo",
        "endCursor": "Y3Vyc29yMw==",
        "hasNextPage": false,
      ]
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Leia Organa",
          "id": "1003",
        ],
      ]
      let friendsConnection: [String: AnyHashable] = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data
      ]
    }

    try pager.loadMore()
    wait(for: [serverExpectation], timeout: 1.0)
  }
}
