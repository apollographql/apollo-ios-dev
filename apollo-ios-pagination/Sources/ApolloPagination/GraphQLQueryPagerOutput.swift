import Apollo
import ApolloAPI
import Foundation

/// A struct which contains the outputs of pagination
public struct PaginationOutput<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>: Hashable, Sendable {
  /// An array of previous pages, in pagination order
  /// Earlier pages come first in the array.
  public let previousPages: [GraphQLResponse<PaginatedQuery>]

  /// The initial page that we fetched.
  public let initialPage: GraphQLResponse<InitialQuery>?

  /// An array of pages after the initial page.
  public let nextPages: [GraphQLResponse<PaginatedQuery>]

  public let lastUpdatedPage: QueryWrapper

  public init(
    previousPages: [GraphQLResponse<PaginatedQuery>],
    initialPage: GraphQLResponse<InitialQuery>?,
    nextPages: [GraphQLResponse<PaginatedQuery>],
    lastUpdatedPage: QueryWrapper
  ) {
    self.previousPages = previousPages
    self.initialPage = initialPage
    self.nextPages = nextPages
    self.lastUpdatedPage = lastUpdatedPage
  }

  public var allErrors: [GraphQLError] {
    (previousPages.compactMap(\.errors) + [initialPage?.errors].compactMap { $0 } + nextPages.compactMap(\.errors)).flatMap { $0 }
  }
}

extension PaginationOutput {
  public enum QueryWrapper: Hashable, Sendable {
    case initial(GraphQLResponse<InitialQuery>)
    case paginated(GraphQLResponse<PaginatedQuery>)
  }
}

extension PaginationOutput.QueryWrapper {
  public var errors: [GraphQLError]? {
    switch self {
    case .initial(let result):
      result.errors
    case .paginated(let result):
      result.errors
    }
  }

  public var source: UpdateSource {
    switch self {
    case .initial(let result):
      result.updateSource
    case .paginated(let result):
      result.updateSource
    }
  }
}

extension PaginationOutput.QueryWrapper where InitialQuery == PaginatedQuery {
  public var data: InitialQuery.Data? {
    switch self {
    case .initial(let result):
      result.data
    case .paginated(let result):
      result.data
    }
  }
}

extension PaginationOutput where InitialQuery == PaginatedQuery {
  public var allData: [InitialQuery.Data] {
    previousPages.compactMap(\.data) + [initialPage?.data].compactMap { $0 } + nextPages.compactMap(\.data)
  }

  public var allPages: [GraphQLResponse<InitialQuery>] {
    previousPages + [initialPage].compactMap { $0 } + nextPages
  }
}
