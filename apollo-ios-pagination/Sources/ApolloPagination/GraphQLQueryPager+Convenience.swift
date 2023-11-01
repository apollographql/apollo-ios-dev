import Apollo
import ApolloAPI

public extension GraphQLQueryPager {
  static func makeForwardCursorQueryPager(
    client: ApolloClientProtocol,
    queryProvider: @escaping (CursorBasedPagination.ForwardPagination?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.ForwardPagination
  ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(nil),
      extractPageInfo: pageExtraction(transform: extractPageInfo),
      nextPageResolver: queryProvider,
      previousPageResolver: nil
    )
  }

  static func makeForwardCursorQueryPager(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.ForwardPagination,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.ForwardPagination,
    nextPageResolver: @escaping (CursorBasedPagination.ForwardPagination) -> PaginatedQuery
  ) -> GraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: pageExtraction(
        initialTransfom: extractInitialPageInfo,
        paginatedTransform: extractNextPageInfo
      ),
      nextPageResolver: nextPageResolver,
      previousPageResolver: nil
    )
  }

  static func makeReverseCursorQueryPager(
    client: ApolloClientProtocol,
    queryProvider: @escaping (CursorBasedPagination.ReversePagination?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.ReversePagination
  ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(nil),
      extractPageInfo: pageExtraction(transform: extractPageInfo),
      nextPageResolver: nil,
      previousPageResolver: queryProvider
    )
  }

  static func makeReverseCursorQueryPager(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.ReversePagination,
    extractPreviousPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.ReversePagination,
    previousPageResolver: @escaping (CursorBasedPagination.ReversePagination) -> PaginatedQuery
  ) -> GraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: pageExtraction(
        initialTransfom: extractInitialPageInfo,
        paginatedTransform: extractPreviousPageInfo
      ),
      nextPageResolver: nil,
      previousPageResolver: previousPageResolver
    )
  }

  static func makeBidirectionalCursorQueryPager(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    queryProvider: @escaping (CursorBasedPagination.BidirectionalPagination?) -> PaginatedQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.BidirectionalPagination?) -> PaginatedQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.BidirectionalPagination,
    extractPaginatedPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.BidirectionalPagination
  ) -> GraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: pageExtraction(
        initialTransfom: extractInitialPageInfo,
        paginatedTransform: extractPaginatedPageInfo
      ),
      nextPageResolver: queryProvider,
      previousPageResolver: previousQueryProvider
    )
  }

  static func makeBidirectionalCursorQueryPager(
    client: ApolloClientProtocol,
    start: CursorBasedPagination.BidirectionalPagination?,
    queryProvider: @escaping (CursorBasedPagination.BidirectionalPagination?) -> InitialQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.BidirectionalPagination?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.BidirectionalPagination
  ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(start),
      extractPageInfo: pageExtraction(transform: extractPageInfo),
      nextPageResolver: queryProvider,
      previousPageResolver: previousQueryProvider
    )
  }
}

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
