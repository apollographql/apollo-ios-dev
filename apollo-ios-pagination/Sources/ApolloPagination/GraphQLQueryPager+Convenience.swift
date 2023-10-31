import Apollo
import ApolloAPI

extension GraphQLQueryPager {
  public static func makeForwardCursorQueryPager(
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

  public static func makeForwardCursorQueryPager(
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

  public static func makeReverseCursorQueryPager(
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

  public static func makeReverseCursorQueryPager(
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
      nextPageResolver: previousPageResolver,
      previousPageResolver: nil
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
