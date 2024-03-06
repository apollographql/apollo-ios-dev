import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import XCTest

@testable import ApolloPagination

final class AsyncGraphQLQueryPagerTests: XCTestCase {
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

  func test_forwardInit_simple() async throws {
    let initialQuery = Query()
    initialQuery.__variables = [
      "id": "2001",
      "first": 2,
      "after": GraphQLNullable<String>.null
    ]
    let pager = await AsyncGraphQLQueryPager(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: { data in
        CursorBasedPagination.Forward(
          hasNext: data.hero.friendsConnection.pageInfo.hasNextPage,
          endCursor: data.hero.friendsConnection.pageInfo.endCursor
        )
      }, 
      pageResolver: { page, direction in
        switch direction {
        case .next:
          let nextQuery = Query()
          nextQuery.__variables = [
            "id": "2001",
            "first": 2,
            "after": page.endCursor
          ]
          return nextQuery
        case .previous:
          return nil
        }
      }
    )

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1)

    var canLoadMore = await pager.canLoadNext
    XCTAssertTrue(canLoadMore)

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = pager.sink { value in
      secondPageFetch.fulfill()
    }
    try await pager.loadNext()
    await fulfillment(of: [secondPageExpectation, secondPageFetch])
    subscription.cancel()
    canLoadMore = await pager.canLoadNext
    XCTAssertFalse(canLoadMore)
  }

  func test_forwardInit_simple_mapping() async throws {
    struct ViewModel {
      let name: String
    }

    let initialQuery = Query()
    initialQuery.__variables = [
      "id": "2001",
      "first": 2,
      "after": GraphQLNullable<String>.null
    ]
    let pager = await AsyncGraphQLQueryPager(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: { data in
        CursorBasedPagination.Forward(
          hasNext: data.hero.friendsConnection.pageInfo.hasNextPage,
          endCursor: data.hero.friendsConnection.pageInfo.endCursor
        )
      },
      pageResolver: { page, direction in
        switch direction {
        case .next:
          let nextQuery = Query()
          nextQuery.__variables = [
            "id": "2001",
            "first": 2,
            "after": page.endCursor
          ]
          return nextQuery
        case .previous:
          return nil
        }
      }
    )

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1)

    var canLoadMore = await pager.canLoadNext
    XCTAssertTrue(canLoadMore)

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = pager
      .compactMap { output -> [ViewModel]? in
        guard case .success((let output, _)) = output else { return nil }
        let inOrderData = output.previousPages + [output.initialPage] + output.nextPages
        let models = inOrderData.flatMap { data in
          data.hero.friendsConnection.friends.map { friend in ViewModel(name: friend.name) }
        }
        return models
      }
      .sink { _ in
        secondPageFetch.fulfill()
      }

    try await pager.loadNext()
    await fulfillment(of: [secondPageExpectation, secondPageFetch])
    subscription.cancel()
    canLoadMore = await pager.canLoadNext
    XCTAssertFalse(canLoadMore)
  }

  func test_forwardInit_singleQuery_transform() async throws {
    let initialQuery = Query()
    initialQuery.__variables = [
      "id": "2001",
      "first": 2,
      "after": GraphQLNullable<String>.null
    ]
    let pager = await AsyncGraphQLQueryPager(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: { data in
        CursorBasedPagination.Forward(
          hasNext: data.hero.friendsConnection.pageInfo.hasNextPage,
          endCursor: data.hero.friendsConnection.pageInfo.endCursor
        )
      },
      pageResolver: { page, direction in
        switch direction {
        case .next:
          let nextQuery = Query()
          nextQuery.__variables = [
            "id": "2001",
            "first": 2,
            "after": page.endCursor
          ]
          return nextQuery
        case .previous:
          return nil
        }
      } ,
      transform: { previous, first, next in
        let inOrderData = previous + [first] + next
        return inOrderData.flatMap { data in
          data.hero.friendsConnection.friends.map { friend in friend.name }
        }
      }
    )

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1)

    var canLoadMore = await pager.canLoadNext
    XCTAssertTrue(canLoadMore)

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = pager.sink { value in
      secondPageFetch.fulfill()
    }
    try await pager.loadNext()
    await fulfillment(of: [secondPageExpectation, secondPageFetch])
    subscription.cancel()
    canLoadMore = await pager.canLoadNext
    XCTAssertFalse(canLoadMore)
  }

  func test_forwardInit_singleQuery_transform_mapping() async throws {
    struct ViewModel {
      let name: String
    }

    let initialQuery = Query()
    initialQuery.__variables = [
      "id": "2001",
      "first": 2,
      "after": GraphQLNullable<String>.null
    ]
    let pager = await AsyncGraphQLQueryPager(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: { data in
        CursorBasedPagination.Forward(
          hasNext: data.hero.friendsConnection.pageInfo.hasNextPage,
          endCursor: data.hero.friendsConnection.pageInfo.endCursor
        )
      },
      pageResolver: { page, direction in
        switch direction {
        case .next:
          let nextQuery = Query()
          nextQuery.__variables = [
            "id": "2001",
            "first": 2,
            "after": page.endCursor
          ]
          return nextQuery
        case .previous:
          return nil
        }
      },
      transform: { previous, first, next in
        let inOrderData = previous + [first] + next
        return inOrderData.flatMap { data in
          data.hero.friendsConnection.friends.map { friend in friend.name }
        }
      }
    )

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1)

    var canLoadMore = await pager.canLoadNext
    XCTAssertTrue(canLoadMore)

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = pager
      .compactMap { result in
        switch result {
        case .success((let strings, _)):
          return strings.map(ViewModel.init(name:))
        case .failure(let error):
          XCTFail("Unexpected failure: \(error)")
          return nil
        }
      }.sink { value in
        secondPageFetch.fulfill()
      }
    try await pager.loadNext()
    await fulfillment(of: [secondPageExpectation, secondPageFetch])
    subscription.cancel()
    canLoadMore = await pager.canLoadNext
    XCTAssertFalse(canLoadMore)
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

  private func createPager() -> AsyncGraphQLQueryPagerCoordinator<Query, Query> {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return AsyncGraphQLQueryPagerCoordinator<Query, Query>(
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
          "after": pageInfo.endCursor,
        ]
        return nextQuery
      }
    )
  }

  private func fetchFirstPage<T>(pager: AsyncGraphQLQueryPager<T>) async {
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }

  private func fetchSecondPage<T>(pager: AsyncGraphQLQueryPager<T>) async throws {
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    try await pager.loadNext()
    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }
}
