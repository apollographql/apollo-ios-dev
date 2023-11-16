import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import XCTest

@testable import ApolloPagination

final class AnyGraphQLQueryPagerTests: XCTestCase {
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
    struct ViewModel {
      let name: String
    }

    let anyPager = createPager().eraseToAnyPager { data in
      data.hero.friendsConnection.friends.map {
        ViewModel(name: $0.name)
      }
    }

    let subscriptionExpectation = expectation(description: "Subscription")
    subscriptionExpectation.expectedFulfillmentCount = 2
    var expectedViewModels: [ViewModel]?
    anyPager.subscribe { (result: Result<([ViewModel], UpdateSource), Error>) in
      switch result {
      case .success((let viewModels, _)):
        expectedViewModels = viewModels
        subscriptionExpectation.fulfill()
      default:
        XCTFail("Failed to get view models from pager.")
      }
    }

    fetchFirstPage(pager: anyPager)
    try fetchSecondPage(pager: anyPager)

    wait(for: [subscriptionExpectation], timeout: 1.0)
    let results = try XCTUnwrap(expectedViewModels)
    XCTAssertEqual(results.count, 3)
    XCTAssertEqual(results.map(\.name), ["Luke Skywalker", "Han Solo", "Leia Organa"])
  }

  func test_passesBackSeparateData() throws {
    let anyPager = createPager().eraseToAnyPager { _, initial, next in
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

    fetchFirstPage(pager: anyPager)
    wait(for: [initialExpectation], timeout: 1.0)
    XCTAssertEqual(expectedViewModel, "Han Solo")

    try fetchSecondPage(pager: anyPager)
    wait(for: [secondExpectation], timeout: 1.0)
    XCTAssertEqual(expectedViewModel, "Leia Organa")
  }

  func test_loadAll() throws {
    let pager = createPager()

    let firstPageExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    let lastPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let loadAllExpectation = expectation(description: "Load all pages")
    pager.subscribe { _ in
      loadAllExpectation.fulfill()
    }
    pager.loadAll()
    wait(for: [firstPageExpectation, lastPageExpectation, loadAllExpectation], timeout: 5)
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
      },
      previousPageResolver: nil
    )
  }

  private func fetchFirstPage<T>(pager: AnyGraphQLQueryPager<T>) {
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    pager.fetch()
    wait(for: [serverExpectation], timeout: 1.0)
  }

  private func fetchSecondPage<T>(pager: AnyGraphQLQueryPager<T>) throws {
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    pager.loadMore()
    wait(for: [serverExpectation], timeout: 1.0)
  }
}
