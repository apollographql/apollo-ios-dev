import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import XCTest

@testable import ApolloPagination

final class AnyAsyncGraphQLQueryPagerTests: XCTestCase {
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

  func test_concatenatesPages_matchingInitialAndPaginated() async throws {
    struct ViewModel {
      let name: String
    }

    let anyPager = await createPager().eraseToAnyPager { data in
      data.hero.friendsConnection.friends.map {
        ViewModel(name: $0.name)
      }
    }

    let fetchExpectation = expectation(description: "Initial Fetch")
    fetchExpectation.assertForOverFulfill = false
    let subscriptionExpectation = expectation(description: "Subscription")
    subscriptionExpectation.expectedFulfillmentCount = 2
    var expectedViewModels: [ViewModel]?
    anyPager.subscribe { (result: Result<([ViewModel], UpdateSource), Error>) in
      switch result {
      case .success((let viewModels, _)):
        expectedViewModels = viewModels
        fetchExpectation.fulfill()
        subscriptionExpectation.fulfill()
      default:
        XCTFail("Failed to get view models from pager.")
      }
    }

    await fetchFirstPage(pager: anyPager)
    await fulfillment(of: [fetchExpectation], timeout: 1)
    try await fetchSecondPage(pager: anyPager)

    await fulfillment(of: [subscriptionExpectation], timeout: 1.0)
    let results = try XCTUnwrap(expectedViewModels)
    XCTAssertEqual(results.count, 3)
    XCTAssertEqual(results.map(\.name), ["Luke Skywalker", "Han Solo", "Leia Organa"])
  }

  func test_passesBackSeparateData() async throws {
    let anyPager = await createPager().eraseToAnyPager { _, initial, next in
      if let latestPage = next.last {
        return latestPage.hero.friendsConnection.friends.last?.name
      }
      return initial.hero.friendsConnection.friends.last?.name
    }

    let initialExpectation = expectation(description: "Initial")
    let secondExpectation = expectation(description: "Second")
    var expectedViewModel: String?
    anyPager.subscribe { (result: Result<(String?, UpdateSource), Error>) in
      switch result {
      case .success((let viewModel, _)):
        let oldValue = expectedViewModel
        expectedViewModel = viewModel
        if oldValue == nil {
          initialExpectation.fulfill()
        } else {
          secondExpectation.fulfill()
        }
      default:
        XCTFail("Failed to get view models from pager.")
      }
    }

    await fetchFirstPage(pager: anyPager)
    await fulfillment(of: [initialExpectation], timeout: 1.0)
    XCTAssertEqual(expectedViewModel, "Han Solo")

    try await fetchSecondPage(pager: anyPager)
    await fulfillment(of: [secondExpectation], timeout: 1.0)
    XCTAssertEqual(expectedViewModel, "Leia Organa")
  }

  func test_loadAll() async throws {
    let pager = createPager()

    let firstPageExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    let lastPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let loadAllExpectation = expectation(description: "Load all pages")
    let subscriber = await pager.subscribe { _ in
      loadAllExpectation.fulfill()
    }
    try await pager.loadAll()
    await fulfillment(of: [firstPageExpectation, lastPageExpectation, loadAllExpectation], timeout: 5)
    subscriber.cancel()
  }

  // MARK: - Test helpers

  private func createPager() -> AsyncGraphQLQueryPager<Query, Query> {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return AsyncGraphQLQueryPager<Query, Query>(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: .main,
      extractPageInfo: { data in
        switch data {
        case .initial(let data), .paginated(let data):
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

  private func fetchFirstPage<T>(pager: AnyAsyncGraphQLQueryPager<T>) async {
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }

  private func fetchSecondPage<T>(pager: AnyAsyncGraphQLQueryPager<T>) async throws {
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    try await pager.loadNext()
    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }
}
