import ApolloAPI

/// The result of either the initial query or the paginated query, for the purpose of extracting a `PageInfo` from it.
public enum PageExtractionData<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery> {
  case initial(InitialQuery.Data)
  case paginated(PaginatedQuery.Data)
}
