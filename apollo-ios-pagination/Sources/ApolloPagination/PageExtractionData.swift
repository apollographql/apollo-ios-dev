import ApolloAPI

extension GraphQLQueryPager {
  /// The result of either the initial query or the paginated query, for the purpose of extracting a `PageInfo` from it.
  public enum PageExtractionData {
    case initial(InitialQuery.Data)
    case paginated(PaginatedQuery.Data)
  }
}
