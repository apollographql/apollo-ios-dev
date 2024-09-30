import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Combine
import XCTest

@testable import ApolloPagination

final class AsyncGraphQLQueryPagerCoordinatorTests: XCTestCase, CacheDependentTesting {
  private typealias ReverseQuery = MockQuery<Mocks.Hero.ReverseFriendsQuery>
  private typealias ForwardQuery = MockQuery<Mocks.Hero.FriendsQuery>

  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  var cache: (any NormalizedCache)!
  var server: MockGraphQLServer!
  var client: ApolloClient!
  var cancellables: [AnyCancellable] = []

  @MainActor
  override func setUp() async throws {
    try await super.setUp()

    cache = try await makeNormalizedCache()
    let store = ApolloStore(cache: cache)

    server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(server: server, store: store)

    client = ApolloClient(networkTransport: networkTransport, store: store)
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)
  }

  override func tearDownWithError() throws {
    cache = nil
    server = nil
    client = nil
    cancellables.forEach { $0.cancel() }
    cancellables = []

    try super.tearDownWithError()
  }

  func test_canLoadMore() async throws {
    let pager = createForwardPager()

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.fetch()
    await fulfillment(of: [serverExpectation])

    var canLoadMore = await pager.canLoadNext
    XCTAssertTrue(canLoadMore)

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })
    try await pager.loadNext()
    await fulfillment(of: [secondPageExpectation, secondPageFetch])
    subscription.cancel()
    canLoadMore = await pager.canLoadNext
    XCTAssertFalse(canLoadMore)
  }

  func test_canLoadPrevious() async throws {
    let pager = createReversePager()

    let serverExpectation = Mocks.Hero.ReverseFriendsQuery.expectationForLastItem(server: server)

    await pager.fetch()
    await fulfillment(of: [serverExpectation])

    var canLoadMore = await pager.canLoadPrevious
    XCTAssertTrue(canLoadMore)

    let secondPageExpectation = Mocks.Hero.ReverseFriendsQuery.expectationForPreviousItem(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })
    try await pager.loadPrevious()
    await fulfillment(of: [secondPageExpectation, secondPageFetch])
    subscription.cancel()
    canLoadMore = await pager.canLoadPrevious
    XCTAssertFalse(canLoadMore)
  }

  @available(iOS 16.0, macOS 13.0, *)
  func test_actor_canResetMidflight() async throws {
    server.customDelay = .milliseconds(150)
    let pager = createForwardPager()
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.subscribe(onUpdate: { _ in
      XCTFail("We should never get results back")
    }).store(in: &cancellables)

    Task {
      try await pager.loadAll()
    }

    Task {
      try? await Task.sleep(for: .milliseconds(10))
      await pager.reset()
    }

    await fulfillment(of: [serverExpectation], timeout: 1.0)
  }

  @available(iOS 16.0, macOS 13.0, *)
  func test__reset__loadingState() async throws {
    server.customDelay = .milliseconds(150)
    let pager = createForwardPager()
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.subscribe(onUpdate: { _ in
      XCTFail("We should never get results back")
    }).store(in: &cancellables)

    Task {
      try await pager.loadAll()
    }

    Task {
      try? await Task.sleep(for: .milliseconds(10))
      await pager.reset()
    }

    await fulfillment(of: [serverExpectation], timeout: 1.0)
    async let isLoadingAll = pager.isLoadingAll
    async let isFetching = pager.isFetching
    let loadingStates = await [isFetching, isLoadingAll]
    loadingStates.forEach { XCTAssertFalse($0) }
  }

  @available(iOS 16.0, macOS 13.0, *)
  func test__reset__midflight_isFetching_isFalse() async throws {
    server.customDelay = .milliseconds(1)
    let pager = createForwardPager()
    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.fetch()
    await fulfillment(of: [serverExpectation], timeout: 1.0)

    server.customDelay = .seconds(3)
    Task {
      try? await pager.loadNext()
    }
    let cancellationExpectation = expectation(description: "finished cancellation")
    Task {
      try? await Task.sleep(for: .milliseconds(50))
      await pager.reset()
      cancellationExpectation.fulfill()
    }

    await fulfillment(of: [cancellationExpectation])
    let isFetching = await pager.isFetching
    XCTAssertFalse(isFetching)
  }

  private func createReversePager() -> AsyncGraphQLQueryPagerCoordinator<ReverseQuery, ReverseQuery> {
    let initialQuery = ReverseQuery()
    initialQuery.__variables = ["id": "2001", "first": 2, "before": "Y3Vyc29yMw=="]
    return AsyncGraphQLQueryPagerCoordinator<ReverseQuery, ReverseQuery>(
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
          "before": pageInfo.startCursor,
        ]
        return nextQuery
      }
    )
  }

  private func createForwardPager() -> AsyncGraphQLQueryPagerCoordinator<ForwardQuery, ForwardQuery> {
    let initialQuery = ForwardQuery()
    initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return AsyncGraphQLQueryPagerCoordinator<ForwardQuery, ForwardQuery>(
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
        let nextQuery = ForwardQuery()
        nextQuery.__variables = [
          "id": "2001",
          "first": 2,
          "after": pageInfo.endCursor,
        ]
        return nextQuery
      }
    )
  }
}
