import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
@preconcurrency import Combine
import XCTest

@testable import ApolloPagination

final class ReversePaginationTests: XCTestCase, CacheDependentTesting {

  private typealias Query = MockQuery<Mocks.Hero.ReverseFriendsQuery>

  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  var store: ApolloStore!
  var server: MockGraphQLServer!
  var client: ApolloClient!
  var cancellables: [AnyCancellable] = []

  override func setUp() async throws {
    try await super.setUp()

    store = try await makeTestStore()

    server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(mockServer: server, store: store)

    client = ApolloClient(networkTransport: networkTransport, store: store)
    await MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)
  }

  override func tearDownWithError() throws {
    store = nil
    server = nil
    client = nil
    cancellables.forEach { $0.cancel() }
    cancellables = []

    try super.tearDownWithError()
  }

  func test_fetchMultiplePages() async throws {
    let pager = createPager()

    let serverExpectation = await Mocks.Hero.ReverseFriendsQuery.expectationForLastItem(server: server)

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

    let secondPageExpectation = await Mocks.Hero.ReverseFriendsQuery.expectationForPreviousItem(server: server)
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

    let firstPageExpectation = await Mocks.Hero.ReverseFriendsQuery.expectationForLastItem(server: server)
    let lastPageExpectation = await Mocks.Hero.ReverseFriendsQuery.expectationForPreviousItem(server: server)
    let loadAllExpectation = expectation(description: "Load all pages")
    await pager.subscribe(onUpdate: { _ in
      loadAllExpectation.fulfill()
    }).store(in: &cancellables)
    try await pager.loadAll()
    await fulfillment(of: [firstPageExpectation, lastPageExpectation, loadAllExpectation], timeout: 5)
  }

  private func createPager() -> GraphQLQueryPagerCoordinator<Query, Query> {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "before": "Y3Vyc29yMw=="]
    return GraphQLQueryPagerCoordinator<Query, Query>(
      client: client,
      initialQuery: initialQuery,      
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
