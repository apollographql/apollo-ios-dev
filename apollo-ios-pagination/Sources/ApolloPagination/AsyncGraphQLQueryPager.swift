import Apollo
import ApolloAPI
@preconcurrency import Combine
import Foundation

/// Type-erases a query pager, transforming data from a generic type to a specific type, often a view model or array
/// of view models.
public final class GraphQLQueryPager<Model>: Publisher, @unchecked Sendable {
  public typealias Failure = Never
  public typealias Output = Result<Model, any Error>
  let _subject: CurrentValueSubject<Output?, Never> = .init(nil)
  var publisher: AnyPublisher<Output, Never> { _subject.compactMap({ $0 }).eraseToAnyPublisher() }
  @Atomic public var cancellables: Set<AnyCancellable> = []
  public let pager: any PagerType

  public var canLoadNext: Bool { get async { await pager.canLoadNext } }
  public var canLoadPrevious: Bool { get async { await pager.canLoadPrevious } }

  init<Pager: GraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager,
    transform: @escaping @Sendable (PaginationOutput<InitialQuery, PaginatedQuery>) throws -> Model
  ) {
    self.pager = pager
    Task {
      let cancellable = await pager.subscribe { [weak self] result in
        guard let self else { return }
        let returnValue: Output

        switch result {
        case let .success(output):
          do {
            let transformedModels = try transform(output)
            returnValue = .success(transformedModels)
          } catch {
            returnValue = .failure(error)
          }
        case let .failure(error):
          returnValue = .failure(error)
        }

        _subject.send(returnValue)
      }
      _ = $cancellables.mutate { $0.insert(cancellable) }
    }
  }

  init<Pager: GraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager
  ) where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    self.pager = pager
    Task {
      let cancellable = await pager.subscribe { [weak self] result in
        guard let self else { return }
        _subject.send(result)
      }
      _ = $cancellables.mutate { $0.insert(cancellable) }
    }
  }

  /// Initialize an `AsyncGraphQLQueryPager` that outputs a `PaginationOutput<InitialQuery, PaginatedQuery>`.
  /// - Parameters:
  ///   - client: Apollo client type
  ///   - initialQuery: The query to call for the first page of pagination. May be a separate type of query than the pagination query.
  ///   - watcherDispatchQueue: The queue that the underlying `GraphQLQueryWatcher`s respond on. Defaults to `main`.
  ///   - extractPageInfo: A user-input closure that instructs the pager on how to extract `P`, a `PaginationInfo` type, from the `Data` of either the `InitialQuery` or `PaginatedQuery`.
  ///   - pageResolver: A user-input closure that instructs the pager on how to create a new `PaginatedQuery` given a `PaginationInfo` and a `PaginationDirection`.
  public convenience init<
    P: PaginationInfo,
    InitialQuery: GraphQLQuery,
    PaginatedQuery: GraphQLQuery
  >(
    client: ApolloClient,
    initialQuery: InitialQuery,
    extractPageInfo: @escaping @Sendable (PageExtractionData<InitialQuery, PaginatedQuery, Model?>) -> P,
    pageResolver: (@Sendable (P, PaginationDirection) -> PaginatedQuery?)?
  ) where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    let pager = GraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: extractPageInfo,
      pageResolver: pageResolver
    )
    self.init(pager: pager)
  }

  /// Initialize an `AsyncGraphQLQueryPager` that outputs a user-defined `Model`, the result of the `transform` argument.
  /// - Parameters:
  ///   - client: Apollo client type
  ///   - initialQuery: The query to call for the first page of pagination. May be a separate type of query than the pagination query.
  ///   - watcherDispatchQueue: The queue that the underlying `GraphQLQueryWatcher`s respond on. Defaults to `main`.
  ///   - extractPageInfo: A user-input closure that instructs the pager on how to extract `P`, a `PaginationInfo` type, from the `Data` of either the `InitialQuery` or `PaginatedQuery`.
  ///   - pageResolver: A user-input closure that instructs the pager on how to create a new `PaginatedQuery` given a `PaginationInfo` and a `PaginationDirection`.
  ///   - transform: Transforms the `PaginationOutput` into a `Model` type.
  public convenience init<
    P: PaginationInfo,
    InitialQuery: GraphQLQuery,
    PaginatedQuery: GraphQLQuery
  >(
    client: ApolloClient,
    initialQuery: InitialQuery,
    extractPageInfo: @escaping @Sendable (PageExtractionData<InitialQuery, PaginatedQuery, PaginationOutput<InitialQuery, PaginatedQuery>?>) -> P,
    pageResolver: (@Sendable (P, PaginationDirection) -> PaginatedQuery?)?,
    transform: @escaping @Sendable (PaginationOutput<InitialQuery, PaginatedQuery>) throws -> Model
  ) {
    let pager = GraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: extractPageInfo,
      pageResolver: pageResolver
    )
    self.init(pager: pager, transform: transform)
  }

  // MARK: Load Next

  /// Load the next page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `cacheAndNetwork`.
  public func loadNext(
    cachePolicy: CachePolicy.Query.CacheAndNetwork = .cacheAndNetwork
  ) async throws {
    try await self.loadNext(fetchBehavior: cachePolicy.toFetchBehavior())
  }

  /// Load the next page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `cacheAndNetwork`.
  public func loadNext(
    cachePolicy: CachePolicy.Query.CacheOnly
  ) async throws {
    try await self.loadNext(fetchBehavior: cachePolicy.toFetchBehavior())
  }

  /// Load the next page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `cacheAndNetwork`.
  public func loadNext(
    cachePolicy: CachePolicy.Query.SingleResponse
  ) async throws {
    try await self.loadNext(fetchBehavior: cachePolicy.toFetchBehavior())
  }

  /// Load the next page, if available.
  /// - Parameters:
  ///   - fetchBehavior: The Apollo `FetchBehavior` to use.
  public func loadNext(
    fetchBehavior: FetchBehavior
  ) async throws {
    try await pager.loadNext(fetchBehavior: fetchBehavior)
  }

  // MARK: Load Previous

  /// Load the previous page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `cacheAndNetwork`.
  public func loadPrevious(
    cachePolicy: CachePolicy.Query.CacheAndNetwork = .cacheAndNetwork
  ) async throws {
    try await self.loadPrevious(fetchBehavior: cachePolicy.toFetchBehavior())
  }

  /// Load the previous page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `cacheAndNetwork`.
  public func loadPrevious(
    cachePolicy: CachePolicy.Query.CacheOnly
  ) async throws {
    try await self.loadPrevious(fetchBehavior: cachePolicy.toFetchBehavior())
  }

  /// Load the previous page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `cacheAndNetwork`.
  public func loadPrevious(
    cachePolicy: CachePolicy.Query.SingleResponse
  ) async throws {
    try await self.loadPrevious(fetchBehavior: cachePolicy.toFetchBehavior())
  }

  /// Load the previous page, if available.
  /// - Parameters:
  ///   - fetchBehavior: The Apollo `FetchBehavior` to use.
  public func loadPrevious(
    fetchBehavior: FetchBehavior
  ) async throws {
    try await pager.loadPrevious(fetchBehavior: fetchBehavior)
  }

  // MARK: Load All

  /// Loads all pages. Does not output a value until all pages have loaded.
  /// - Parameters:
  ///   - fetchFromInitialPage: Pass true to begin loading from the initial page; otherwise pass false.  Defaults to `true`.  **NOTE**: Loading all pages with this value set to `false` requires that the initial page has already been loaded previously.
  public func loadAll(
    fetchFromInitialPage: Bool = true
  ) async throws {
    try await pager.loadAll(fetchFromInitialPage: fetchFromInitialPage)
  }

  // MARK: Refetch

  /// Discards pagination state and fetches the first page from scratch.
  /// - Parameter cachePolicy: The apollo cache policy to trigger the first fetch with. Defaults to `networkOnly`.
  public func refetch(cachePolicy: CachePolicy.Query.SingleResponse = .networkOnly) async {
    await self.refetch(fetchBehavior: cachePolicy.toFetchBehavior())
  }

  /// Discards pagination state and fetches the first page from scratch.
  /// - Parameter cachePolicy: The apollo cache policy to trigger the first fetch with. Defaults to `networkOnly`.
  public func refetch(cachePolicy: CachePolicy.Query.CacheOnly) async {
    await self.refetch(fetchBehavior: cachePolicy.toFetchBehavior())
  }

  /// Discards pagination state and fetches the first page from scratch.
  /// - Parameter cachePolicy: The apollo cache policy to trigger the first fetch with. Defaults to `networkOnly`.
  public func refetch(cachePolicy: CachePolicy.Query.CacheAndNetwork) async {
    await self.refetch(fetchBehavior: cachePolicy.toFetchBehavior())
  }

  /// Discards pagination state and fetches the first page from scratch.
  /// - Parameter fetchBehavior: The Apollo `FetchBehavior` to use.
  public func refetch(fetchBehavior: FetchBehavior) async {
    await pager.refetch(fetchBehavior: fetchBehavior)
  }

  /// Fetches the first page.
  public func fetch() async {
    await pager.fetch()
  }

  /// Resets pagination state and cancels in-flight updates from the pager.
  public func reset() async {
    await pager.reset()
  }

  public func receive<S>(
    subscriber: S
  ) where S: Subscriber, Never == S.Failure, Result<Model, any Error> == S.Input {
    publisher.subscribe(subscriber)
  }
}
