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

  public let mostRecentPage: QueryWrapper

  public init(
    previousPages: [GraphQLResult<PaginatedQuery.Data>],
    initialPage: GraphQLResult<InitialQuery.Data>?,
    nextPages: [GraphQLResult<PaginatedQuery.Data>],
    mostRecentPage: QueryWrapper
  ) {
    self.previousPages = previousPages
    self.initialPage = initialPage
    self.nextPages = nextPages
    self.mostRecentPage = mostRecentPage
  }

  public var allErrors: [GraphQLError] {
    (previousPages.compactMap(\.errors) + [initialPage?.errors].compactMap { $0 } + nextPages.compactMap(\.errors)).flatMap { $0 }
  }
}

extension PaginationOutput {
  public enum QueryWrapper: Hashable {
    case initial(GraphQLResult<InitialQuery.Data>)
    case paginated(GraphQLResult<PaginatedQuery.Data>)
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

  public var allPages: [GraphQLResult<InitialQuery.Data>] {
    previousPages + [initialPage].compactMap { $0 } + nextPages
  }
}
