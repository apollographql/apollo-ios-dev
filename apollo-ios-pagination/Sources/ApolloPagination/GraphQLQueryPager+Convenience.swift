import Apollo
import ApolloAPI
import Foundation

// MARK: - GraphQLQueryPager Convenience Functions

public extension GraphQLQueryPager {

  /// Convenience initializer for creating a pager that has a single query and does not 
  /// transform output responses.
  convenience init<InitialQuery: GraphQLQuery, P: PaginationInfo>(
    client: any ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    initialQuery: InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> P,
    pageResolver: @escaping (P, PaginationDirection) -> InitialQuery?
  ) where Model == PaginationOutput<InitialQuery, InitialQuery> {
    self.init(
      pager: GraphQLQueryPagerCoordinator(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(transform: extractPageInfo),
        pageResolver: pageResolver
      ))
  }

  /// Convenience initializer for creating a multi-query pager that does not
  /// transform output responses.
  convenience init<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, P: PaginationInfo>(
    client: any ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> P,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> P,
    pageResolver: @escaping (P, PaginationDirection) -> PaginatedQuery?
  ) where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    self.init(
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
}

// MARK: - AsyncGraphQLQueryPager Convenience Functions

public extension AsyncGraphQLQueryPager {
  /// Convenience initializer for creating a pager that has a single query and does not
  /// transform output responses.
  convenience init<InitialQuery: GraphQLQuery, P: PaginationInfo>(
    client: any ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    initialQuery: InitialQuery,
    extractPageInfo: @escaping (InitialQuery.Data) -> P,
    pageResolver: @escaping (P, PaginationDirection) -> InitialQuery?
  ) where Model == PaginationOutput<InitialQuery, InitialQuery> {
    self.init(
      pager: AsyncGraphQLQueryPagerCoordinator(
        client: client,
        initialQuery: initialQuery,
        watcherDispatchQueue: watcherDispatchQueue,
        extractPageInfo: pageExtraction(transform: extractPageInfo),
        pageResolver: pageResolver
      ))
  }

  /// Convenience initializer for creating a multi-query pager that does not 
  /// transform output responses.
  convenience init<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, P: PaginationInfo>(
    client: any ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractInitialPageInfo: @escaping (InitialQuery.Data) -> P,
    extractNextPageInfo: @escaping (PaginatedQuery.Data) -> P,
    pageResolver: @escaping (P, PaginationDirection) -> PaginatedQuery?
  ) where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    self.init(
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
