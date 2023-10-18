import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Combine
import XCTest

@testable import ApolloPagination

final class SubscribeTest: XCTestCase, CacheDependentTesting {
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

  private typealias Query = MockQuery<Mocks.Hero.FriendsQuery>

  func test_multipleSubscribers() async throws {
    let pager = createPager()

    let initialFetchExpectation = expectation(description: "Results")
    initialFetchExpectation.assertForOverFulfill = false

    var results: [Result<GraphQLQueryPager<Query, Query>.Output, Error>] = []
    var otherResults: [Result<GraphQLQueryPager<Query, Query>.Output, Error>] = []
    await pager.$currentValue.compactMap({ $0 }).sink { result in
      results.append(result)
      initialFetchExpectation.fulfill()
    }.store(in: &cancellables)

    await pager.$currentValue.compactMap({ $0 }).sink { result in
      otherResults.append(result)
    }.store(in: &cancellables)

    let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.refetch()
    await fulfillment(of: [serverExpectation, initialFetchExpectation], timeout: 1.0)
    XCTAssertFalse(results.isEmpty)
    let result = try XCTUnwrap(results.first)
    XCTAssertSuccessResult(result) { value in
      let (first, next, source) = value
      XCTAssertTrue(next.isEmpty)
      XCTAssertEqual(first.hero.friendsConnection.friends.count, 2)
      XCTAssertEqual(first.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(source, .fetch)
      XCTAssertEqual(results.count, otherResults.count)
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
          return ForwardPagination(
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
