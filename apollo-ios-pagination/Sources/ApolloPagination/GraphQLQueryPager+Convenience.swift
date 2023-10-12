import Apollo
import ApolloAPI

// MARK: - Pager Convenience Methods

public extension GraphQLQueryPager {
    static func makeQueryPager<P: PaginationInfo>(
        client: ApolloClientProtocol,
        queryProvider: @escaping (P?) -> InitialQuery,
        extractPageInfo: @escaping (InitialQuery.Data) -> P
    ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
        .init(
            client: client,
            initialQuery: queryProvider(nil),
            extractPageInfo: pageExtraction(transform: extractPageInfo),
            nextPageResolver: queryProvider
        )
    }

    static func makeQueryPager<P: PaginationInfo>(
        client: ApolloClientProtocol,
        initialQuery: InitialQuery,
        extractInitialPageInfo: @escaping (InitialQuery.Data) -> P,
        extractNextPageInfo: @escaping (PaginatedQuery.Data) -> P,
        nextPageResolver: @escaping (P) -> PaginatedQuery
    ) -> GraphQLQueryPager {
        .init(
            client: client,
            initialQuery: initialQuery,
            extractPageInfo: pageExtraction(
                initialTransfom: extractInitialPageInfo,
                paginatedTransform: extractNextPageInfo
            ),
            nextPageResolver: nextPageResolver
        )
    }
}

// MARK: Forward Pager Convenience Methods

public extension GraphQLQueryPager {
    static func makeForwardCursorQueryPager(
        client: ApolloClientProtocol,
        queryProvider: @escaping (CursorBasedPagination.ForwardPagination?) -> InitialQuery,
        extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.ForwardPagination
    ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
        .makeQueryPager(
            client: client,
            queryProvider: queryProvider,
            extractPageInfo: extractPageInfo
        )
    }

    static func makeForwardCursorQueryPager(
        client: ApolloClientProtocol,
        initialQuery: InitialQuery,
        extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.ForwardPagination,
        extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.ForwardPagination,
        nextPageResolver: @escaping (CursorBasedPagination.ForwardPagination) -> PaginatedQuery
    ) -> GraphQLQueryPager {
        makeQueryPager(
            client: client,
            initialQuery: initialQuery,
            extractInitialPageInfo: extractInitialPageInfo,
            extractNextPageInfo: extractNextPageInfo,
            nextPageResolver: nextPageResolver
        )
    }
}

// MARK: Reverse Pager Convenience Methods

public extension GraphQLQueryPager {
    static func makeReverseCursorQueryPager(
        client: ApolloClientProtocol,
        queryProvider: @escaping (CursorBasedPagination.ReversePagination?) -> InitialQuery,
        extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.ReversePagination
    ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
        .makeQueryPager(
            client: client,
            queryProvider: queryProvider,
            extractPageInfo: extractPageInfo
        )
    }

    static func makeReverseCursorQueryPager(
        client: ApolloClientProtocol,
        initialQuery: InitialQuery,
        extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.ReversePagination,
        extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.ReversePagination,
        nextPageResolver: @escaping (CursorBasedPagination.ReversePagination) -> PaginatedQuery
    ) -> GraphQLQueryPager {
        makeQueryPager(
            client: client,
            initialQuery: initialQuery,
            extractInitialPageInfo: extractInitialPageInfo,
            extractNextPageInfo: extractNextPageInfo,
            nextPageResolver: nextPageResolver
        )
    }
}

// MARK: Offset Pager Convenience Methods

public extension GraphQLQueryPager {
    static func makeOffsetQueryPager(
        client: ApolloClientProtocol,
        queryProvider: @escaping (OffsetPagination?) -> InitialQuery,
        extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination
    ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
        .makeQueryPager(
            client: client,
            queryProvider: queryProvider,
            extractPageInfo: extractPageInfo
        )
    }

    static func makeOffsetQueryPager(
        client: ApolloClientProtocol,
        initialQuery: InitialQuery,
        extractInitialPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination,
        extractNextPageInfo: @escaping (PaginatedQuery.Data) -> OffsetPagination,
        nextPageResolver: @escaping (OffsetPagination) -> PaginatedQuery
    ) -> GraphQLQueryPager {
        makeQueryPager(
            client: client,
            initialQuery: initialQuery,
            extractInitialPageInfo: extractInitialPageInfo,
            extractNextPageInfo: extractNextPageInfo,
            nextPageResolver: nextPageResolver
        )
    }
}

// MARK: - Private API

private func pageExtraction<InitialQuery: GraphQLQuery, NextQuery: GraphQLQuery, P: PaginationInfo>(
    initialTransfom: @escaping (InitialQuery.Data) -> P,
    paginatedTransform: @escaping (NextQuery.Data) -> P
) -> (GraphQLQueryPager<InitialQuery, NextQuery>.PageExtractionData) -> P {
    { extractionData in
        switch extractionData {
        case .initial(let value):
            return initialTransfom(value)
        case .paginated(let value):
            return paginatedTransform(value)
        }
    }
}

private func pageExtraction<InitialQuery: GraphQLQuery, P: PaginationInfo>(
    transform: @escaping (InitialQuery.Data) -> P
) -> (GraphQLQueryPager<InitialQuery, InitialQuery>.PageExtractionData) -> P {
    { extractionData in
        switch extractionData {
        case .initial(let value), .paginated(let value):
            return transform(value)
        }
    }
}
