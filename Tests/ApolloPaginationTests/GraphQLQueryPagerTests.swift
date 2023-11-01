import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Combine
import XCTest

@testable import ApolloPagination

final class GraphQLQueryPagerTests: XCTestCase, CacheDependentTesting {
    private typealias ReverseQuery = MockQuery<Mocks.Hero.ReverseFriendsQuery>
    private typealias ForwardQuery = MockQuery<Mocks.Hero.FriendsQuery>


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

    func test_canLoadMore() async throws {
        let pager = createForwardPager()

        let serverExpectation = Mocks.Hero.FriendsQuery.expectationForFirstPage(server: server)

        await pager.fetch()
        await fulfillment(of: [serverExpectation])

        var canLoadMore = await pager.canLoadNext
        XCTAssertTrue(canLoadMore)

        let secondPageExpectation = Mocks.Hero.FriendsQuery.expectationForSecondPage(server: server)
        let secondPageFetch = expectation(description: "Second Page")
        secondPageFetch.expectedFulfillmentCount = 2
        let subscription = await pager.subscribe(onUpdate: { _ in
            secondPageFetch.fulfill()
        })
        try await pager.loadMore()
        await fulfillment(of: [secondPageExpectation, secondPageFetch])
        subscription.cancel()
        canLoadMore = await pager.canLoadNext
        XCTAssertFalse(canLoadMore)
    }

    func test_canLoadPrevious() async throws {
        let pager = createReversePager()

        let serverExpectation = Mocks.Hero.ReverseFriendsQuery.expectationForLastItem(server: server)

        await pager.fetch()
        await fulfillment(of: [serverExpectation])

        var canLoadMore = await pager.canLoadPrevious
        XCTAssertTrue(canLoadMore)

        let secondPageExpectation = Mocks.Hero.ReverseFriendsQuery.expectationForPreviousItem(server: server)
        let secondPageFetch = expectation(description: "Second Page")
        secondPageFetch.expectedFulfillmentCount = 2
        let subscription = await pager.subscribe(onUpdate: { _ in
            secondPageFetch.fulfill()
        })
        try await pager.loadPrevious()
        await fulfillment(of: [secondPageExpectation, secondPageFetch])
        subscription.cancel()
        canLoadMore = await pager.canLoadPrevious
        XCTAssertFalse(canLoadMore)
    }

    private func createReversePager() -> GraphQLQueryPager<ReverseQuery, ReverseQuery>.Actor {
        let initialQuery = ReverseQuery()
        initialQuery.__variables = ["id": "2001", "first": 2, "before": "Y3Vyc29yMw=="]
        return GraphQLQueryPager<ReverseQuery, ReverseQuery>.Actor(
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
            nextPageResolver: nil,
            previousPageResolver: { pageInfo in
                let nextQuery = ReverseQuery()
                nextQuery.__variables = [
                    "id": "2001",
                    "first": 2,
                    "before": pageInfo.startCursor,
                ]
                return nextQuery
            }
        )
    }

    private func createForwardPager() -> GraphQLQueryPager<ForwardQuery, ForwardQuery>.Actor {
        let initialQuery = ForwardQuery()
        initialQuery.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
        return GraphQLQueryPager<ForwardQuery, ForwardQuery>.Actor(
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
                let nextQuery = ForwardQuery()
                nextQuery.__variables = [
                    "id": "2001",
                    "first": 2,
                    "after": pageInfo.endCursor,
                ]
                return nextQuery
            },
            previousPageResolver: nil
        )
    }
}
