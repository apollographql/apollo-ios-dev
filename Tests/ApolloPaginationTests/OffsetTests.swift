import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Combine
import XCTest

@testable import ApolloPagination

final class OffsetTests: XCTestCase {
  private typealias Query = MockQuery<Mocks.Hero.OffsetFriendsQuery>

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

  private func createPager() async -> GraphQLQueryPager<PaginationOutput<Query, Query>> {
    let pageSize = 2
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "offset": 0, "limit": pageSize]
    let pager = GraphQLQueryPagerCoordinator<Query, Query>(
      client: client,
      initialQuery: initialQuery,      
      extractPageInfo: { data in
        switch data {
        case .initial(let data, let output), .paginated(let data, let output):
          var totalOffset: Int = 0
          if let output {
            output.allData.forEach { page in
              totalOffset += page.hero.friends.count
            }
          }
          return OffsetPagination.Forward(
            offset: totalOffset,
            canLoadNext: !data.hero.friends.isEmpty || data.hero.friends.count % pageSize != 0
          )
        }
      },
      pageResolver: { pageInfo, direction in
        guard direction == .next else { return nil }
        let nextQuery = Query()
        nextQuery.__variables = [
          "id": "2001",
          "offset": pageInfo.offset,
          "limit": pageSize,
        ]
        return nextQuery
      }
    )
    return GraphQLQueryPager(pager: pager)
  }

  // This is due to a timing issue in unit tests only wherein we deinit immediately after waiting for expectations
  private func ignoringCancellations(error: (any Error)?) {
    if PaginationError.isCancellation(error: error as? PaginationError) {
      return
    } else {
      XCTAssertNil(error)
    }
  }

  private func fetchFirstPage<T>(pager: GraphQLQueryPager<T>) async {
    let serverExpectation = await Mocks.Hero.OffsetFriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }

  private func fetchSecondPage<T>(pager: GraphQLQueryPager<T>) async throws {
    let serverExpectation = await Mocks.Hero.OffsetFriendsQuery.expectationForLastPage(server: server)
    try await pager.loadNext()
    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }

  // MARK: - Tests

  func test_concatenatesPages_matchingInitialAndPaginated() async throws {
    struct ViewModel {
      let name: String
    }

    let pager = await createPager()

    let fetchExpectation = expectation(description: "Initial Fetch")
    fetchExpectation.assertForOverFulfill = false
    let subscriptionExpectation = expectation(description: "Subscription")
    subscriptionExpectation.expectedFulfillmentCount = 2
    var expectedViewModels: [ViewModel] = []
    let subscriber = pager.compactMap { value in
      switch value {
      case .success(let output):
        let friends = output.allData.flatMap { data in
          data.hero.friends.map { friend in
            ViewModel(name: friend.name)
          }
        }
        return friends
      case .failure(let error):
        XCTFail(error.localizedDescription)
        return nil
      }
    }.sink { viewModels in
      expectedViewModels = viewModels
      fetchExpectation.fulfill()
      subscriptionExpectation.fulfill()
    }

    await fetchFirstPage(pager: pager)
    await fulfillment(of: [fetchExpectation], timeout: 1)
    XCTAssertEqual(expectedViewModels.count, 2)
    XCTAssertEqual(expectedViewModels.map(\.name), ["Luke Skywalker", "Han Solo"])
    let canLoadNext = await pager.canLoadNext
    XCTAssertTrue(canLoadNext)

    try await fetchSecondPage(pager: pager)
    await fulfillment(of: [subscriptionExpectation], timeout: 1)
    XCTAssertEqual(expectedViewModels.count, 3)
    XCTAssertEqual(expectedViewModels.map(\.name), ["Luke Skywalker", "Han Solo", "Leia Organa"])
    subscriber.cancel()
  }

}
