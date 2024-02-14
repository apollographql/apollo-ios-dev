import Apollo
import ApolloAPI
import Foundation

// MARK: - GraphQLQueryPager Convenience Functions

public extension GraphQLQueryPager {

  // MARK: Offset initializers

  static func makeForwardOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Forward
  ) -> GraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    GraphQLQueryPager(pager: GraphQLQueryPagerCoordinator(
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

  static func makeForwardOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Forward,
    transform: @escaping ([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data]) throws -> Model
  ) -> GraphQLQueryPager {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
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

  static func makeForwardOffsetQueryPager<InitialQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Forward,
    transform: @escaping (InitialQuery.Data) throws -> Model
  ) -> GraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
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

  static func makeReverseOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Reverse
  ) -> GraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    GraphQLQueryPager(pager: GraphQLQueryPagerCoordinator(
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

  static func makeReverseOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Reverse,
    transform: @escaping ([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data]) throws -> Model
  ) -> GraphQLQueryPager {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
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

  static func makeReverseOffsetQueryPager<InitialQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Reverse,
    transform: @escaping (InitialQuery.Data) throws -> Model
  ) -> GraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
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

  static func makeBidirectionalOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    start: OffsetPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Bidirectional
  ) -> GraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    GraphQLQueryPager(pager: GraphQLQueryPagerCoordinator(
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
    ))
  }

  static func makeBidirectionalOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    start: OffsetPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Bidirectional,
    transform: @escaping ([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data]) throws -> Model
  ) -> GraphQLQueryPager {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
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
      ),
      transform: transform
    )
  }

  static func makeBidirectionalOffsetQueryPager<InitialQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    start: OffsetPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Bidirectional,
    transform: @escaping (InitialQuery.Data) throws -> Model
  ) -> GraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
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
      ),
      initialTransform: transform,
      pageTransform: transform
    )
  }

  // MARK: CursorBasedPagination.Forward Initializers

  /// This convenience function creates an `GraphQLQueryPager` that paginates forward with only one query and has an output type of `Result<(PaginationOutput<InitialQuery, InitialQuery>, UpdateSource), Error>`.
  /// - Parameters:
  ///   - client: The Apollo client
  ///   - watcherDispatchQueue: The preferred dispatch queue for the internal `GraphQLQueryWatcher`s to operate on. Defaults to `main`.
  ///   - queryProvider: The transform from `CursorBasedPagination.Forward` to `InitialQuery`.
  ///   - extractPageInfo: The transform from `InitialQuery.Data` to `CursorBasedPagination.Forward`
  /// - Returns: `GraphQLQueryPager`
  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward
  ) -> GraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    GraphQLQueryPager(pager: GraphQLQueryPagerCoordinator(
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

  /// This convenience function creates an `GraphQLQueryPager` that paginates forward with only one query and has a custom output model.
  /// - Parameters:
  ///   - client: The Apollo client
  ///   - watcherDispatchQueue: The preferred dispatch queue for the internal `GraphQLQueryWatcher`s to operate on. Defaults to `main`.
  ///   - queryProvider: The transform from `CursorBasedPagination.Forward` to `InitialQuery`.
  ///   - extractPageInfo: The transform from `InitialQuery.Data` to `CursorBasedPagination.Forward`
  ///   - transform: The transform from `([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data])` to a custom `Model` type.
  /// - Returns: `GraphQLQueryPager`
  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    transform: @escaping ([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data]) throws -> Model
  ) -> GraphQLQueryPager {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
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

  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    transform: @escaping (InitialQuery.Data) throws -> Model
  ) -> GraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
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

  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> PaginatedQuery
  ) -> GraphQLQueryPager where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    GraphQLQueryPager(
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

  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> PaginatedQuery,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
  ) -> GraphQLQueryPager {
    GraphQLQueryPager(
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

  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> PaginatedQuery,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
  ) -> GraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    GraphQLQueryPager(
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

  // MARK: CursorBasedPagination.Reverse Initializers

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse
  ) -> GraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    GraphQLQueryPager(pager: GraphQLQueryPagerCoordinator(
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
  ) -> GraphQLQueryPager {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
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
  ) -> GraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
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

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Reverse,
    nextPageResolver: @escaping (CursorBasedPagination.Reverse) -> PaginatedQuery
  ) -> GraphQLQueryPager where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    GraphQLQueryPager(
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

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractPreviousPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Reverse,
    previousPageResolver: @escaping (CursorBasedPagination.Reverse) -> PaginatedQuery,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
  ) -> GraphQLQueryPager {
    GraphQLQueryPager(
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

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractPreviousPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Reverse,
    previousPageResolver: @escaping (CursorBasedPagination.Reverse) -> PaginatedQuery,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
  ) -> GraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    GraphQLQueryPager(
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

  // MARK: CursorBasedPagination.Bidirectional Initializers

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    start: CursorBasedPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional
  ) -> GraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    GraphQLQueryPager(pager: .makeBidirectionalCursorQueryPager(
      client: client,
      start: start,
      watcherDispatchQueue: watcherDispatchQueue,
      queryProvider: queryProvider,
      previousQueryProvider: previousQueryProvider,
      extractPageInfo: extractPageInfo
    ))
  }

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    start: CursorBasedPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    transform: @escaping ([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data]) throws -> Model
  ) -> GraphQLQueryPager {
    GraphQLQueryPager(
      pager: .makeBidirectionalCursorQueryPager(
        client: client,
        start: start,
        watcherDispatchQueue: watcherDispatchQueue,
        queryProvider: queryProvider,
        previousQueryProvider: previousQueryProvider,
        extractPageInfo: extractPageInfo
      ),
      transform: transform
    )
  }

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    start: CursorBasedPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    transform: @escaping (InitialQuery.Data) throws -> Model
  ) -> GraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    GraphQLQueryPager(
      pager: .makeBidirectionalCursorQueryPager(
        client: client,
        start: start,
        watcherDispatchQueue: watcherDispatchQueue,
        queryProvider: queryProvider,
        previousQueryProvider: previousQueryProvider,
        extractPageInfo: extractPageInfo
      ),
      initialTransform: transform,
      pageTransform: transform
    )
  }

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    extractPaginatedPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Bidirectional
  ) -> GraphQLQueryPager where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    GraphQLQueryPager(pager: .makeBidirectionalCursorQueryPager(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
      queryProvider: queryProvider,
      previousQueryProvider: previousQueryProvider,
      extractInitialPageInfo: extractInitialPageInfo,
      extractPaginatedPageInfo: extractPaginatedPageInfo
    ))
  }

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    extractPaginatedPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Bidirectional,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
  ) -> GraphQLQueryPager {
    GraphQLQueryPager(
      pager: .makeBidirectionalCursorQueryPager(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        queryProvider: queryProvider,
        previousQueryProvider: previousQueryProvider,
        extractInitialPageInfo: extractInitialPageInfo,
        extractPaginatedPageInfo: extractPaginatedPageInfo
      ),
      transform: transform
    )
  }

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    extractPaginatedPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Bidirectional,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
  ) -> GraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    GraphQLQueryPager(
      pager: .makeBidirectionalCursorQueryPager(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        queryProvider: queryProvider,
        previousQueryProvider: previousQueryProvider,
        extractInitialPageInfo: extractInitialPageInfo,
        extractPaginatedPageInfo: extractPaginatedPageInfo
      ),
      initialTransform: initialTransform,
      pageTransform: pageTransform
    )
  }
}

// MARK: - AsyncGraphQLQueryPager Convenience Functions

public extension AsyncGraphQLQueryPager {

  // MARK: Offset Initializers

  static func makeForwardOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Forward
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

  static func makeForwardOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Forward,
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

  static func makeForwardOffsetQueryPager<InitialQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Forward?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Forward,
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

  static func makeReverseOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Reverse
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

  static func makeReverseOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Reverse,
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

  static func makeReverseOffsetQueryPager<InitialQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Reverse?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Reverse,
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

  static func makeBidirectionalOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    start: OffsetPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Bidirectional
  ) async -> AsyncGraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    await AsyncGraphQLQueryPager(pager: AsyncGraphQLQueryPagerCoordinator(
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
    ))
  }

  static func makeBidirectionalOffsetQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    start: OffsetPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Bidirectional,
    transform: @escaping ([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data]) throws -> Model
  ) async -> AsyncGraphQLQueryPager {
    await AsyncGraphQLQueryPager(
      pager: AsyncGraphQLQueryPagerCoordinator(
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
      ),
      transform: transform
    )
  }

  static func makeBidirectionalOffsetQueryPager<InitialQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    start: OffsetPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (OffsetPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> OffsetPagination.Bidirectional,
    transform: @escaping (InitialQuery.Data) throws -> Model
  ) async -> AsyncGraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    await AsyncGraphQLQueryPager(
      pager: AsyncGraphQLQueryPagerCoordinator(
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
      ),
      initialTransform: transform,
      pageTransform: transform
    )
  }

  // MARK: CursorBasedPagination.Forward Initializers

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

  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> PaginatedQuery
  ) async -> AsyncGraphQLQueryPager where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
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

  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> PaginatedQuery,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
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

  static func makeForwardCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Forward,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Forward,
    nextPageResolver: @escaping (CursorBasedPagination.Forward) -> PaginatedQuery,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
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

  // MARK: CursorBasedPagination.Reverse Initializers

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

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Reverse,
    nextPageResolver: @escaping (CursorBasedPagination.Reverse) -> PaginatedQuery
  ) async -> AsyncGraphQLQueryPager where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
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

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractPreviousPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Reverse,
    previousPageResolver: @escaping (CursorBasedPagination.Reverse) -> PaginatedQuery,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
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

  static func makeReverseCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Reverse,
    extractPreviousPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Reverse,
    previousPageResolver: @escaping (CursorBasedPagination.Reverse) -> PaginatedQuery,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
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

  // MARK: CursorBasedPagination.Bidirectional Initializers

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    start: CursorBasedPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional
  ) async -> AsyncGraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    await AsyncGraphQLQueryPager(pager: .makeBidirectionalCursorQueryPager(
      client: client,
      start: start,
      watcherDispatchQueue: watcherDispatchQueue,
      queryProvider: queryProvider,
      previousQueryProvider: previousQueryProvider,
      extractPageInfo: extractPageInfo
    ))
  }

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    start: CursorBasedPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    transform: @escaping ([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data]) throws -> Model
  ) async -> AsyncGraphQLQueryPager {
    await AsyncGraphQLQueryPager(
      pager: .makeBidirectionalCursorQueryPager(
        client: client,
        start: start,
        watcherDispatchQueue: watcherDispatchQueue,
        queryProvider: queryProvider,
        previousQueryProvider: previousQueryProvider,
        extractPageInfo: extractPageInfo
      ),
      transform: transform
    )
  }

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    start: CursorBasedPagination.Bidirectional?,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    transform: @escaping (InitialQuery.Data) throws -> Model
  ) async -> AsyncGraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    await AsyncGraphQLQueryPager(
      pager: .makeBidirectionalCursorQueryPager(
        client: client,
        start: start,
        watcherDispatchQueue: watcherDispatchQueue,
        queryProvider: queryProvider,
        previousQueryProvider: previousQueryProvider,
        extractPageInfo: extractPageInfo
      ),
      initialTransform: transform,
      pageTransform: transform
    )
  }

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    extractPaginatedPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Bidirectional
  ) async -> AsyncGraphQLQueryPager where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    await AsyncGraphQLQueryPager(pager: .makeBidirectionalCursorQueryPager(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
      queryProvider: queryProvider,
      previousQueryProvider: previousQueryProvider,
      extractInitialPageInfo: extractInitialPageInfo,
      extractPaginatedPageInfo: extractPaginatedPageInfo
    ))
  }

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    extractPaginatedPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Bidirectional,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
  ) async -> AsyncGraphQLQueryPager {
    await AsyncGraphQLQueryPager(
      pager: .makeBidirectionalCursorQueryPager(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        queryProvider: queryProvider,
        previousQueryProvider: previousQueryProvider,
        extractInitialPageInfo: extractInitialPageInfo,
        extractPaginatedPageInfo: extractPaginatedPageInfo
      ),
      transform: transform
    )
  }

  static func makeBidirectionalCursorQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, T>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    queryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    previousQueryProvider: @escaping (CursorBasedPagination.Bidirectional?) -> PaginatedQuery,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> CursorBasedPagination.Bidirectional,
    extractPaginatedPageInfo: @escaping (PaginatedQuery.Data) -> CursorBasedPagination.Bidirectional,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
  ) async -> AsyncGraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    await AsyncGraphQLQueryPager(
      pager: .makeBidirectionalCursorQueryPager(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        queryProvider: queryProvider,
        previousQueryProvider: previousQueryProvider,
        extractInitialPageInfo: extractInitialPageInfo,
        extractPaginatedPageInfo: extractPaginatedPageInfo
      ),
      initialTransform: initialTransform,
      pageTransform: pageTransform
    )
  }
}

// MARK: - Internal helpers

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

private func pageExtraction<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, P: PaginationInfo, T>(
  initialTransfom: @escaping (InitialQuery.Data) -> P,
  paginatedTransform: @escaping (PaginatedQuery.Data) -> P
) -> (PageExtractionData<InitialQuery, PaginatedQuery, T>) -> P {
  { extractionData in
    switch extractionData {
    case .initial(let value, _):
      return initialTransfom(value)
    case .paginated(let value, _):
      return paginatedTransform(value)
    }
  }
}

private func pageExtraction<InitialQuery: GraphQLQuery, P: PaginationInfo, T>(
  transform: @escaping (InitialQuery.Data) -> P
) -> (PageExtractionData<InitialQuery, InitialQuery, T>) -> P {
  { extractionData in
    switch extractionData {
    case .initial(let value, _), .paginated(let value, _):
      return transform(value)
    }
  }
}
