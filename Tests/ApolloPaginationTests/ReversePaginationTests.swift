import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Combine
import XCTest

@testable import ApolloPagination

final class ReversePaginationTests: XCTestCase, CacheDependentTesting {

  private typealias Query = MockQuery<Mocks.Hero.ReverseFriendsQuery>

  var cacheType: TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  var cache: NormalizedCache!
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
    cancellables.forEach { $0.cancel() }
    cancellables = []

    try super.tearDownWithError()
  }

  func test_fetchMultiplePages() async throws {
    let pager = createPager()

    let serverExpectation = Mocks.Hero.ReverseFriendsQuery.expectationForLastItem(server: server)

    var results: [Result<(Query.Data, [Query.Data], UpdateSource), Error>] = []
    let firstPageExpectation = expectation(description: "First page")
    var subscription = await pager.subscribe(onUpdate: { _ in
      firstPageExpectation.fulfill()
    })
    await pager.fetch()
    await fulfillment(of: [serverExpectation, firstPageExpectation], timeout: 1)
    subscription.cancel()
    var result = try await XCTUnwrapping(await pager.currentValue)
    results.append(result)
    XCTAssertSuccessResult(result) { value in
      let (first, next, source) = value
      XCTAssertTrue(next.isEmpty)
      XCTAssertEqual(first.hero.friendsConnection.friends.count, 2)
      XCTAssertEqual(first.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(source, .fetch)
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

    try XCTAssertSuccessResult(result) { value in
      let (_, next, source) = value
      // Assert first page is unchanged
      XCTAssertEqual(try? results.first?.get().0, try? results.last?.get().0)

      XCTAssertFalse(next.isEmpty)
      XCTAssertEqual(next.count, 1)
      let page = try XCTUnwrap(next.first)
      XCTAssertEqual(page.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(source, .fetch)
    }
    let count = await pager.varMap.values.count
    XCTAssertEqual(count, 1)
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

  private func createPager() -> GraphQLQueryPager<Query, Query>.Actor {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "before": "Y3Vyc29yMw=="]
    return GraphQLQueryPager<Query, Query>.Actor(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: { data in
        switch data {
        case .initial(let data), .paginated(let data):
          return CursorBasedPagination.ReversePagination(
            hasPrevious: data.hero.friendsConnection.pageInfo.hasPreviousPage,
            startCursor: data.hero.friendsConnection.pageInfo.startCursor
          )
        }
      },
      nextPageResolver: { pageInfo in
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
