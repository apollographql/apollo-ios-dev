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
  private var cancellables: [AnyCancellable] = []

  override func setUp() {
    super.setUp()
    store = ApolloStore(cache: InMemoryNormalizedCache())
    server = MockGraphQLServer()
    networkTransport = MockNetworkTransport(server: server, store: store)
    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  func test_concurrentFetches() async throws {
    let pager = createPager()
    var results: [Result<GraphQLQueryPager<Query, Query>.Output, Error>] = []
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
      XCTAssertEqual(error as? PaginationError, PaginationError.loadInProgress)
    }
  }

  func test_concurrentFetches_nonisolated() throws {
    let pager = createNonisolatedPager()
    var results: [Result<GraphQLQueryPager<Query, Query>.Output, Error>] = []
    let initialExpectation = expectation(description: "Initial")
    initialExpectation.assertForOverFulfill = false
    let nextExpectation = expectation(description: "Next")
    nextExpectation.expectedFulfillmentCount = 2
    pager.subscribe(onUpdate: {
      results.append($0)
      initialExpectation.fulfill()
      nextExpectation.fulfill()
    })
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    pager.fetch()
    wait(for: [serverExpectation, initialExpectation], timeout: 1.0)

    XCTAssertEqual(results.count, 1)
    loadDataFromManyThreads(pager: pager)
    wait(for: [nextExpectation], timeout: 1)

    XCTAssertEqual(results.count, 2)
  }

  private func loadDataFromManyThreads(
    pager: GraphQLQueryPager<Query, Query>.Actor,
    expectation: XCTestExpectation
  ) async {
    await withTaskGroup(of: Void.self) { group in
      let serverExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: self.server)
      group.addTask { try? await pager.loadMore() }
      group.addTask { try? await pager.loadMore() }
      group.addTask { try? await pager.loadMore() }
      group.addTask { try? await pager.loadMore() }
      group.addTask { try? await pager.loadMore() }

      group.addTask { await self.fulfillment(of: [serverExpectation, expectation], timeout: 100) }
      await group.waitForAll()
    }
  }

  private func loadDataFromManyThreadsThrowing(
    pager: GraphQLQueryPager<Query, Query>.Actor
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      let serverExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: self.server)
      group.addTask(priority: .userInitiated) { try await pager.loadMore() }
      group.addTask { try await pager.loadMore() }
      group.addTask { try await pager.loadMore() }
      group.addTask { try await pager.loadMore() }
      group.addTask { try await pager.loadMore() }

      group.addTask { await self.fulfillment(of: [serverExpectation], timeout: 100) }
      try await group.waitForAll()
    }
  }

  private func loadDataFromManyThreads(
    pager: GraphQLQueryPager<Query, Query>
  ) {
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: self.server)

    (0..<5).forEach { _ in
      try? pager.loadMore()
    }
    wait(for: [serverExpectation], timeout: 1.0)
  }

  // MARK: - Test helpers

  private func createPager() -> GraphQLQueryPager<Query, Query>.Actor {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return GraphQLQueryPager<Query, Query>.Actor(
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
      },
      previousPageResolver: nil
    )
  }

  private func createNonisolatedPager() -> GraphQLQueryPager<Query, Query> {
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
      },
      previousPageResolver: nil
    )
  }

  private func fetchFirstPage(pager: GraphQLQueryPager<Query, Query>.Actor) async {
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }
}
