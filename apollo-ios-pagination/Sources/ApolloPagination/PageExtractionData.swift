import ApolloAPI

/// The result of either the initial query or the paginated query, for the purpose of extracting a `PageInfo` from it.
public enum PageExtractionData<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery, T> {
  case initial(InitialQuery.Data, T)
  case paginated(PaginatedQuery.Data, T)
}
