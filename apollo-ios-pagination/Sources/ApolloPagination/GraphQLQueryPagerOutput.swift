import Apollo
import ApolloAPI
import Foundation

/// A struct which contains the outputs of pagination
public struct PaginationOutput<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>: Hashable {
  /// An array of previous pages, in pagination order
  /// Earlier pages come first in the array.
  public let previousPages: [GraphQLResult<PaginatedQuery.Data>]

  /// The initial page that we fetched.
  public let initialPage: GraphQLResult<InitialQuery.Data>?

  /// An array of pages after the initial page.
  public let nextPages: [GraphQLResult<PaginatedQuery.Data>]

  public let mostRecentSource: UpdateSource?

  public init(
    previousPages: [GraphQLResult<PaginatedQuery.Data>],
    initialPage: GraphQLResult<InitialQuery.Data>?,
    nextPages: [GraphQLResult<PaginatedQuery.Data>],
    mostRecentSource: UpdateSource?
  ) {
    self.previousPages = previousPages
    self.initialPage = initialPage
    self.nextPages = nextPages
    self.mostRecentSource = mostRecentSource
  }

  public var allErrors: [GraphQLError] {
    (previousPages.compactMap(\.errors) + [initialPage?.errors].compactMap { $0 } + nextPages.compactMap(\.errors)).flatMap { $0 }
  }
}

extension PaginationOutput where InitialQuery == PaginatedQuery {
  public var allData: [InitialQuery.Data] {
    previousPages.compactMap(\.data) + [initialPage?.data].compactMap { $0 } + nextPages.compactMap(\.data)
  }

  public var allPages: [GraphQLResult<InitialQuery.Data>] {
    previousPages + [initialPage].compactMap { $0 } + nextPages
  }
}
