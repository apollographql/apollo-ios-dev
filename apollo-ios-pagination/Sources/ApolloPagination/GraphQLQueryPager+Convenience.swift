import Apollo
import ApolloAPI
import Foundation

public extension GraphQLQueryPager {
  static func makeForwardCursorQueryPager(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward
  ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(nil),
      watcherDispatchQueue: watcherDispatchQueue,
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
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> PaginatedQuery
  ) -> GraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
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
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse
  ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(nil),
      watcherDispatchQueue: watcherDispatchQueue,
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
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractPreviousPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Reverse,
    previousPageResolver: @escaping (CursorBasedPagination.Reverse) -> PaginatedQuery
  ) -> GraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
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
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    extractPaginatedPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Bidirectional
  ) -> GraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
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
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional
  ) -> GraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(start),
      watcherDispatchQueue: watcherDispatchQueue,
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

public extension AsyncGraphQLQueryPager {
  static func makeForwardCursorQueryPager(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward
  ) -> AsyncGraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(nil),
      watcherDispatchQueue: watcherDispatchQueue,
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
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> PaginatedQuery
  ) -> AsyncGraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
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
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse
  ) -> AsyncGraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(nil),
      watcherDispatchQueue: watcherDispatchQueue,
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
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractPreviousPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Reverse,
    previousPageResolver: @escaping (CursorBasedPagination.Reverse) -> PaginatedQuery
  ) -> AsyncGraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
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
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    extractPaginatedPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Bidirectional
  ) -> AsyncGraphQLQueryPager {
    .init(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
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
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional
  ) -> AsyncGraphQLQueryPager where InitialQuery == PaginatedQuery {
    .init(
      client: client,
      initialQuery: queryProvider(start),
      watcherDispatchQueue: watcherDispatchQueue,
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
