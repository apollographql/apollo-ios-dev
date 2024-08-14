import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Combine
import XCTest

@testable import ApolloPagination

final class BidirectionalPaginationTests: XCTestCase, CacheDependentTesting {

  private typealias Query = MockQuery<Mocks.Hero.BidirectionalFriendsQuery>

  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  var cache: (any NormalizedCache)!
  var server: MockGraphQLServer!
  var client: ApolloClient!
  var cancellables: [AnyCancellable] = []

  override func setUpWithError() throws {
    try super.setUpWithError()

    cache = try makeNormalizedCache()
    let store = ApolloStore(cache: cache)

    server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(server: server, store: store)

    client = ApolloClient(networkTransport: networkTransport, store: store)
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object = IDCacheKeyProvider.resolver
  }

  override func tearDownWithError() throws {
    cache = nil
    server = nil
    client = nil
    cancellables.removeAll()

    try super.tearDownWithError()
  }

  // MARK: - Test Helpers

  private func createPager() -> AsyncGraphQLQueryPagerCoordinator<Query, Query> {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 1, "after": "Y3Vyc29yMw==", "before": GraphQLNullable<String>.null]
    return AsyncGraphQLQueryPagerCoordinator<Query, Query>(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: .main,
      extractPageInfo: { data in
        switch data {
        case .initial(let data, _), .paginated(let data, _):
          return CursorBasedPagination.Bidirectional(
            hasNext: data.hero.friendsConnection.pageInfo.hasNextPage,
            endCursor: data.hero.friendsConnection.pageInfo.endCursor,
            hasPrevious: data.hero.friendsConnection.pageInfo.hasPreviousPage,
            startCursor: data.hero.friendsConnection.pageInfo.startCursor
          )
        }
      },
      pageResolver: { pageInfo, direction in
        switch direction {
        case .next:
          let nextQuery = Query()
          nextQuery.__variables = [
            "id": "2001",
            "first": 1,
            "after": pageInfo.endCursor,
            "before": GraphQLNullable<String>.null,
          ]
          return nextQuery
        case .previous:
          let previousQuery = Query()
          previousQuery.__variables = [
            "id": "2001",
            "first": 1,
            "before": pageInfo.startCursor,
            "after": GraphQLNullable<String>.null,
          ]
          return previousQuery
        }
      }
    )
  }

  // MARK: - AsyncGraphQLQueryPager tests

  func test_fetchMultiplePages_async() async throws {
    let pager = createPager()
    let serverExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForFirstFetchInMiddleOfList(server: server)

    var results: [Result<PaginationOutput<Query, Query>, any Error>] = []
    let firstPageExpectation = expectation(description: "First page")
    var subscription = await pager.subscribe(onUpdate: { _ in
      firstPageExpectation.fulfill()
    })
    await pager.fetch()
    await fulfillment(of: [serverExpectation, firstPageExpectation], timeout: 1)
    subscription.cancel()
    var result = try await XCTUnwrapping(await pager.currentValue)
    results.append(result)
    XCTAssertSuccessResult(result) { output in
      XCTAssertTrue(output.nextPages.isEmpty)
      XCTAssertEqual(output.initialPage?.data?.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(output.initialPage?.data?.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(output.initialPage?.source, .server)
    }

    let secondPageExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForLastPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })

    try await pager.loadNext()
    await fulfillment(of: [secondPageExpectation, secondPageFetch], timeout: 1)
    subscription.cancel()

    result = try await XCTUnwrapping(await pager.currentValue)
    results.append(result)

    try XCTAssertSuccessResult(result) { output in
      // Assert first page is unchanged
      XCTAssertEqual(try? results.first?.get().initialPage, try? results.last?.get().initialPage)

      XCTAssertFalse(output.nextPages.isEmpty)
      XCTAssertEqual(output.nextPages.count, 1)
      XCTAssertTrue(output.previousPages.isEmpty)
      XCTAssertEqual(output.previousPages.count, 0)
      let page = try XCTUnwrap(output.nextPages.first)
      XCTAssertEqual(page.data?.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(page.source, .server)
    }
    var previousCount = await pager.previousPageVarMap.values.count
    XCTAssertEqual(previousCount, 0)
    var nextCount = await pager.nextPageVarMap.values.count
    XCTAssertEqual(nextCount, 1)

    let previousPageExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForPreviousPage(server: server)
    let previousPageFetch = expectation(description: "Previous Page")
    previousPageFetch.assertForOverFulfill = false
    previousPageFetch.expectedFulfillmentCount = 2
    subscription = await pager.subscribe(onUpdate: { _ in
      previousPageFetch.fulfill()
    })

    try await pager.loadPrevious()
    await fulfillment(of: [previousPageExpectation, previousPageFetch], timeout: 1)
    subscription.cancel()

    result = try await XCTUnwrapping(await pager.currentValue)
    results.append(result)

    try XCTAssertSuccessResult(result) { output in
      // Assert first page is unchanged
      XCTAssertEqual(try? results.first?.get().initialPage, try? results.last?.get().initialPage)

      XCTAssertFalse(output.nextPages.isEmpty)
      XCTAssertEqual(output.nextPages.count, 1)
      XCTAssertFalse(output.previousPages.isEmpty)
      XCTAssertEqual(output.previousPages.count, 1)
      let page = try XCTUnwrap(output.previousPages.first)
      XCTAssertEqual(page.data?.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(page.source, .server)
    }
    previousCount = await pager.previousPageVarMap.values.count
    XCTAssertEqual(previousCount, 1)
    nextCount = await pager.nextPageVarMap.values.count
    XCTAssertEqual(nextCount, 1)
  }

  func test_loadAll_async() async throws {
    let pager = createPager()

    let firstPageExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForFirstFetchInMiddleOfList(server: server)
    let previousPageExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForPreviousPage(server: server)
    let lastPageExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForLastPage(server: server)

    let loadAllExpectation = expectation(description: "Load all pages")
    await pager.subscribe(onUpdate: { _ in
      loadAllExpectation.fulfill()
    }).store(in: &cancellables)
    try await pager.loadAll()
    await fulfillment(
      of: [firstPageExpectation, lastPageExpectation, previousPageExpectation, loadAllExpectation],
      timeout: 5
    )

    let result = try await XCTUnwrapping(try await pager.currentValue?.get())
    XCTAssertFalse(result.previousPages.isEmpty)
    XCTAssertEqual(result.initialPage?.data?.hero.friendsConnection.friends.count, 1)
    XCTAssertFalse(result.nextPages.isEmpty)
    let friends = (
      result.previousPages.compactMap(\.data?.hero.friendsConnection.friends)
        + result.nextPages.compactMap(\.data?.hero.friendsConnection.friends)
    ).flatMap { $0 } + (result.initialPage?.data?.hero.friendsConnection.friends ?? [])

    XCTAssertEqual(Set(friends).count, 3)
  }

  // MARK: - GraphQLQueryPager tests

  func test_fetchMultiplePages() async throws {
    let pager = GraphQLQueryPagerCoordinator(pager: createPager())
    let serverExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForFirstFetchInMiddleOfList(server: server)

    var results: [Result<PaginationOutput<Query, Query>, any Error>] = []
    let firstPageExpectation = expectation(description: "First page")
    var subscription = await pager.publisher.sink { _ in
      firstPageExpectation.fulfill()
    }
    pager.fetch()
    await fulfillment(of: [serverExpectation, firstPageExpectation], timeout: 1)
    subscription.cancel()
    var result = try await XCTUnwrapping(await pager.pager.currentValue)
    results.append(result)
    XCTAssertSuccessResult(result) { output in
      XCTAssertTrue(output.nextPages.isEmpty)
      XCTAssertEqual(output.initialPage?.data?.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(output.initialPage?.data?.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(output.initialPage?.source, .server)
    }

    let secondPageExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForLastPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    subscription = await pager.publisher.sink { _ in
      secondPageFetch.fulfill()
    }

    pager.loadNext()
    await fulfillment(of: [secondPageExpectation, secondPageFetch], timeout: 1)
    subscription.cancel()

    result = try await XCTUnwrapping(await pager.pager.currentValue)
    results.append(result)

    try XCTAssertSuccessResult(result) { output in
      // Assert first page is unchanged
      XCTAssertEqual(try? results.first?.get().initialPage, try? results.last?.get().initialPage)

      XCTAssertFalse(output.nextPages.isEmpty)
      XCTAssertEqual(output.nextPages.count, 1)
      XCTAssertTrue(output.previousPages.isEmpty)
      XCTAssertEqual(output.previousPages.count, 0)
      let page = try XCTUnwrap(output.nextPages.first)
      XCTAssertEqual(page.data?.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(page.source, .server)
    }

    let previousPageExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForPreviousPage(server: server)
    let previousPageFetch = expectation(description: "Previous Page")
    previousPageFetch.assertForOverFulfill = false
    previousPageFetch.expectedFulfillmentCount = 2
    subscription = await pager.publisher.sink { _ in
      previousPageFetch.fulfill()
    }

    pager.loadPrevious()
    await fulfillment(of: [previousPageExpectation, previousPageFetch], timeout: 1)
    subscription.cancel()

    result = try await XCTUnwrapping(await pager.pager.currentValue)
    results.append(result)

    try XCTAssertSuccessResult(result) { output in
      // Assert first page is unchanged
      XCTAssertEqual(try? results.first?.get().initialPage, try? results.last?.get().initialPage)

      XCTAssertFalse(output.nextPages.isEmpty)
      XCTAssertEqual(output.nextPages.count, 1)
      XCTAssertFalse(output.previousPages.isEmpty)
      XCTAssertEqual(output.previousPages.count, 1)
      let page = try XCTUnwrap(output.previousPages.first)
      XCTAssertEqual(page.data?.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(page.source, .server)
    }
  }

  func test_loadAll() async throws {
    let pager = GraphQLQueryPagerCoordinator(pager: createPager())

    let firstPageExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForFirstFetchInMiddleOfList(server: server)
    let previousPageExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForPreviousPage(server: server)
    let lastPageExpectation = Mocks.Hero.BidirectionalFriendsQuery.expectationForLastPage(server: server)

    let loadAllExpectation = expectation(description: "Load all pages")
    pager.subscribe(onUpdate: { _ in
      loadAllExpectation.fulfill()
    })
    pager.loadAll()
    await fulfillment(
      of: [firstPageExpectation, lastPageExpectation, previousPageExpectation, loadAllExpectation],
      timeout: 5
    )

    let result = try await XCTUnwrapping(try await pager.pager.currentValue?.get())
    XCTAssertFalse(result.previousPages.isEmpty)
    XCTAssertEqual(result.initialPage?.data?.hero.friendsConnection.friends.count, 1)
    XCTAssertFalse(result.nextPages.isEmpty)

    let friends = (
      result.previousPages.compactMap(\.data?.hero.friendsConnection.friends)
        + result.nextPages.compactMap(\.data?.hero.friendsConnection.friends)
    ).flatMap { $0 } + (result.initialPage?.data?.hero.friendsConnection.friends ?? [])

    XCTAssertEqual(Set(friends).count, 3)
  }
}
