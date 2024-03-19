@testable import ApolloPagination

extension GraphQLQueryPagerCoordinator {
  func eraseToAnyPager<T>(
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> T
  ) -> GraphQLQueryPager<T> {
    GraphQLQueryPager(pager: self, transform: transform)
  }

  func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    initialTransform: @escaping (InitialQuery.Data) throws -> S,
    nextPageTransform: @escaping (PaginatedQuery.Data) throws -> S
  ) -> GraphQLQueryPager<S> where T == S.Element {
    GraphQLQueryPager(
      pager: self,
      initialTransform: initialTransform,
      pageTransform: nextPageTransform
    )
  }

  func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    transform: @escaping (InitialQuery.Data) throws -> S
  ) -> GraphQLQueryPager<S> where InitialQuery == PaginatedQuery, T == S.Element {
    GraphQLQueryPager(
      pager: self,
      initialTransform: transform,
      pageTransform: transform
    )
  }
}

extension AsyncGraphQLQueryPagerCoordinator {
  nonisolated func eraseToAnyPager<T>(
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> T
  ) -> AsyncGraphQLQueryPager<T> {
    AsyncGraphQLQueryPager(
      pager: self,
      transform: transform
    )
  }

  nonisolated func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    initialTransform: @escaping (InitialQuery.Data) throws -> S,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> S
  ) -> AsyncGraphQLQueryPager<S> where T == S.Element {
    AsyncGraphQLQueryPager(
      pager: self,
      initialTransform: initialTransform,
      pageTransform: pageTransform
    )
  }

  nonisolated func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    transform: @escaping (InitialQuery.Data) throws -> S
  ) -> AsyncGraphQLQueryPager<S> where InitialQuery == PaginatedQuery, T == S.Element {
    AsyncGraphQLQueryPager(
      pager: self,
      initialTransform: transform,
      pageTransform: transform
    )
  }
}
