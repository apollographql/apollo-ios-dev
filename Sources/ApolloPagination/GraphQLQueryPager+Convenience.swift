import Apollo
import ApolloAPI
import Foundation

// MARK: - GraphQLQueryPager Convenience Functions

public extension GraphQLQueryPager {
  /// Convenience function for creating a pager that has a single query and does not transform output responses.
  static func makeQueryPager<InitialQuery: GraphQLQuery, P: PaginationInfo>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    initialQuery: InitialQuery,
    pageResolver: @escaping (P, PaginationDirection) -> InitialQuery?,
    extractPageInfo: @escaping (InitialQuery.Data) -> P
  ) -> GraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    GraphQLQueryPager(pager: GraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
      extractPageInfo: pageExtraction(transform: extractPageInfo),
      pageResolver: pageResolver
    ))
  }

  /// Convenience function for creating a pager that has a single query and transforms output responses.
  static func makeQueryPager<InitialQuery: GraphQLQuery, P: PaginationInfo>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    initialQuery: InitialQuery,
    pageResolver: @escaping (P, PaginationDirection) -> InitialQuery?,
    extractPageInfo: @escaping (InitialQuery.Data) -> P,
    transform: @escaping ([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data]) throws -> Model
  ) -> GraphQLQueryPager {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(transform: extractPageInfo),
        pageResolver: pageResolver
      ),
      transform: transform
    )
  }

  /// Convenience function for creating a pager that has a single query and transforms output responses into a collection.
  static func makeQueryPager<InitialQuery: GraphQLQuery, T, P: PaginationInfo>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    initialQuery: InitialQuery,
    pageResolver: @escaping (P, PaginationDirection) -> InitialQuery?,
    extractPageInfo: @escaping (InitialQuery.Data) -> P,
    transform: @escaping (InitialQuery.Data) throws -> Model
  ) -> GraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    GraphQLQueryPager(
      pager: GraphQLQueryPagerCoordinator(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(transform: extractPageInfo),
        pageResolver: pageResolver
      ),
      initialTransform: transform,
      pageTransform: transform
    )
  }

  /// Convenience function for creating a multi-query pager that does not transform output responses.
  static func makeQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, P: PaginationInfo>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> P,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> P,
    pageResolver: @escaping (P, PaginationDirection) -> PaginatedQuery?
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
        pageResolver: pageResolver
      )
    )
  }

  /// Convenience function for creating a multi-query pager that does transforms output responses.
  static func makeQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, P: PaginationInfo>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> P,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> P,
    pageResolver: @escaping (P, PaginationDirection) -> PaginatedQuery?,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
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
        pageResolver: pageResolver
      ),
      transform: transform
    )
  }

  /// Convenience function for creating a multi-query pager that transforms output responses into collections
  static func makeQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, T, P: PaginationInfo>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> P,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> P,
    pageResolver: @escaping (P, PaginationDirection) -> PaginatedQuery?,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
  ) -> GraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    GraphQLQueryPager(
      pager: .init(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(
          initialTransfom: extractInitialPageInfo,
          paginatedTransform: extractNextPageInfo
        ),
        pageResolver: pageResolver
      ),
      initialTransform: initialTransform,
      pageTransform: pageTransform
    )
  }
}

// MARK: - AsyncGraphQLQueryPager Convenience Functions

public extension AsyncGraphQLQueryPager {
  /// Convenience function for creating a pager that has a single query and does not transform output responses.
  static func makeQueryPager<InitialQuery: GraphQLQuery, P: PaginationInfo>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    initialQuery: InitialQuery,
    pageResolver: @escaping (P, PaginationDirection) -> InitialQuery?,
    extractPageInfo: @escaping (InitialQuery.Data) -> P
  ) async -> AsyncGraphQLQueryPager where Model == PaginationOutput<InitialQuery, InitialQuery> {
    await AsyncGraphQLQueryPager(pager: AsyncGraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
      extractPageInfo: pageExtraction(transform: extractPageInfo),
      pageResolver: pageResolver
    ))
  }

  /// Convenience function for creating a pager that has a single query and transforms output responses.
  static func makeQueryPager<InitialQuery: GraphQLQuery, P: PaginationInfo>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    initialQuery: InitialQuery,
    pageResolver: @escaping (P, PaginationDirection) -> InitialQuery?,
    extractPageInfo: @escaping (InitialQuery.Data) -> P,
    transform: @escaping ([InitialQuery.Data], InitialQuery.Data, [InitialQuery.Data]) throws -> Model
  ) async -> AsyncGraphQLQueryPager {
    await AsyncGraphQLQueryPager(
      pager: AsyncGraphQLQueryPagerCoordinator(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(transform: extractPageInfo),
        pageResolver: pageResolver
      ),
      transform: transform
    )
  }

  /// Convenience function for creating a pager that has a single query and transforms output responses into a collection.
  static func makeQueryPager<InitialQuery: GraphQLQuery, T, P: PaginationInfo>(
    client: ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    initialQuery: InitialQuery,
    pageResolver: @escaping (P, PaginationDirection) -> InitialQuery?,
    extractPageInfo: @escaping (InitialQuery.Data) -> P,
    transform: @escaping (InitialQuery.Data) throws -> Model
  ) async -> AsyncGraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    await AsyncGraphQLQueryPager(
      pager: AsyncGraphQLQueryPagerCoordinator(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(transform: extractPageInfo),
        pageResolver: pageResolver
      ),
      initialTransform: transform,
      pageTransform: transform
    )
  }

  /// Convenience function for creating a multi-query pager that does not transform output responses.
  static func makeQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, P: PaginationInfo>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> P,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> P,
    pageResolver: @escaping (P, PaginationDirection) -> PaginatedQuery?
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
        pageResolver: pageResolver
      )
    )
  }

  /// Convenience function for creating a multi-query pager that does transforms output responses.
  static func makeQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, P: PaginationInfo>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> P,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> P,
    pageResolver: @escaping (P, PaginationDirection) -> PaginatedQuery?,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
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
        pageResolver: pageResolver
      ),
      transform: transform
    )
  }

  /// Convenience function for creating a multi-query pager that transforms output responses into collections
  static func makeQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, T, P: PaginationInfo>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> P,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> P,
    pageResolver: @escaping (P, PaginationDirection) -> PaginatedQuery?,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
  ) async -> AsyncGraphQLQueryPager where Model: RangeReplaceableCollection, T == Model.Element {
    await AsyncGraphQLQueryPager(
      pager: .init(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(
          initialTransfom: extractInitialPageInfo,
          paginatedTransform: extractNextPageInfo
        ),
        pageResolver: pageResolver
      ),
      initialTransform: initialTransform,
      pageTransform: pageTransform
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
