import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import XCTest

@testable import ApolloPagination

final class GraphQLQueryPagerTests: XCTestCase {
  private typealias Query = MockQuery<Mocks.Hero.FriendsQuery>

  private var store: ApolloStore!
  private var server: MockGraphQLServer!
  private var networkTransport: MockNetworkTransport!
  private var client: ApolloClient!

  override func setUp() {
    super.setUp()
    store = ApolloStore(cache: InMemoryNormalizedCache())
    server = MockGraphQLServer()
    networkTransport = MockNetworkTransport(mockServer: server, store: store)
    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  func test_forwardInit_simple() async throws {
    let initialQuery = Query()
    initialQuery.__variables = [
      "id": "2001",
      "first": 2,
      "after": GraphQLNullable<String>.null,
    ]
    let pager = GraphQLQueryPager(
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
            "after": page.endCursor ?? .null,
          ]
          return nextQuery
        case .previous:
          return nil
        }
      }
    )

    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1)

    var canLoadMore = await pager.canLoadNext
    XCTAssertTrue(canLoadMore)

    let secondPageExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = pager.sink { _ in
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
      "after": GraphQLNullable<String>.null,
    ]
    let pager = GraphQLQueryPager(
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
            "after": page.endCursor ?? .null,
          ]
          return nextQuery
        case .previous:
          return nil
        }
      }
    )

    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1)

    var canLoadMore = await pager.canLoadNext
    XCTAssertTrue(canLoadMore)

    let secondPageExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = pager
      .compactMap { output -> [ViewModel]? in
        guard case .success(let output) = output else { return nil }
        let models = output.allData.flatMap { data in
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
      "after": GraphQLNullable<String>.null,
    ]
    let pager = GraphQLQueryPager(
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
            "after": page.endCursor ?? .null,
          ]
          return nextQuery
        case .previous:
          return nil
        }
      }
    )

    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1)

    var canLoadMore = await pager.canLoadNext
    XCTAssertTrue(canLoadMore)

    let secondPageExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = pager.sink { _ in
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
      "after": GraphQLNullable<String>.null,
    ]
    let pager = GraphQLQueryPager(
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
            "after": page.endCursor ?? .null,
          ]
          return nextQuery
        case .previous:
          return nil
        }
      }
    )

    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1)

    var canLoadMore = await pager.canLoadNext
    XCTAssertTrue(canLoadMore)

    let secondPageExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = pager
      .compactMap { result in
        switch result {
        case .success(let output):
          return output.allData.flatMap { data in
            data.hero.friendsConnection.friends.map { friend in friend.name }
          }.map(ViewModel.init(name:))
        case .failure(let error):
          XCTFail("Unexpected failure: \(error)")
          return nil
        }
      }.sink { _ in
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

    let anyPager = createPager()

    let fetchExpectation = expectation(description: "Initial Fetch")
    fetchExpectation.assertForOverFulfill = false
    let subscriptionExpectation = expectation(description: "Subscription")
    subscriptionExpectation.expectedFulfillmentCount = 2
    var expectedViewModels: [ViewModel]?
    let subscriber = anyPager
      .compactMap { result in
        switch result {
        case .success(let data):
          return data.allData.flatMap { data in
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

    await fetchFirstPage(pager: anyPager)
    await fulfillment(of: [fetchExpectation], timeout: 1)
    try await fetchSecondPage(pager: anyPager)

    await fulfillment(of: [subscriptionExpectation], timeout: 1)
    let results = try XCTUnwrap(expectedViewModels)
    XCTAssertEqual(results.count, 3)
    XCTAssertEqual(results.map(\.name), ["Luke Skywalker", "Han Solo", "Leia Organa"])
    subscriber.cancel()
  }

  func test_passesBackSeparateData() async throws {
    let anyPager = createPager()

    let initialExpectation = expectation(description: "Initial")
    let secondExpectation = expectation(description: "Second")
    var expectedViewModel: String?
    let subscriber = anyPager
      .compactMap { result in
        switch result {
        case .success(let output):
          if let latestPage = output.nextPages.last {
            return latestPage.data?.hero.friendsConnection.friends.last?.name
          }
          return output.initialPage?.data?.hero.friendsConnection.friends.last?.name
        case .failure(let error):
          XCTFail(error.localizedDescription)
          return nil
        }
      }
      .sink { viewModel in
        let oldValue = expectedViewModel
        expectedViewModel = viewModel
        if oldValue == nil {
          initialExpectation.fulfill()
        } else {
          secondExpectation.fulfill()
        }
      }

    await fetchFirstPage(pager: anyPager)
    await fulfillment(of: [initialExpectation], timeout: 1)
    XCTAssertEqual(expectedViewModel, "Han Solo")

    try await fetchSecondPage(pager: anyPager)
    await fulfillment(of: [secondExpectation], timeout: 1)
    XCTAssertEqual(expectedViewModel, "Leia Organa")
    subscriber.cancel()
  }

  func test_loadAll() async throws {
    let pager = createPager()

    let firstPageExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    let lastPageExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let loadAllExpectation = expectation(description: "Load all pages")
    let subscriber = pager.sink { _ in
      loadAllExpectation.fulfill()
    }
    try await pager.loadAll()
    await fulfillment(of: [firstPageExpectation, lastPageExpectation, loadAllExpectation], timeout: 5)
    subscriber.cancel()
  }

  func test_errors_partialSuccess() async throws {
    let pager = createPager()
    var expectedResults: [Result<PaginationOutput<Query, Query>, any Error>] = []
    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPageWithErrors(server: server)
    let fetchExpectation = expectation(description: "Fetch")
    let subscription = pager.sink { output in
      expectedResults.append(output)
      fetchExpectation.fulfill()
    }
    await pager.fetch()
    await fulfillment(of: [serverExpectation, fetchExpectation], timeout: 3)
    XCTAssertEqual(expectedResults.count, 1)
    let result = try XCTUnwrap(expectedResults.first)
    let successValue = try result.get()
    XCTAssertFalse(successValue.allErrors.isEmpty)
    XCTAssertEqual(successValue.initialPage?.data?.hero.name, "R2-D2")
    let canLoadNext = await pager.canLoadNext
    XCTAssertTrue(canLoadNext)
    subscription.cancel()
  }

  func test_errors_noData() async throws {
    let pager = createPager()
    var expectedResults: [Result<PaginationOutput<Query, Query>, any Error>] = []
    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPageErrorsOnly(server: server)
    let fetchExpectation = expectation(description: "Fetch")
    let subscription = pager.sink { output in
      expectedResults.append(output)
      fetchExpectation.fulfill()
    }
    await pager.fetch()
    await fulfillment(of: [serverExpectation, fetchExpectation], timeout: 3)
    XCTAssertEqual(expectedResults.count, 1)
    let result = try XCTUnwrap(expectedResults.first)
    let successValue = try result.get()
    XCTAssertFalse(successValue.allErrors.isEmpty)
    XCTAssertNil(successValue.initialPage?.data)
    subscription.cancel()
  }

  func test_errors_noData_loadAll() async throws {
    let pager = createPager()
    var expectedResults: [Result<PaginationOutput<Query, Query>, any Error>] = []
    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPageErrorsOnly(server: server)
    let fetchExpectation = expectation(description: "Fetch")
    let subscription = pager.sink { output in
      expectedResults.append(output)
      XCTAssertEqual(expectedResults.count, 1)
      do {
        let result = try XCTUnwrap(expectedResults.first)
        let successValue = try result.get()
        XCTAssertFalse(successValue.allErrors.isEmpty)
        XCTAssertNil(successValue.initialPage?.data)
      } catch {
        XCTFail(error.localizedDescription)
      }
      fetchExpectation.fulfill()
    }
    try await pager.loadAll(fetchFromInitialPage: true)
    await fulfillment(of: [serverExpectation, fetchExpectation], timeout: 3)
    subscription.cancel()
  }

  func test_errors_noDataOnSecondPage_loadAll() async throws {
    let pager = createPager()
    var expectedResults: [Result<PaginationOutput<Query, Query>, any Error>] = []

    let firstPageExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    let lastPageExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPageErrorsOnly(server: server)
    let loadAllExpectation = expectation(description: "Load all pages")
    let subscriber = pager.sink { output in
      expectedResults.append(output)
      loadAllExpectation.fulfill()
    }
    try await pager.loadAll()
    await fulfillment(of: [firstPageExpectation, lastPageExpectation, loadAllExpectation], timeout: 5)
    let result = try XCTUnwrap(expectedResults.first)
    let successValue = try result.get()
    XCTAssertFalse(successValue.allErrors.isEmpty)
    XCTAssertNotNil(successValue.initialPage)
    XCTAssertNil(successValue.nextPages[0].data)
    subscriber.cancel()
  }

  // MARK: - Test helpers

  private func createPager() -> GraphQLQueryPager<PaginationOutput<Query, Query>> {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return .init(pager: GraphQLQueryPagerCoordinator<Query, Query>(
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
          "after": pageInfo.endCursor ?? .null,
        ]
        return nextQuery
      }
    ))
  }

  private func fetchFirstPage<T>(pager: GraphQLQueryPager<T>) async {
    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1)
  }

  private func fetchSecondPage<T>(pager: GraphQLQueryPager<T>) async throws {
    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    try await pager.loadNext()
    await fulfillment(of: [serverExpectation], timeout: 1)
  }
}
