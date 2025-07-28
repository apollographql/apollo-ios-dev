import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
@preconcurrency import Combine
import XCTest

@testable import ApolloPagination

final class ForwardPaginationTests: XCTestCase, CacheDependentTesting {

  private typealias Query = MockQuery<Mocks.Hero.FriendsQuery>

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

    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

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

    let secondPageExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
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
    let previousCount = await pager.previousPageVarMap.values.count
    XCTAssertEqual(previousCount, 0)
    let nextCount = await pager.nextPageVarMap.values.count
    XCTAssertEqual(nextCount, 1)
  }

  func test_variableMapping() async throws {
    let pager = createPager()

    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.fetch()
    await fulfillment(of: [serverExpectation])

    let secondPageExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })
    try await pager.loadNext(fetchBehavior: .NetworkOnly)
    await fulfillment(of: [secondPageExpectation, secondPageFetch])
    subscription.cancel()

    // Test Variable Mapping

    let nextQuery = Query()
    nextQuery.__variables = [
      "id": "2001",
      "first": 2,
      "after": "Y3Vyc29yMg==",
    ]

    let expectedVariables = PageVariables(nextQuery.__variables!)
    let actualVariables = try await XCTUnwrapping(await pager.nextPageVarMap.keys.first)

    XCTAssertEqual(expectedVariables, actualVariables)
  }

  func test_paginationState() async throws {
    let pager = createPager()

    var nextPageInfo = await pager.nextPageInfo
    XCTAssertNil(nextPageInfo)

    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.fetch()
    await fulfillment(of: [serverExpectation])

    nextPageInfo = try await XCTUnwrapping(await pager.nextPageInfo)
    var page = try XCTUnwrap(nextPageInfo as? CursorBasedPagination.Forward)
    let expectedFirstPage = CursorBasedPagination.Forward(
      hasNext: true,
      endCursor: "Y3Vyc29yMg=="
    )
    XCTAssertEqual(page, expectedFirstPage)

    let secondPageExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })
    try await pager.loadNext(fetchBehavior: .NetworkOnly)
    await fulfillment(of: [secondPageExpectation, secondPageFetch])
    subscription.cancel()

    nextPageInfo = try await XCTUnwrapping(await pager.nextPageInfo)
    page = try XCTUnwrap(nextPageInfo as? CursorBasedPagination.Forward)
    let expectedSecondPage = CursorBasedPagination.Forward(
      hasNext: false,
      endCursor: "Y3Vyc29yMw=="
    )

    XCTAssertEqual(page, expectedSecondPage)
  }

  func test_fetchMultiplePages_mutateHero() async throws {
    let pager = createPager()

    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    let firstPageExpectation = expectation(description: "First page")
    var subscription = await pager.subscribe(onUpdate: { _ in
      firstPageExpectation.fulfill()
    })
    await pager.fetch()
    await fulfillment(of: [serverExpectation, firstPageExpectation], timeout: 1)
    subscription.cancel()
    let result = try await XCTUnwrapping(await pager.currentValue)
    XCTAssertSuccessResult(result) { output in
      XCTAssertTrue(output.nextPages.isEmpty)
      XCTAssertEqual(output.initialPage?.data?.hero.friendsConnection.friends.count, 2)
      XCTAssertEqual(output.initialPage?.data?.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(output.initialPage?.source, .server)
    }

    let secondPageExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })

    try await pager.loadNext()
    await fulfillment(of: [secondPageExpectation, secondPageFetch], timeout: 1)
    subscription.cancel()
    let newResult = try await XCTUnwrapping(await pager.currentValue)
    try XCTAssertSuccessResult(newResult) { output in
      // Assert first page is unchanged
      XCTAssertEqual(try? result.get().initialPage, try? newResult.get().initialPage)
      XCTAssertFalse(output.nextPages.isEmpty)
      XCTAssertEqual(output.nextPages.count, 1)
      let page = try XCTUnwrap(output.nextPages.first)
      XCTAssertEqual(page.data?.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(page.source, .server)
    }
    let count = await pager.nextPageVarMap.values.count
    XCTAssertEqual(count, 1)

    let transactionExpectation = expectation(description: "Writing to cache")
    let mutationExpectation = expectation(description: "Mutation")
    mutationExpectation.expectedFulfillmentCount = 3 // once for subscribe, 2 for pages refreshing
    await pager.subscribe(onUpdate: { _ in mutationExpectation.fulfill() }).store(in: &cancellables)
    try await client.store.withinReadWriteTransaction { transaction in
      let cacheMutation = MockLocalCacheMutation<Mocks.Hero.NameCacheMutation>()
      cacheMutation.__variables = ["id": "2001"]
      try! await transaction.update(cacheMutation) { data in
        data.hero?.name = "C3PO"
        transactionExpectation.fulfill()
      }
    }
    await fulfillment(of: [transactionExpectation, mutationExpectation])
    let finalResult = try await XCTUnwrapping(await pager.currentValue)
    XCTAssertSuccessResult(finalResult) { output in
      XCTAssertEqual(output.initialPage?.data?.hero.name, "C3PO")
      XCTAssertEqual(output.nextPages.count, 1)
      XCTAssertEqual(output.nextPages.first?.data?.hero.name, "C3PO")
    }
  }

  func test_loadAll() async throws {
    let pager = createPager()

    let firstPageExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    let lastPageExpectation = await Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let loadAllExpectation = expectation(description: "Load all pages")
    await pager.subscribe(onUpdate: { _ in
      loadAllExpectation.fulfill()
    }).store(in: &cancellables)
    try await pager.loadAll()
    await fulfillment(of: [firstPageExpectation, lastPageExpectation, loadAllExpectation], timeout: 5)
  }

  func test_failingFetch_finishes() async throws {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "flirst": 2, "after": GraphQLNullable<String>.none]
    let pager = GraphQLQueryPagerCoordinator<Query, Query>(
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
          "after": pageInfo.endCursor,
        ]
        return nextQuery
      }
    )
    let lastPageExpectation = await Mocks.Hero.FriendsQuery.failingExpectation(server: server)

    let cancellable = await pager.subscribe { result in
      try? XCTAssertThrowsError(result.get())
    }
    await pager.fetch()
    await fulfillment(of: [lastPageExpectation])
    cancellable.cancel()
  }

  private func createPager() -> GraphQLQueryPagerCoordinator<Query, Query> {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return GraphQLQueryPagerCoordinator<Query, Query>(
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
          "after": pageInfo.endCursor,
        ]
        return nextQuery
      }
    )
  }
}

private extension Mocks.Hero.FriendsQuery {
  static func failingExpectation(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "flirst": 2, "after": GraphQLNullable<String>.none]
    return await server.expect(query) { _ in
      let pageInfo: [AnyHashable: AnyHashable] = [
        "__typename": "PageInfo",
        "endCursor": "Y3Vyc29yMg==",
        "hasNextPage": true,
      ]
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Luke Skywalker",
          "id": "1000",
        ],
        [
          "__typename": "Human",
          "name": "Han Solo",
          "id": "1002",
        ],
      ]
      let friendsConnection = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data = [
        "hero": hero
      ]

      return [
        "data": data as JSONValue
      ]
    }
  }
}
