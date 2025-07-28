import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
@preconcurrency import Combine
import XCTest

@testable import ApolloPagination

final class ConcurrencyTests: XCTestCase {
  private typealias Query = MockQuery<Mocks.Hero.FriendsQuery>

  private var store: ApolloStore!
  private var server: MockGraphQLServer!
  private var networkTransport: MockNetworkTransport!
  private var client: ApolloClient!
  private var cancellables: [AnyCancellable] = []

  override func setUp() {
    super.setUp()
    store = ApolloStore(cache: InMemoryNormalizedCache())
    server = MockGraphQLServer()
    networkTransport = MockNetworkTransport(mockServer: server, store: store)
    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  // MARK: - Test helpers

  private func loadDataFromManyThreads(
    pager: GraphQLQueryPagerCoordinator<Query, Query>,
    expectation: XCTestExpectation
  ) async {
    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: self.server)
    await withTaskGroup(of: Void.self) { group in
      group.addTask { try? await pager.loadNext() }
      group.addTask { try? await pager.loadNext() }
      group.addTask { try? await pager.loadNext() }
      group.addTask { try? await pager.loadNext() }
      group.addTask { try? await pager.loadNext() }

      await group.waitForAll()
    }

    await self.fulfillment(of: [serverExpectation, expectation], timeout: 100)
  }

  private func loadDataFromManyThreadsThrowing(
    pager: GraphQLQueryPagerCoordinator<Query, Query>
  ) async throws {
    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: self.server)
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try await pager.loadNext() }
      group.addTask { try await pager.loadNext() }
      group.addTask { try await pager.loadNext() }
      group.addTask { try await pager.loadNext() }
      group.addTask { try await pager.loadNext() }

      try await group.waitForAll()
    }
    await self.fulfillment(of: [serverExpectation], timeout: 100)
  }

  private func loadDataFromManyThreads(
    pager: GraphQLQueryPagerCoordinator<Query, Query>
  ) async throws {
    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: self.server)

    for _ in (0..<5) {
      try await pager.loadNext()
    }
    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }

  private func createPager() -> GraphQLQueryPagerCoordinator<Query, Query> {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return GraphQLQueryPagerCoordinator<Query, Query>(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: { data in
        switch data {
        case .initial(let data, _), .paginated(let data, _):
          return CursorBasedPagination.Forward(
            hasNext: data.hero.friendsConnection.pageInfo.hasNextPage,
            endCursor: data.hero.friendsConnection.pageInfo.endCursor
          )
        }
      },
      pageResolver: { pageInfo, direction in
        guard direction == .next else { return nil }
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

  private func fetchFirstPage(pager: GraphQLQueryPagerCoordinator<Query, Query>) async {
    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }

  // MARK: - Tests

  func test_concurrentFetches() async throws {
    let pager = createPager()
    nonisolated(unsafe) var results: [Result<PaginationOutput<Query, Query>, any Error>] = []
    let resultsExpectation = expectation(description: "Results arrival")
    resultsExpectation.expectedFulfillmentCount = 2
    await pager.subscribe { result in
      results.append(result)
      resultsExpectation.fulfill()
    }.store(in: &cancellables)
    await fetchFirstPage(pager: pager)
    await loadDataFromManyThreads(pager: pager, expectation: resultsExpectation)

    XCTAssertEqual(results.count, 2)
  }

  func test_concurrentFetchesThrowsError() async throws {
    let pager = createPager()
    await fetchFirstPage(pager: pager)
    await XCTAssertThrowsError(try await loadDataFromManyThreadsThrowing(pager: pager)) { error in
      XCTAssertTrue(PaginationError.isLoadInProgress(error: error as? PaginationError))
    }
  }

}
