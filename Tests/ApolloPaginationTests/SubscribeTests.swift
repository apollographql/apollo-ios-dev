import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
@preconcurrency import Combine
import XCTest

@testable import ApolloPagination

final class SubscribeTest: XCTestCase, CacheDependentTesting {
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

    try super.tearDownWithError()
  }

  private typealias Query = MockQuery<Mocks.Hero.FriendsQuery>

  func test_multipleSubscribers() async throws {
    let pager = createPager()

    let initialFetchExpectation = expectation(description: "Results")
    initialFetchExpectation.assertForOverFulfill = false

    var results: [Result<PaginationOutput<Query, Query>, any Error>] = []
    var otherResults: [Result<PaginationOutput<Query, Query>, any Error>] = []
    await pager.$currentValue.compactMap({ $0 }).sink { result in
      results.append(result)
      initialFetchExpectation.fulfill()
    }.store(in: &cancellables)

    await pager.$currentValue.compactMap({ $0 }).sink { result in
      otherResults.append(result)
    }.store(in: &cancellables)

    let serverExpectation = await Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

    await pager.fetch()
    await fulfillment(of: [serverExpectation, initialFetchExpectation], timeout: 1.0)
    XCTAssertFalse(results.isEmpty)
    let result = try XCTUnwrap(results.first)
    XCTAssertSuccessResult(result) { output in
      XCTAssertTrue(output.nextPages.isEmpty)
      XCTAssertEqual(output.initialPage?.data?.hero.friendsConnection.friends.count, 2)
      XCTAssertEqual(output.initialPage?.data?.hero.friendsConnection.totalCount, 3)
      XCTAssertEqual(output.initialPage?.source, .server)
      XCTAssertEqual(results.count, otherResults.count)
    }
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
          "after": pageInfo.endCursor ?? .null,
        ]
        return nextQuery
      }
    )
  }
}
