import Apollo
import ApolloAPI
import Combine
import Foundation

public protocol PagerType {
  associatedtype InitialQuery: GraphQLQuery
  associatedtype PaginatedQuery: GraphQLQuery
  typealias Output = (InitialQuery.Data, [PaginatedQuery.Data], UpdateSource)
  
  func canLoadNext() -> Bool
  func cancel()
  func loadMore(
    cachePolicy: CachePolicy,
    completion: (@MainActor () -> Void)?
  ) throws
  func refetch(cachePolicy: CachePolicy)
}

public class GraphQLQueryPagerWrapper<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>: PagerType {
  private let pager: GraphQLQueryPager<InitialQuery, PaginatedQuery>
  private var cancellables: [AnyCancellable] = []
  
  private enum PhonyError: Error {
    case workaround
  }
  
  public init<P: PaginationInfo>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    extractPageInfo: @escaping (PageExtractionData<InitialQuery, PaginatedQuery>) -> P,
    nextPageResolver: @escaping (P) -> PaginatedQuery
  ) {
    pager = .init(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: extractPageInfo,
      nextPageResolver: nextPageResolver
    )
  }
  
  deinit {
    cancellables.forEach { $0.cancel() }
  }
  
  public init(pager: GraphQLQueryPager<InitialQuery, PaginatedQuery>) {
    self.pager = pager
  }
  
  public func subscribe(onUpdate: @MainActor @escaping (Result<Output, Error>) -> Void) {
    Task {
      await pager.subscribe(onUpdate: onUpdate)
        .store(in: &cancellables)
    }
  }
  
  public func canLoadNext() -> Bool {
    do {
      try _canLoadNext()
      return true
    } catch {
      return false
    }
  }
  
  private func _canLoadNext() throws {
    Task {
      let canLoadNext = await pager.canLoadNext()
      if !canLoadNext { throw PhonyError.workaround }
    }
  }
  
  public func cancel() {
    Task {
      await pager.cancel()
    }
  }
  
  public func loadMore(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: (@MainActor () -> Void)? = nil
  ) throws {
    Task {
      try await pager.loadMore(cachePolicy: cachePolicy)
      await completion?()
    }
  }
  
  public func refetch(cachePolicy: CachePolicy = .returnCacheDataAndFetch) {
    Task {
      await pager.refetch(cachePolicy: cachePolicy)
    }
  }
}
