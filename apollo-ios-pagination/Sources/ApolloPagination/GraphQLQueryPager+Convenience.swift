import Apollo
import ApolloAPI
import Foundation

public extension AsyncGraphQLQueryPager {
  /// This convenience function creates an `AsyncGraphQLQueryPager` that paginates forward with only one query and has an output type of `Result<(PaginationOutput<InitialQuery, InitialQuery>, UpdateSource), Error>`.
  /// - Parameters:
  ///   - client: The Apollo client
  ///   - watcherDispatchQueue: The preferred dispatch queue for the internal `GraphQLQueryWatcher`s to operate on. Defaults to `main`.
  ///   - queryProvider: The transform from `CursorBasedPagination.Forward` to `InitialQuery`.
  ///   - extractPageInfo: The transform from `InitialQuery.Data` to `CursorBasedPagination.Forward`
  /// - Returns: `AsyncGraphQLQueryPager`
  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward
  ) async -> AsyncGraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    await AsyncGraphQLQueryPager(pager: AsyncGraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: queryProvider(nil),
      watcherDispatchQueue: watcherDispatchQueue,
      extractPageInfo: pageExtraction(transform: extractPageInfo),
      pageResolver: { page, direction in
        guard direction == .next else { return nil }
        return queryProvider(page)
      }
    ))
  }

  /// This convenience function creates an `AsyncGraphQLQueryPager` that paginates forward with only one query and has a custom output model.
  /// - Parameters:
  ///   - client: The Apollo client
  ///   - watcherDispatchQueue: The preferred dispatch queue for the internal `GraphQLQueryWatcher`s to operate on. Defaults to `main`.
  ///   - queryProvider: The transform from `CursorBasedPagination.Forward` to `InitialQuery`.
  ///   - extractPageInfo: The transform from `InitialQuery.Data` to `CursorBasedPagination.Forward`
  ///   - transform: The transform from `([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data])` to a custom `Model` type.
  /// - Returns: `AsyncGraphQLQueryPager`
  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    transform: @escaping ([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data]) throws -> Model
  ) async -> AsyncGraphQLQueryPager {
    await AsyncGraphQLQueryPager(
      pager: AsyncGraphQLQueryPagerCoordinator(
        client: client,
        initialQuery: queryProvider(nil),
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(transform: extractPageInfo),
        pageResolver: { page, direction in
          guard direction == .next else { return nil }
          return queryProvider(page)
        }
      ),
      transform: transform
    )
  }
  /// This convenience function creates an `AsyncGraphQLQueryPager` that paginates forward with only one query. The output type is represented as an array of a custom model.
  /// - Parameters:
  ///   - client: The Apollo client
  ///   - watcherDispatchQueue: The preferred dispatch queue for the internal `GraphQLQueryWatcher`s to operate on. Defaults to `main`.
  ///   - queryProvider: The transform from `CursorBasedPagination.Forward` to `InitialQuery`.
  ///   - extractPageInfo: The transform from `InitialQuery.Data` to `CursorBasedPagination.Forward`
  ///   - transform: The transform from `([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data])` to a custom `Model` type.
  /// - Returns: `AsyncGraphQLQueryPager`
  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    transform: @escaping (InitialQuery.Data) throws -> Model
  ) async -> AsyncGraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    await AsyncGraphQLQueryPager(
      pager: AsyncGraphQLQueryPagerCoordinator(
        client: client,
        initialQuery: queryProvider(nil),
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(transform: extractPageInfo),
        pageResolver: { page, direction in
          guard direction == .next else { return nil }
          return queryProvider(page)
        }
      ),
      initialTransform: transform,
      pageTransform: transform
    )
  }

  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery, NextQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (NextQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> NextQuery
  ) async -> AsyncGraphQLQueryPager where Model == PaginationOutput<InitialQuery, NextQuery> {
    await AsyncGraphQLQueryPager(
      pager: .init(
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
    )
  }

  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery, NextQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (NextQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> NextQuery,
    transform: @escaping ([NextQuery.Data], InitialQuery.Data, [NextQuery.Data]) throws -> Model
  ) async -> AsyncGraphQLQueryPager {
    await AsyncGraphQLQueryPager(
      pager: .makeForwardCursorQueryPager(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractInitialPageInfo: extractInitialPageInfo,
        extractNextPageInfo: extractNextPageInfo,
        nextPageResolver: nextPageResolver
      ),
      transform: transform
    )
  }

  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery, NextQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (NextQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> NextQuery,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (NextQuery.Data) throws -> Model
  ) async -> AsyncGraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    await AsyncGraphQLQueryPager(
      pager: .makeForwardCursorQueryPager(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractInitialPageInfo: extractInitialPageInfo,
        extractNextPageInfo: extractNextPageInfo,
        nextPageResolver: nextPageResolver
      ),
      initialTransform: initialTransform,
      pageTransform: pageTransform
    )
  }

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse
  ) async -> AsyncGraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    await AsyncGraphQLQueryPager(pager: AsyncGraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: queryProvider(nil),
      watcherDispatchQueue: watcherDispatchQueue,
      extractPageInfo: pageExtraction(transform: extractPageInfo),
      pageResolver: { page, direction in
        guard direction == .previous else { return nil }
        return queryProvider(page)
      }
    ))
  }

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    transform: @escaping ([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data]) throws -> Model
  ) async -> AsyncGraphQLQueryPager {
    await AsyncGraphQLQueryPager(
      pager: AsyncGraphQLQueryPagerCoordinator(
        client: client,
        initialQuery: queryProvider(nil),
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(transform: extractPageInfo),
        pageResolver: { page, direction in
          guard direction == .previous else { return nil }
          return queryProvider(page)
        }
      ),
      transform: transform
    )
  }

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    transform: @escaping (InitialQuery.Data) throws -> Model
  ) async -> AsyncGraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    await AsyncGraphQLQueryPager(
      pager: AsyncGraphQLQueryPagerCoordinator(
        client: client,
        initialQuery: queryProvider(nil),
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(transform: extractPageInfo),
        pageResolver: { page, direction in
          guard direction == .previous else { return nil }
          return queryProvider(page)
        }
      ),
      initialTransform: transform,
      pageTransform: transform
    )
  }

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery, NextQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractNextPageInfo: @escaping (NextQuery.Data) -> CursorBasedPagination.Reverse,
    nextPageResolver: @escaping (CursorBasedPagination.Reverse) -> NextQuery
  ) async -> AsyncGraphQLQueryPager where Model == PaginationOutput<InitialQuery, NextQuery> {
    await AsyncGraphQLQueryPager(
      pager: .init(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(
          initialTransfom: extractInitialPageInfo,
          paginatedTransform: extractNextPageInfo
        ),
        pageResolver: { page, direction in
          guard direction == .previous else { return nil }
          return nextPageResolver(page)
        }
      )
    )
  }

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery, NextQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractPreviousPageInfo: @escaping (NextQuery.Data) -> CursorBasedPagination.Reverse,
    previousPageResolver: @escaping (CursorBasedPagination.Reverse) -> NextQuery,
    transform: @escaping ([NextQuery.Data], InitialQuery.Data, [NextQuery.Data]) throws -> Model
  ) async -> AsyncGraphQLQueryPager {
    await AsyncGraphQLQueryPager(
      pager: .makeReverseCursorQueryPager(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractInitialPageInfo: extractInitialPageInfo,
        extractPreviousPageInfo: extractPreviousPageInfo,
        previousPageResolver: previousPageResolver
      ),
      transform: transform
    )
  }

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery, NextQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractPreviousPageInfo: @escaping (NextQuery.Data) -> CursorBasedPagination.Reverse,
    previousPageResolver: @escaping (CursorBasedPagination.Reverse) -> NextQuery,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (NextQuery.Data) throws -> Model
  ) async -> AsyncGraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    await AsyncGraphQLQueryPager(
      pager: .makeReverseCursorQueryPager(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractInitialPageInfo: extractInitialPageInfo,
        extractPreviousPageInfo: extractPreviousPageInfo,
        previousPageResolver: previousPageResolver
      ),
      initialTransform: initialTransform,
      pageTransform: pageTransform
    )
  }
}

private extension GraphQLQueryPagerCoordinator {
  static func makeForwardCursorQueryPager(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> PaginatedQuery
  ) -> GraphQLQueryPagerCoordinator {
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
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractPreviousPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Reverse,
    previousPageResolver: @escaping (CursorBasedPagination.Reverse) -> PaginatedQuery
  ) -> GraphQLQueryPagerCoordinator {
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
  ) -> GraphQLQueryPagerCoordinator {
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
  ) -> GraphQLQueryPagerCoordinator where InitialQuery == PaginatedQuery {
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

private extension AsyncGraphQLQueryPagerCoordinator {
  static func makeForwardCursorQueryPager(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> PaginatedQuery
  ) -> AsyncGraphQLQueryPagerCoordinator {
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
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractPreviousPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Reverse,
    previousPageResolver: @escaping (CursorBasedPagination.Reverse) -> PaginatedQuery
  ) -> AsyncGraphQLQueryPagerCoordinator {
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
  ) -> AsyncGraphQLQueryPagerCoordinator {
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
  ) -> AsyncGraphQLQueryPagerCoordinator where InitialQuery == PaginatedQuery {
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
