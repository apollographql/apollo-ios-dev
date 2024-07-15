@testable import ApolloPagination

extension GraphQLQueryPagerCoordinator {
  func eraseToAnyPager<T>(
    transform: @escaping (PaginationOutput<InitialQuery, PaginatedQuery>) throws -> T
  ) -> GraphQLQueryPager<T> {
    GraphQLQueryPager(pager: self, transform: transform)
  }

  func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    transform: @escaping (PaginationOutput<InitialQuery, InitialQuery>) throws -> S
  ) -> GraphQLQueryPager<S> where InitialQuery == PaginatedQuery, T == S.Element {
    GraphQLQueryPager(
      pager: self,
      transform: transform
    )
  }
}

extension AsyncGraphQLQueryPagerCoordinator {
  nonisolated func eraseToAnyPager<T>(
    transform: @escaping (PaginationOutput<InitialQuery, PaginatedQuery>) throws -> T
  ) -> AsyncGraphQLQueryPager<T> {
    AsyncGraphQLQueryPager(
      pager: self,
      transform: transform
    )
  }

  nonisolated func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    transform: @escaping (PaginationOutput<InitialQuery, InitialQuery>) throws -> S
  ) -> AsyncGraphQLQueryPager<S> where InitialQuery == PaginatedQuery, T == S.Element {
    AsyncGraphQLQueryPager(
      pager: self,
      transform: transform
    )
  }
}
