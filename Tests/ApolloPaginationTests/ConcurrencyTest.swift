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

  func test_concurrentFetches() async throws {
    let pager = createPager()
    var results: [Result<(Query.Data, [Query.Data], UpdateSource), Error>] = []
    pager.subscribe { result in
      results.append(result)
    }
    fetchFirstPage(pager: pager)
    var completionCount = 0
    let onUpdate: () -> Void = {
      completionCount += 1
    }
    await loadDataFromManyThreads(pager: pager, onUpdate: onUpdate)

    XCTAssertEqual(results.count, 2)
    XCTAssertEqual(completionCount, 1)
  }

  private func loadDataFromManyThreads(
    pager: GraphQLQueryPager<Query, Query>,
    onUpdate: @escaping () -> Void
  ) async {
    try? await withThrowingTaskGroup(of: Void.self) { group in
      let serverExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: self.server)
      (1...5).forEach { _ in
        group.addTask { try await pager.loadMore(completion: onUpdate) }
      }
      group.addTask { await self.fulfillment(of: [serverExpectation], timeout: 1) }
      try await group.waitForAll()
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
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    pager.refetch()
    wait(for: [serverExpectation], timeout: 1.0)
  }
}
