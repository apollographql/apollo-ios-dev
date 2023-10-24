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

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })

    try await pager.loadMore()
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

  func test_variableMapping() async throws {
    let pager = createPager()

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.fetch()
    await fulfillment(of: [serverExpectation])

    let result = try await XCTUnwrapping(await pager.currentValue)
    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    let subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })
    try await pager.loadMore(cachePolicy: .fetchIgnoringCacheData)
    await fulfillment(of: [secondPageExpectation, secondPageFetch])
    subscription.cancel()

    // Test Variable Mapping

    let nextQuery = Query()
    nextQuery.__variables = [
      "id": "2001",
      "first": 2,
      "after": "Y3Vyc29yMg==",
    ]

    let expectedVariables = nextQuery.__variables?.values.compactMap { $0._jsonEncodableValue?._jsonValue } ?? []
    let firstKey = await pager.varMap.keys.first as? [JSONValue]
    let actualVariables = try XCTUnwrap(firstKey)

    XCTAssertEqual(expectedVariables.count, actualVariables.count)
    XCTAssertEqual(expectedVariables.count, 3)

    XCTAssertEqual(Set(expectedVariables), Set(actualVariables))
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
    XCTAssertSuccessResult(result) { value in
      let (first, next, source) = value
      XCTAssertTrue(next.isEmpty)
      XCTAssertEqual(first.hero.friendsConnection.friends.count, 2)
      XCTAssertEqual(first.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(source, .fetch)
    }

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
    let secondPageFetch = expectation(description: "Second Page")
    secondPageFetch.expectedFulfillmentCount = 2
    subscription = await pager.subscribe(onUpdate: { _ in
      secondPageFetch.fulfill()
    })

    try await pager.loadMore()
    await fulfillment(of: [secondPageExpectation, secondPageFetch], timeout: 1)
    subscription.cancel()
    let newResult = try await XCTUnwrapping(await pager.currentValue)
    try XCTAssertSuccessResult(newResult) { value in
      let (_, next, source) = value
      // Assert first page is unchanged
      XCTAssertEqual(try? result.get().0, try? newResult.get().0)
      XCTAssertFalse(next.isEmpty)
      XCTAssertEqual(next.count, 1)
      let page = try XCTUnwrap(next.first)
      XCTAssertEqual(page.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(source, .fetch)
    }
    let count = await pager.varMap.values.count
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
    XCTAssertSuccessResult(finalResult) { value in
      XCTAssertEqual(value.0.hero.name, "C3PO")
      XCTAssertEqual(value.1.count, 1)
      XCTAssertEqual(value.1.first?.hero.name, "C3PO")
    }
  }

  private func createPager() -> GraphQLQueryPager<Query, Query>.Actor {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return GraphQLQueryPager<Query, Query>.Actor(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: { data in
        switch data {
        case .initial(let data), .paginated(let data):
          return CursorBasedPagination.ForwardPagination(
            hasNext: data.hero.friendsConnection.pageInfo.hasNextPage,
            endCursor: data.hero.friendsConnection.pageInfo.endCursor
          )
        }
      },
      nextPageResolver: { pageInfo in
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
