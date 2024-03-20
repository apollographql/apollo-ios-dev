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
    networkTransport = MockNetworkTransport(server: server, store: store)
    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  private func createPager() async -> AsyncGraphQLQueryPager<PaginationOutput<Query, Query>> {
    let pageSize = 2
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "offset": 0, "limit": pageSize]
    let pager = AsyncGraphQLQueryPagerCoordinator<Query, Query>(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: .main,
      extractPageInfo: { data in
        switch data {
        case .initial(let data, let output), .paginated(let data, let output):
          var totalOffset: Int = 0
          if let output {
            let pages = (output.previousPages + [output.initialPage] + output.nextPages)
            pages.forEach { page in
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
          "limit": pageSize
        ]
        return nextQuery
      }
    )
    return AsyncGraphQLQueryPager(pager: pager)
  }

  // This is due to a timing issue in unit tests only wherein we deinit immediately after waiting for expectations
  private func ignoringCancellations(error: Error?) {
    if PaginationError.isCancellation(error: error as? PaginationError) {
      return
    } else {
      XCTAssertNil(error)
    }
  }


  private func fetchFirstPage<T>(pager: AsyncGraphQLQueryPager<T>) async {
    let serverExpectation = Mocks.Hero.OffsetFriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }

  private func fetchSecondPage<T>(pager: AsyncGraphQLQueryPager<T>) async throws {
    let serverExpectation = Mocks.Hero.OffsetFriendsQuery.expectationForLastPage(server: server)
    try await pager.loadNext()
    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }

  // MARK: - Tests

  func test_concatenatesPages_matchingInitialAndPaginated() async throws {
    struct ViewModel {
      let name: String
    }

    let pager = await createPager()
    var results: [ViewModel]?
    let cancellable = pager.map { value in
      switch value {
      case .success((let output, _)):
        let pages = output.previousPages + [output.initialPage] + output.nextPages

        let friends = pages.flatMap { data in
          data.hero.friends.map { friend in
            ViewModel(name: friend.name)
          }
        }
        return Result<[ViewModel], Error>.success(friends)
      case .failure(let error):
        return .failure(error)
      }
    }.sink { result in
      switch result {
      case .success((let viewModels)):
        results = viewModels
      default:
        XCTFail("Failed to get view models from pager.")
      }
    }

    await fetchFirstPage(pager: pager)
    XCTAssertEqual(results?.count, 2)
    XCTAssertEqual(results?.map(\.name), ["Luke Skywalker", "Han Solo"])
    let canLoadNext = await pager.canLoadNext
    XCTAssertTrue(canLoadNext)

    try await fetchSecondPage(pager: pager)
    XCTAssertEqual(results?.count, 3)
    XCTAssertEqual(results?.map(\.name), ["Luke Skywalker", "Han Solo", "Leia Organa"])
    cancellable.cancel()
  }

}
