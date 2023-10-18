import Apollo
import ApolloAPI

public extension GraphQLQueryPager.Actor {
  static func makeQueryPager<P: PaginationInfo>(
    client: ApolloClientProtocol,
    queryProvider: @escaping (P?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> P
  ) -> GraphQLQueryPager.Actor where InitialQuery == PaginatedQuery {
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
  ) -> GraphQLQueryPager.Actor {
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

  static func makeForwardCursorQueryPager(
    client: ApolloClientProtocol,
    queryProvider: @escaping (CursorBasedPagination.ForwardPagination?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.ForwardPagination
  ) -> GraphQLQueryPager.Actor where InitialQuery == PaginatedQuery {
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
  ) -> GraphQLQueryPager.Actor {
    makeQueryPager(
      client: client,
      initialQuery: initialQuery,
      extractInitialPageInfo: extractInitialPageInfo,
      extractNextPageInfo: extractNextPageInfo,
      nextPageResolver: nextPageResolver
    )
  }

  static func makeReverseCursorQueryPager(
    client: ApolloClientProtocol,
    queryProvider: @escaping (CursorBasedPagination.ReversePagination?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.ReversePagination
  ) -> GraphQLQueryPager.Actor where InitialQuery == PaginatedQuery {
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
  ) -> GraphQLQueryPager.Actor {
    makeQueryPager(
      client: client,
      initialQuery: initialQuery,
      extractInitialPageInfo: extractInitialPageInfo,
      extractNextPageInfo: extractNextPageInfo,
      nextPageResolver: nextPageResolver
    )
  }
}

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

private func pageExtraction<InitialQuery: GraphQLQuery, NextQuery: GraphQLQuery, P: PaginationInfo>(
  initialTransfom: @escaping (InitialQuery.Data) -> P,
  paginatedTransform: @escaping (NextQuery.Data) -> P
) -> (PageExtractionData<InitialQuery, NextQuery>) -> P {
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
) -> (PageExtractionData<InitialQuery, InitialQuery>) -> P {
  { extractionData in
    switch extractionData {
    case .initial(let value), .paginated(let value):
      return transform(value)
    }
  }
}
