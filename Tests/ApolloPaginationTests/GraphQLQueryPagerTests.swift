import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Combine
import XCTest

@testable import ApolloPagination

final class GraphQLQueryPagerTests: XCTestCase {
  private typealias Query = MockQuery<Mocks.Hero.FriendsQuery>
  private typealias ReverseQuery = MockQuery<Mocks.Hero.ReverseFriendsQuery>

  private var store: ApolloStore!
  private var server: MockGraphQLServer!
  private var networkTransport: MockNetworkTransport!
  private var client: ApolloClient!
  private var subscriptions: Set<AnyCancellable> = []

  override func setUp() {
    super.setUp()
    store = ApolloStore(cache: InMemoryNormalizedCache())
    server = MockGraphQLServer()
    networkTransport = MockNetworkTransport(server: server, store: store)
    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  override func tearDown() {
    super.tearDown()
    subscriptions.removeAll()
  }

  // MARK: - Test helpers

  private func createPager() -> GraphQLQueryPager<PaginationOutput<Query, Query>> {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return .init(pager: GraphQLQueryPagerCoordinator<Query, Query>(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: .main,
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
          "after": pageInfo.endCursor
        ]
        return nextQuery
      }
    ))
  }

  private func createReversePager() -> GraphQLQueryPager<PaginationOutput<ReverseQuery, ReverseQuery>> {
    let initialQuery = ReverseQuery()
    initialQuery.__variables = ["id": "2001", "first": 2, "before": "Y3Vyc29yMw=="]
    return .init(pager: GraphQLQueryPagerCoordinator<ReverseQuery, ReverseQuery>(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: .main,
      extractPageInfo: { data in
        switch data {
        case .initial(let data, _), .paginated(let data, _):
          return CursorBasedPagination.Reverse(
            hasPrevious: data.hero.friendsConnection.pageInfo.hasPreviousPage,
            startCursor: data.hero.friendsConnection.pageInfo.startCursor
          )
        }
      },
      pageResolver: { pageInfo, direction in
        guard direction == .previous else { return nil }
        let nextQuery = ReverseQuery()
        nextQuery.__variables = [
          "id": "2001",
          "first": 2,
          "before": pageInfo.startCursor
        ]
        return nextQuery
      }
    ))
  }

  // This is due to a timing issue in unit tests only wherein we deinit immediately after waiting for expectations
  private func ignoringCancellations(error: (any Error)?) {
    if PaginationError.isCancellation(error: error as? PaginationError) {
      return
    } else {
      XCTAssertNil(error)
    }
  }

  private func fetchFirstPage<T>(pager: GraphQLQueryPager<T>) {
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    pager.fetch()
    wait(for: [serverExpectation], timeout: 1.0)
  }

  private func fetchSecondPage<T>(pager: GraphQLQueryPager<T>) throws {
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    pager.loadNext(completion: ignoringCancellations(error:))
    wait(for: [serverExpectation], timeout: 1.0)
  }

  private func reverseFetchLastPage<T>(pager: GraphQLQueryPager<T>) {
    let serverExpectation = Mocks.Hero.ReverseFriendsQuery.expectationForLastItem(server: server)
    pager.fetch()
    wait(for: [serverExpectation], timeout: 1.0)
  }

  private func reverseFetchPreviousPage<T>(pager: GraphQLQueryPager<T>) throws {
    let serverExpectation = Mocks.Hero.ReverseFriendsQuery.expectationForPreviousItem(server: server)
    pager.loadPrevious(completion: ignoringCancellations(error:))
    wait(for: [serverExpectation], timeout: 1.0)
  }

  // MARK: - Tests

  func test_concatenatesPages_matchingInitialAndPaginated() throws {
    struct ViewModel {
      let name: String
    }

    let anyPager = createPager()

    let fetchExpectation = expectation(description: "Initial Fetch")
    fetchExpectation.assertForOverFulfill = false
    let subscriptionExpectation = expectation(description: "Subscription")
    subscriptionExpectation.expectedFulfillmentCount = 2
    var expectedViewModels: [ViewModel]?
    let subscription = anyPager.compactMap { result in
      switch result {
      case .success(let data):
        return data.allPages.flatMap { data in
          data.hero.friendsConnection.friends.map {
            ViewModel(name: $0.name)
          }
        }
      case .failure(let error):
        XCTFail(error.localizedDescription)
        return nil
      }
    }.sink { viewModels in
      expectedViewModels = viewModels
      fetchExpectation.fulfill()
      subscriptionExpectation.fulfill()
    }

    fetchFirstPage(pager: anyPager)
    wait(for: [fetchExpectation], timeout: 1)
    try fetchSecondPage(pager: anyPager)

    wait(for: [subscriptionExpectation], timeout: 1.0)
    let results = try XCTUnwrap(expectedViewModels)
    XCTAssertEqual(results.count, 3)
    XCTAssertEqual(results.map(\.name), ["Luke Skywalker", "Han Solo", "Leia Organa"])
    subscription.cancel()
  }

  func test_transformless_init() throws {
    let pager = createPager()
    let fetchExpectation = expectation(description: "Initial Fetch")
    var expectedViewModels: [PaginationOutput<Query, Query>] = []
    pager.sink { result in
      switch result {
      case .success(let value):
        expectedViewModels.append(value)
        fetchExpectation.fulfill()
      default:
        XCTFail("Failed to get view models from pager")
      }
    }.store(in: &subscriptions)

    fetchFirstPage(pager: pager)
    wait(for: [fetchExpectation], timeout: 1)
    XCTAssertFalse(expectedViewModels.isEmpty)
    XCTAssertEqual(expectedViewModels.count, 1)
  }

  func test_passesBackSeparateData() throws {
    let anyPager = createPager()

    let initialExpectation = expectation(description: "Initial")
    let secondExpectation = expectation(description: "Second")
    var expectedViewModel: String?
    anyPager
      .map { result in
        switch result {
        case .success(let output):
          return output.allPages.last.flatMap(\.hero.friendsConnection.friends.last?.name)
        case .failure(let error):
          XCTFail(error.localizedDescription)
          return nil
        }
      }
      .receive(on: RunLoop.main)
      .sink { viewModel in
        let oldValue = expectedViewModel
        expectedViewModel = viewModel
        if oldValue == nil {
          initialExpectation.fulfill()
        } else {
          secondExpectation.fulfill()
        }
      }.store(in: &subscriptions)

    fetchFirstPage(pager: anyPager)
    wait(for: [initialExpectation], timeout: 1.0)
    XCTAssertEqual(expectedViewModel, "Han Solo")
    XCTAssertTrue(anyPager.canLoadNext)
    XCTAssertFalse(anyPager.canLoadPrevious)

    try fetchSecondPage(pager: anyPager)
    wait(for: [secondExpectation], timeout: 1.0)
    XCTAssertEqual(expectedViewModel, "Leia Organa")
    XCTAssertFalse(anyPager.canLoadNext)
    XCTAssertFalse(anyPager.canLoadPrevious)
  }

  func test_reversePager_loadPrevious() throws {
    let anyPager = createReversePager()

    let initialExpectation = expectation(description: "Initial")
    let secondExpectation = expectation(description: "Second")
    var expectedViewModel: String?
    let subscriber = anyPager
      .compactMap { result in
        switch result {
        case .success(let output):
          if let latestPage = output.previousPages.last {
            return latestPage.hero.friendsConnection.friends.first?.name
          }
          return output.initialPage?.hero.friendsConnection.friends.first?.name
        case .failure(let error):
          XCTFail(error.localizedDescription)
          return nil
        }
      }
      .receive(on: RunLoop.main)
      .sink { viewModel in
        let oldValue = expectedViewModel
        expectedViewModel = viewModel
        if oldValue == nil {
          initialExpectation.fulfill()
        } else {
          secondExpectation.fulfill()
        }
      }

    reverseFetchLastPage(pager: anyPager)
    wait(for: [initialExpectation], timeout: 1.0)
    XCTAssertEqual(expectedViewModel, "Han Solo")
    XCTAssertFalse(anyPager.canLoadNext)
    XCTAssertTrue(anyPager.canLoadPrevious)

    try reverseFetchPreviousPage(pager: anyPager)
    wait(for: [secondExpectation], timeout: 1.0)
    XCTAssertEqual(expectedViewModel, "Luke Skywalker")
    XCTAssertFalse(anyPager.canLoadNext)
    XCTAssertFalse(anyPager.canLoadPrevious)
    subscriber.cancel()
  }

  // MARK: - Reset Tests

  @available(iOS 16.0, macOS 13.0, *)
  func test_pager_reset_calls_callback() async throws {
    server.customDelay = .milliseconds(1)
    let pager = createPager()
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1)
    server.customDelay = .milliseconds(200)
    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let callbackExpectation = expectation(description: "Callback")
    pager.loadNext(completion: { _ in
      callbackExpectation.fulfill()
    })
    try await Task.sleep(for: .milliseconds(50))
    pager.reset()
    await fulfillment(of: [callbackExpectation, secondPageExpectation], timeout: 1)
  }
}
