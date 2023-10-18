import Apollo
import ApolloAPI
import Combine
import Foundation

/// The result of either the initial query or the paginated query, for the purpose of extracting a `PageInfo` from it.
public enum PageExtractionData<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery> {
  // This class is outside of the scope of the `GraphQLQueryPager` such that it can be shared between it and the `Actor`.
  case initial(InitialQuery.Data)
  case paginated(PaginatedQuery.Data)
}

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
  func fetch()
}

/// Handles pagination in the queue by managing multiple query watchers.
public class GraphQLQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>: PagerType {
  public typealias Output = (InitialQuery.Data, [PaginatedQuery.Data], UpdateSource)

  private let pager: Actor
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

  public init(pager: Actor) {
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

  public func refetch(cachePolicy: CachePolicy = .fetchIgnoringCacheData) {
    Task {
      await pager.refetch(cachePolicy: cachePolicy)
    }
  }

  public func fetch() {
    Task {
      await pager.fetch()
    }
  }
}

extension GraphQLQueryPager {
  public actor Actor {
    private let client: any ApolloClientProtocol
    private var firstPageWatcher: GraphQLQueryWatcher<InitialQuery>?
    private var nextPageWatchers: [GraphQLQueryWatcher<PaginatedQuery>] = []
    private let initialQuery: InitialQuery
    let nextPageResolver: (PaginationInfo) -> PaginatedQuery?
    let extractPageInfo: (PageExtractionData<InitialQuery, PaginatedQuery>) -> PaginationInfo
    var currentPageInfo: PaginationInfo? {
      guard let last = pageOrder.last else {
        return initialPageResult.flatMap { extractPageInfo(.initial($0)) }
      }
      if let data = varMap[last] {
        return extractPageInfo(.paginated(data))
      } else if let initialPageResult {
        return extractPageInfo(.initial(initialPageResult))
      } else {
        return nil
      }
    }

    @Published var currentValue: Result<Output, Error>?
    private var subscribers: [AnyCancellable] = []

    var initialPageResult: InitialQuery.Data?
    var latest: (InitialQuery.Data, [PaginatedQuery.Data])? {
      guard let initialPageResult else { return nil }
      return (initialPageResult, pageOrder.compactMap({ varMap[$0] }))
    }

    /// Array of page info used to fetch next pages. Maintains an order of values used to fetch each page in a connection.
    var pageOrder = [AnyHashable]()

    /// Maps each query variable set to latest results from internal watchers.
    var varMap: [AnyHashable: PaginatedQuery.Data] = [:]

    var activeTask: Task<Void, Never>?

    /// Designated Initializer
    /// - Parameters:
    ///   - client: Apollo Client
    ///   - initialQuery: The initial query that is being watched
    ///   - extractPageInfo: The `PageInfo` derived from `PageExtractionData`
    ///   - nextPageResolver: The resolver that can derive the query for loading more. This can be a different query than the `initialQuery`.
    ///   - onError: The callback when there is an error.
    public init<P: PaginationInfo>(
      client: ApolloClientProtocol,
      initialQuery: InitialQuery,
      extractPageInfo: @escaping (PageExtractionData<InitialQuery, PaginatedQuery>) -> P,
      nextPageResolver: @escaping (P) -> PaginatedQuery
    ) {
      self.client = client
      self.initialQuery = initialQuery
      self.extractPageInfo = extractPageInfo
      self.nextPageResolver = { page in
        guard let page = page as? P else { return nil }
        return nextPageResolver(page)
      }
    }

    deinit {
      nextPageWatchers.forEach { $0.cancel() }
      firstPageWatcher?.cancel()
      subscribers.forEach { $0.cancel() }
    }

    // MARK: - Public API

    /// A convenience wrapper around the asynchronous `loadMore` function.
    public func loadMore(
      cachePolicy: CachePolicy = .fetchIgnoringCacheData,
      completion: (() -> Void)? = nil
    ) throws {
      Task {
        try await loadMore(cachePolicy: cachePolicy)
        completion?()
      }
    }

    /// Loads the next page, using the currently saved pagination information to do so.
    /// Thread-safe, and supports multiple subscribers calling from multiple threads.
    /// **NOTE**: Requires having already called `fetch` or `refetch` prior to this call.
    /// - Parameters:
    ///   - cachePolicy: Preferred cache policy for fetching subsequent pages. Defaults to `fetchIgnoringCacheData`.
    public func loadMore(
      cachePolicy: CachePolicy = .fetchIgnoringCacheData
    ) async throws {
      guard let currentPageInfo else {
        assertionFailure("No page info detected -- are you calling `loadMore` prior to calling the initial fetch?")
        throw PaginationError.missingInitialPage
      }
      guard let nextPageQuery = nextPageResolver(currentPageInfo),
            currentPageInfo.canLoadMore
      else { throw PaginationError.pageHasNoMoreContent }
      guard activeTask == nil else {
        throw PaginationError.loadInProgress
      }

      activeTask = Task {
        let publisher = CurrentValueSubject<Void, Never>(())
        await withCheckedContinuation { continuation in
          let watcher = GraphQLQueryWatcher(client: client, query: nextPageQuery) { result in
            self.onSubsequentFetch(
              cachePolicy: cachePolicy,
              result: result,
              publisher: publisher,
              query: nextPageQuery
            )
          }
          nextPageWatchers.append(watcher)
          publisher.sink(receiveCompletion: { _ in
            continuation.resume(with: .success(()))
            self.onTaskCancellation()
          }, receiveValue: { })
          .store(in: &subscribers)
          watcher.refetch(cachePolicy: cachePolicy)
        }
      }
      await activeTask?.value
    }

    public func subscribe(onUpdate: @MainActor @escaping (Result<Output, Error>) -> Void) -> AnyCancellable {
      $currentValue.compactMap({ $0 }).sink { result in
        Task {
          await onUpdate(result)
        }
      }
    }

    /// Reloads all data, starting at the first query, resetting pagination state.
    /// - Parameter cachePolicy: Preferred cache policy for first-page fetches. Defaults to `returnCacheDataAndFetch`
    public func refetch(cachePolicy: CachePolicy = .fetchIgnoringCacheData) {
      cancel()
      if firstPageWatcher == nil {
        assertionFailure("To create consistent product behaviors, calling `fetch` before calling `refetch` will use cached data while still refreshing.")
        self.firstPageWatcher = createInitialPageWatcher()
      }
      firstPageWatcher?.refetch(cachePolicy: cachePolicy)
    }

    /// Loads the first page of results, returning cached data initially, should it exist.
    public func fetch() {
      cancel()
      if firstPageWatcher == nil {
        self.firstPageWatcher = createInitialPageWatcher()
      }
      firstPageWatcher?.refetch(cachePolicy: .returnCacheDataAndFetch)
    }

    /// Cancel any in progress fetching operations and unsubscribe from the store.
    public func cancel() {
      nextPageWatchers.forEach { $0.cancel() }
      nextPageWatchers = []
      firstPageWatcher?.cancel()
      firstPageWatcher = nil

      varMap = [:]
      pageOrder = []
      initialPageResult = nil
      activeTask?.cancel()
      activeTask = nil
      subscribers.forEach { $0.cancel() }
      subscribers.removeAll()
    }

    /// Whether or not we can load more information based on the current page.
    public func canLoadNext() -> Bool {
      currentPageInfo?.canLoadMore ?? false
    }

    // MARK: - Private

    private func onInitialFetch(result: Result<GraphQLResult<InitialQuery.Data>, Error>) {
      switch result {
      case .success(let data):
        self.initialPageResult = data.data
        guard let firstPageData = data.data else { return }
        if let latest = self.latest {
          let (_, nextPage) = latest
          currentValue = .success((firstPageData, nextPage, data.source == .cache ? .cache : .fetch))
        }
      case .failure(let error):
        currentValue = .failure(error)
      }
    }

    private func onSubsequentFetch(
      cachePolicy: CachePolicy,
      result: Result<GraphQLResult<PaginatedQuery.Data>, Error>,
      publisher: CurrentValueSubject<Void, Never>,
      query: PaginatedQuery
    ) {
      switch result {
      case .success(let data):
        guard let nextPageData = data.data else {
          publisher.send(completion: .finished)
          return
        }

        let shouldUpdate: Bool
        if cachePolicy == .returnCacheDataAndFetch && data.source == .cache {
          shouldUpdate = false
        } else {
          shouldUpdate = true
        }
        let variables = query.__variables?.values.compactMap { $0._jsonEncodableValue?._jsonValue } ?? []
        if shouldUpdate {
          self.pageOrder.append(variables)
          publisher.send(completion: .finished)
        }
        self.varMap[variables] = nextPageData

        if let latest = self.latest {
          let (firstPage, nextPage) = latest
          currentValue = .success((firstPage, nextPage, data.source == .cache ? .cache : .fetch))
        }
      case .failure(let error):
        currentValue = .failure(error)
        publisher.send(completion: .finished)
      }
    }

    private func onTaskCancellation() {
      activeTask?.cancel()
      activeTask = nil
    }

    /// Creates a watcher for the first page. Used for the initial load, and subsequent refreshes.
    /// - Returns: A GraphQL watcher for the first page.
    private func createInitialPageWatcher() -> GraphQLQueryWatcher<InitialQuery> {
      GraphQLQueryWatcher(
        client: client,
        query: initialQuery,
        resultHandler: { result in
          Task {
            self.onInitialFetch(result: result)
          }
        }
      )
    }
  }
}
