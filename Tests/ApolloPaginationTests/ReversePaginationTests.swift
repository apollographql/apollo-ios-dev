import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Combine
import XCTest

@testable import ApolloPagination

final class ReversePaginationTests: XCTestCase, CacheDependentTesting {

  private typealias Query = MockQuery<Mocks.Hero.ReverseFriendsQuery>

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

  func test_fetchMultiplePages() async throws {
    let pager = createPager()

    let serverExpectation = Mocks.Hero.ReverseFriendsQuery.expectationForLastItem(server: server)

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
      XCTAssertEqual(output.initialPage?.data?.hero.friendsConnection.friends.count, 2)
      XCTAssertEqual(output.initialPage?.data?.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(output.initialPage?.source, .server)
    }

    let secondPageExpectation = Mocks.Hero.ReverseFriendsQuery.expectationForPreviousItem(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })

    try await pager.loadPrevious()
    await fulfillment(of: [secondPageExpectation, secondPageFetch], timeout: 1)
    subscription.cancel()

    result = try await XCTUnwrapping(await pager.currentValue)
    results.append(result)

    try XCTAssertSuccessResult(result) { output in
      // Assert first page is unchanged
      let first = try? results.first?.get().initialPage
      let last = try? results.last?.get().initialPage
      print("""
        \(#function) - equality
        equal: \(first == last)
        data equal: \(first?.data == last?.data)
        data.hero equal: \(first?.data?.hero == last?.data?.hero)
        data.hero.__typename equal: \(first?.data?.hero.__typename == last?.data?.hero.__typename)
        data.hero.id equal: \(first?.data?.hero.id == last?.data?.hero.id)
        data.hero.name equal: \(first?.data?.hero.name == last?.data?.hero.name)
        data.hero.friendsConnection equal: \(first?.data?.hero.friendsConnection == last?.data?.hero.friendsConnection)
        hashes - lhs:\(first?.data?.hero.friendsConnection.hashValue) rhs:\(last?.data?.hero.friendsConnection.hashValue)
        data.hero.friendsConnection.__data equal: \(first?.data?.hero.friendsConnection.__data == last?.data?.hero.friendsConnection.__data)
        data.hero.friendsConnection.__data._data equal: \(first?.data?.hero.friendsConnection.__data._data == last?.data?.hero.friendsConnection.__data._data)
        data.hero.friendsConnection.__data._fulfilledFragments equal: \(first?.data?.hero.friendsConnection.__data._fulfilledFragments == last?.data?.hero.friendsConnection.__data._fulfilledFragments)
        data.hero.friendsConnection.__data._deferredFragments equal: \(first?.data?.hero.friendsConnection.__data._deferredFragments == last?.data?.hero.friendsConnection.__data._deferredFragments)
        data.hero.friendsConnection.__typename equal: \(first?.data?.hero.friendsConnection.__typename == last?.data?.hero.friendsConnection.__typename)
        data.hero.friendsConnection.totalCount equal: \(first?.data?.hero.friendsConnection.totalCount == last?.data?.hero.friendsConnection.totalCount)
        data.hero.friendsConnection.friends equal: \(first?.data?.hero.friendsConnection.friends == last?.data?.hero.friendsConnection.friends)
        data.hero.friendsConnection.pageInfo equal: \(first?.data?.hero.friendsConnection.pageInfo == last?.data?.hero.friendsConnection.pageInfo)
        """)
      XCTAssertEqual(try? results.first?.get().initialPage, try? results.last?.get().initialPage)

      XCTAssertFalse(output.previousPages.isEmpty)
      XCTAssertEqual(output.previousPages.count, 1)
      XCTAssertTrue(output.nextPages.isEmpty)
      XCTAssertEqual(output.nextPages.count, 0)
      let page = try XCTUnwrap(output.previousPages.first)
      XCTAssertEqual(page.data?.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(page.source, .server)
    }
    let previousCount = await pager.previousPageVarMap.values.count
    XCTAssertEqual(previousCount, 1)
    let nextCount = await pager.nextPageVarMap.values.count
    XCTAssertEqual(nextCount, 0)
  }

  func test_loadAll() async throws {
    let pager = createPager()

    let firstPageExpectation = Mocks.Hero.ReverseFriendsQuery.expectationForLastItem(server: server)
    let lastPageExpectation = Mocks.Hero.ReverseFriendsQuery.expectationForPreviousItem(server: server)
    let loadAllExpectation = expectation(description: "Load all pages")
    await pager.subscribe(onUpdate: { _ in
      loadAllExpectation.fulfill()
    }).store(in: &cancellables)
    try await pager.loadAll()
    await fulfillment(of: [firstPageExpectation, lastPageExpectation, loadAllExpectation], timeout: 5)
  }

  private func createPager() -> AsyncGraphQLQueryPagerCoordinator<Query, Query> {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "before": "Y3Vyc29yMw=="]
    return AsyncGraphQLQueryPagerCoordinator<Query, Query>(
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
        let nextQuery = Query()
        nextQuery.__variables = [
          "id": "2001",
          "first": 2,
          "before": pageInfo.startCursor,
        ]
        return nextQuery
      }
    )
  }
}
