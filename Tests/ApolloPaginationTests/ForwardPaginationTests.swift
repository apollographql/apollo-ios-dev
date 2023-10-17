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

    try super.tearDownWithError()
  }

  func test_fetchMultiplePages() async throws {
    let pager = createPager()

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    var results: [Result<(Query.Data, [Query.Data], UpdateSource), Error>] = []
    await pager.refetch()
    await fulfillment(of: [serverExpectation], timeout: 1)
    var _result = await pager.currentValue
    var result = try XCTUnwrap(_result)
    results.append(result)
    XCTAssertSuccessResult(result) { value in
      let (first, next, source) = value
      XCTAssertTrue(next.isEmpty)
      XCTAssertEqual(first.hero.friendsConnection.friends.count, 2)
      XCTAssertEqual(first.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(source, .fetch)
    }

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)

    try await pager.loadMore()
    await fulfillment(of: [secondPageExpectation], timeout: 1)

    _result = await pager.currentValue
    result = try XCTUnwrap(_result)
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
    Task {
      let count = await pager.varMap.values.count
      XCTAssertEqual(count, 1)
    }
  }

  func test_fetchMultiplePages_noCache() async throws {
    let pager = createPager()

    let initialFetchExpectation = expectation(description: "Results")
    initialFetchExpectation.assertForOverFulfill = false
    let nextPageExpectation = expectation(description: "Next Page")
    nextPageExpectation.expectedFulfillmentCount = 2

    var results: [Result<GraphQLQueryPagerWrapper<Query, Query>.Output, Error>] = []
    var counter = 0
    await pager.subscribe { result in
      results.append(result)
      initialFetchExpectation.fulfill()
      nextPageExpectation.fulfill()
      counter += 1
    }.store(in: &cancellables)

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.refetch(cachePolicy: .fetchIgnoringCacheData)
    await fulfillment(of: [serverExpectation, initialFetchExpectation])
    XCTAssertFalse(results.isEmpty)
    let result = try XCTUnwrap(results.first)
    XCTAssertSuccessResult(result) { value in
      let (first, next, source) = value
      XCTAssertTrue(next.isEmpty)
      XCTAssertEqual(first.hero.friendsConnection.friends.count, 2)
      XCTAssertEqual(first.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(source, .fetch)
      XCTAssertEqual(counter, 1)
    }
    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)

    try await pager.loadMore(cachePolicy: .fetchIgnoringCacheData)
    await fulfillment(of: [secondPageExpectation, nextPageExpectation])
    XCTAssertFalse(results.isEmpty)
    let newResult = try XCTUnwrap(results.last)
    try XCTAssertSuccessResult(newResult) { value in
      let (_, next, source) = value
      // Assert first page is unchanged
      XCTAssertEqual(try? results.first?.get().0, try? results.last?.get().0)

      XCTAssertEqual(counter, 2)
      XCTAssertFalse(next.isEmpty)
      XCTAssertEqual(next.count, 1)
      let page = try XCTUnwrap(next.first)
      XCTAssertEqual(page.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(source, .fetch)
    }
    let count = await pager.varMap.values.count
    XCTAssertEqual(count, 1)

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

    let initialFetchExpectation = expectation(description: "Results")
    initialFetchExpectation.assertForOverFulfill = false
    let nextPageExpectation = expectation(description: "Next Page")
    nextPageExpectation.expectedFulfillmentCount = 2
    nextPageExpectation.assertForOverFulfill = false
    let mutationFulfillment = expectation(description: "Mutation")
    mutationFulfillment.expectedFulfillmentCount = 4
    nextPageExpectation.assertForOverFulfill = false

    var results: [Result<GraphQLQueryPager<Query, Query>.Output, Error>] = []
    var counter = 0
    await pager.subscribe { result in
      results.append(result)
      initialFetchExpectation.fulfill()
      nextPageExpectation.fulfill()
      mutationFulfillment.fulfill()
      counter += 1
    }.store(in: &cancellables)

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.refetch()
    await fulfillment(of: [serverExpectation, initialFetchExpectation])
    XCTAssertFalse(results.isEmpty)
    let result = try XCTUnwrap(results.first)
    XCTAssertSuccessResult(result) { value in
      let (first, next, source) = value
      XCTAssertTrue(next.isEmpty)
      XCTAssertEqual(first.hero.friendsConnection.friends.count, 2)
      XCTAssertEqual(first.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(source, .fetch)
      XCTAssertEqual(counter, 1)
    }

    let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)

    try await pager.loadMore()
    await fulfillment(of: [secondPageExpectation, nextPageExpectation])
    XCTAssertFalse(results.isEmpty)
    let newResult = try XCTUnwrap(results.last)
    try XCTAssertSuccessResult(newResult) { value in
      let (_, next, source) = value
      // Assert first page is unchanged
      XCTAssertEqual(try? results.first?.get().0, try? results.last?.get().0)

      XCTAssertEqual(counter, 2)
      XCTAssertFalse(next.isEmpty)
      XCTAssertEqual(next.count, 1)
      let page = try XCTUnwrap(next.first)
      XCTAssertEqual(page.hero.friendsConnection.friends.count, 1)
      XCTAssertEqual(source, .fetch)
    }
    let count = await pager.varMap.values.count
    XCTAssertEqual(count, 1)

    let transactionExpectation = expectation(description: "Writing to cache")
    client.store.withinReadWriteTransaction { transaction in
      let cacheMutation = MockLocalCacheMutation<Mocks.Hero.NameCacheMutation>()
      cacheMutation.__variables = ["id": "2001"]
      try! transaction.update(cacheMutation) { data in
        data.hero?.name = "C3PO"
        transactionExpectation.fulfill()
      }
    }

    await fulfillment(of: [mutationFulfillment, transactionExpectation])
    XCTAssertEqual(results.count, 4)
    let finalResult = try XCTUnwrap(results.last)
    XCTAssertSuccessResult(finalResult) { value in
      XCTAssertEqual(value.0.hero.name, "C3PO")
      value.1.forEach { page in
        XCTAssertEqual(page.hero.name, "C3PO")
      }
    }
  }

  private func createPager() -> GraphQLQueryPager<Query, Query> {
    let initialQuery = Query()
    initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return GraphQLQueryPager<Query, Query>(
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
