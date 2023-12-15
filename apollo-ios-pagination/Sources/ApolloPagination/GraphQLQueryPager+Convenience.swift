import Apollo
import ApolloAPI

public extension GraphQLQueryPager {
  static func makeForwardCursorQueryPager(
    client: ApolloClientProtocol,
    queryProvider: @escaping (CursorBasedPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward
  ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(nil),
      extractPageInfo: pageExtraction(transform: extractPageInfo),
      pageResolver: { page, direction in
        guard direction == .next else { return nil }
        return queryProvider(page)
      }
    )
  }

  static func makeForwardCursorQueryPager(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> PaginatedQuery
  ) -> GraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: pageExtraction(
        initialTransfom: extractInitialPageInfo,
        paginatedTransform: extractNextPageInfo
      ),
      pageResolver: { page, direction in
        guard direction == .next else { return nil }
        return nextPageResolver(page)
      }
    )
  }

  static func makeReverseCursorQueryPager(
    client: ApolloClientProtocol,
    queryProvider: @escaping (CursorBasedPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse
  ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(nil),
      extractPageInfo: pageExtraction(transform: extractPageInfo),
      pageResolver: { page, direction in
        guard direction == .previous else { return nil }
        return queryProvider(page)
      }
    )
  }

  static func makeReverseCursorQueryPager(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractPreviousPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Reverse,
    previousPageResolver: @escaping (CursorBasedPagination.Reverse) -> PaginatedQuery
  ) -> GraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: pageExtraction(
        initialTransfom: extractInitialPageInfo,
        paginatedTransform: extractPreviousPageInfo
      ),
      pageResolver: { page, direction in
        guard direction == .previous else { return nil }
        return previousPageResolver(page)
      }
    )
  }

  static func makeBidirectionalCursorQueryPager(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    extractPaginatedPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Bidirectional
  ) -> GraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: pageExtraction(
        initialTransfom: extractInitialPageInfo,
        paginatedTransform: extractPaginatedPageInfo
      ),
      pageResolver: { page, direction in
        switch direction {
        case .next:
          return queryProvider(page)
        case .previous:
          return previousQueryProvider(page)
        }
      }
    )
  }

  static func makeBidirectionalCursorQueryPager(
    client: ApolloClientProtocol,
    start: CursorBasedPagination.Bidirectional?,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional
  ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(start),
      extractPageInfo: pageExtraction(transform: extractPageInfo),
      pageResolver: { page, direction in
        switch direction {
        case .next:
          return queryProvider(page)
        case .previous:
          return previousQueryProvider(page)
        }
      }
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
