import ApolloAPI
import Foundation

/// A struct which contains the outputs of pagination
public struct PaginationOutput<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>: Hashable {
  /// An array of previous pages, in pagination order
  /// Earlier pages come first in the array.
  public let previousPages: [PaginatedQuery.Data]

  /// The initial page that we fetched.
  public let initialPage: InitialQuery.Data

  /// An array of pages after the initial page.
  public let nextPages: [PaginatedQuery.Data]

  /// The source of the most recent `Output`: either from the cache or server.
  public let updateSource: UpdateSource

  public init(
    previousPages: [PaginatedQuery.Data],
    initialPage: InitialQuery.Data,
    nextPages: [PaginatedQuery.Data],
    updateSource: UpdateSource
  ) {
    self.previousPages = previousPages
    self.initialPage = initialPage
    self.nextPages = nextPages
    self.updateSource = updateSource
  }
}
