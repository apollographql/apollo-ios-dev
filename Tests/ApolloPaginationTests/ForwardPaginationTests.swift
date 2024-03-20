import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Combine
import XCTest

@testable import ApolloPagination

final class ForwardPaginationTests: XCTestCase, CacheDependentTesting {

  private typealias Query = MockQuery<Mocks.Hero.FriendsQuery>

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

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    var results: [Result<(PaginationOutput<Query, Query>, UpdateSource), Error>] = []
    let firstPageExpectation = expectation(description: "First page")
    var subscription = await pager.subscribe(onUpdate: { _ in
      firstPageExpectation.fulfill()
    })
    await pager.fetch()
    await fulfillment(of: [serverExpectation, firstPageExpectation], timeout: 1)
    subscription.cancel()
    var result = try await XCTUnwrapping(await pager.currentValue)
    results.append(result)
    XCTAssertSuccessResult(result) { (output, source) in
      XCTAssertTrue(output.nextPages.isEmpty)
      XCTAssertEqual(output.initialPage.hero.friendsConnection.friends.count, 2)
      XCTAssertEqual(output.initialPage.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(source, .fetch)
    }

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
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

    try XCTAssertSuccessResult(result) { (output, source) in
      // Assert first page is unchanged
      XCTAssertEqual(try? results.first?.get().0.initialPage, try? results.last?.get().0.initialPage)

      XCTAssertFalse(output.nextPages.isEmpty)
      XCTAssertEqual(output.nextPages.count, 1)
      XCTAssertTrue(output.previousPages.isEmpty)
      XCTAssertEqual(output.previousPages.count, 0)
      let page = try XCTUnwrap(output.nextPages.first)
      XCTAssertEqual(page.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(source, .fetch)
    }
    let previousCount = await pager.previousPageVarMap.values.count
    XCTAssertEqual(previousCount, 0)
    let nextCount = await pager.nextPageVarMap.values.count
    XCTAssertEqual(nextCount, 1)
  }

  func test_variableMapping() async throws {
    let pager = createPager()

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.fetch()
    await fulfillment(of: [serverExpectation])

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })
    try await pager.loadNext(cachePolicy: .fetchIgnoringCacheData)
    await fulfillment(of: [secondPageExpectation, secondPageFetch])
    subscription.cancel()

    // Test Variable Mapping

    let nextQuery = Query()
    nextQuery.__variables = [
      "id": "2001",
      "first": 2,
      "after": "Y3Vyc29yMg==",
    ]

    let expectedVariables = Set(nextQuery.__variables?.values.compactMap { $0._jsonEncodableValue?._jsonValue } ?? [])
    let actualVariables = try await XCTUnwrapping(await pager.nextPageVarMap.keys.first)

    XCTAssertEqual(expectedVariables.count, actualVariables.count)
    XCTAssertEqual(expectedVariables.count, 3)

    XCTAssertEqual(expectedVariables, actualVariables)
  }

  func test_paginationState() async throws {
    let pager = createPager()

    var nextPageInfo = await pager.nextPageInfo
    XCTAssertNil(nextPageInfo)

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.fetch()
    await fulfillment(of: [serverExpectation])

    nextPageInfo = try await XCTUnwrapping(await pager.nextPageInfo)
    var page = try XCTUnwrap(nextPageInfo as? CursorBasedPagination.Forward)
    let expectedFirstPage = CursorBasedPagination.Forward(
      hasNext: true,
      endCursor: "Y3Vyc29yMg=="
    )
    XCTAssertEqual(page, expectedFirstPage)

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })
    try await pager.loadNext(cachePolicy: .fetchIgnoringCacheData)
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

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    let firstPageExpectation = expectation(description: "First page")
    var subscription = await pager.subscribe(onUpdate: { _ in
      firstPageExpectation.fulfill()
    })
    await pager.fetch()
    await fulfillment(of: [serverExpectation, firstPageExpectation], timeout: 1)
    subscription.cancel()
    let result = try await XCTUnwrapping(await pager.currentValue)
    XCTAssertSuccessResult(result) { (output, source) in
      XCTAssertTrue(output.nextPages.isEmpty)
      XCTAssertEqual(output.initialPage.hero.friendsConnection.friends.count, 2)
      XCTAssertEqual(output.initialPage.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(source, .fetch)
    }

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })

    try await pager.loadNext()
    await fulfillment(of: [secondPageExpectation, secondPageFetch], timeout: 1)
    subscription.cancel()
    let newResult = try await XCTUnwrapping(await pager.currentValue)
    try XCTAssertSuccessResult(newResult) { (output, source) in
      // Assert first page is unchanged
      XCTAssertEqual(try? result.get().0.initialPage, try? newResult.get().0.initialPage)
      XCTAssertFalse(output.nextPages.isEmpty)
      XCTAssertEqual(output.nextPages.count, 1)
      let page = try XCTUnwrap(output.nextPages.first)
      XCTAssertEqual(page.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(source, .fetch)
    }
    let count = await pager.nextPageVarMap.values.count
    XCTAssertEqual(count, 1)

    let transactionExpectation = expectation(description: "Writing to cache")
    let mutationExpectation = expectation(description: "Mutation")
    mutationExpectation.expectedFulfillmentCount = 3 // once for subscribe, 2 for pages refreshing
    await pager.subscribe(onUpdate: { _ in mutationExpectation.fulfill() }).store(in: &cancellables)
    client.store.withinReadWriteTransaction { transaction in
      let cacheMutation = MockLocalCacheMutation<Mocks.Hero.NameCacheMutation>()
      cacheMutation.__variables = ["id": "2001"]
      try! transaction.update(cacheMutation) { data in
        data.hero?.name = "C3PO"
        transactionExpectation.fulfill()
      }
    }
    await fulfillment(of: [transactionExpectation, mutationExpectation])
    let finalResult = try await XCTUnwrapping(await pager.currentValue)
    XCTAssertSuccessResult(finalResult) { (output, _) in
      XCTAssertEqual(output.initialPage.hero.name, "C3PO")
      XCTAssertEqual(output.nextPages.count, 1)
      XCTAssertEqual(output.nextPages.first?.hero.name, "C3PO")
    }
  }

  func test_loadAll() async throws {
    let pager = createPager()

    let firstPageExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)
    let lastPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
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
    let pager = AsyncGraphQLQueryPagerCoordinator<Query, Query>(
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
    let lastPageExpectation = Mocks.Hero.FriendsQuery.failingExpectation(server: server)

    let cancellable = await pager.subscribe { result in
      try? XCTAssertThrowsError(result.get())
    }
    await pager.fetch()
    await fulfillment(of: [lastPageExpectation])
    cancellable.cancel()
  }

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
}

private extension Mocks.Hero.FriendsQuery {
  static func failingExpectation(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "flirst": 2, "after": GraphQLNullable<String>.none]
    return server.expect(query) { _ in
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
      let friendsConnection: [String: AnyHashable] = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data
      ]
    }
  }
}
