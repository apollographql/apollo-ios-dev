import Apollo
import ApolloAPI
import Combine
import Foundation
import OrderedCollections

public protocol PagerType {
  associatedtype InitialQuery: GraphQLQuery
  associatedtype PaginatedQuery: GraphQLQuery

  var canLoadNext: Bool { get }
  var canLoadPrevious: Bool { get }
  func cancel()
  func loadPrevious(
    cachePolicy: CachePolicy,
    completion: (@MainActor (Error?) -> Void)?
  )
  func loadMore(
    cachePolicy: CachePolicy,
    completion: (@MainActor (Error?) -> Void)?
  )
  func loadAll(completion: (@MainActor (Error?) -> Void)?)
  func refetch(cachePolicy: CachePolicy)
  func fetch()
}

/// Handles pagination in the queue by managing multiple query watchers.
public class GraphQLQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>: PagerType {
  public struct Output: Hashable {
    public let previousPages: [PaginatedQuery.Data]
    public let initialPage: InitialQuery.Data
    public let nextPages: [PaginatedQuery.Data]
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

  private let pager: Actor
  private var cancellables: [AnyCancellable] = []
  private var canLoadNextSubject: CurrentValueSubject<Bool, Never> = .init(false)
  private var canLoadPreviousSubject: CurrentValueSubject<Bool, Never> = .init(false)

  /// The result of either the initial query or the paginated query, for the purpose of extracting a `PageInfo` from it.
  public enum PageExtractionData {
    case initial(InitialQuery.Data)
    case paginated(PaginatedQuery.Data)
  }

  public init<P: PaginationInfo>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    extractPageInfo: @escaping (PageExtractionData) -> P,
    nextPageResolver: ((P) -> PaginatedQuery)?,
    previousPageResolver: ((P) -> PaginatedQuery)?
  ) {
    pager = .init(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: extractPageInfo,
      nextPageResolver: nextPageResolver,
      previousPageResolver: previousPageResolver
    )
    Task {
      let previousPageVarMapPublisher = await pager.$previousPageVarMap
      let nextPageVarMapPublisher = await pager.$nextPageVarMap
      let initialPublisher = await pager.$initialPageResult
      previousPageVarMapPublisher.combineLatest(initialPublisher, nextPageVarMapPublisher).sink { [weak self] _ in
        guard let self else { return }
        Task {
          let canLoadNext = await self.pager.canLoadNext
          let canLoadPrevious = await self.pager.canLoadPrevious
          self.canLoadNextSubject.send(canLoadNext)
          self.canLoadPreviousSubject.send(canLoadPrevious)
        }
      }.store(in: &cancellables)
    }
  }

  init(pager: Actor) {
    self.pager = pager
  }

  deinit {
    cancellables.forEach { $0.cancel() }
  }

  public func subscribe(onUpdate: @MainActor @escaping (Result<Output, Error>) -> Void) {
    Task {
      await pager.subscribe(onUpdate: onUpdate)
        .store(in: &cancellables)
    }
  }

  public var canLoadNext: Bool { canLoadNextSubject.value }
  public var canLoadPrevious: Bool { canLoadPreviousSubject.value }

  public func cancel() {
    Task {
      await pager.cancel()
    }
  }

  public func loadPrevious(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: (@MainActor (Error?) -> Void)? = nil
  ) {
    Task<_, Never> {
      do {
        try await pager.loadPrevious(cachePolicy: cachePolicy)
        await completion?(nil)
      } catch {
        await completion?(error)
      }
    }
  }

  public func loadMore(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: (@MainActor (Error?) -> Void)? = nil
  ) {
    Task<_, Never> {
      do {
        try await pager.loadMore(cachePolicy: cachePolicy)
        await completion?(nil)
      } catch {
        await completion?(error)
      }
    }
  }

  public func loadAll(completion: (@MainActor (Error?) -> Void)? = nil) {
    Task<_, Never> {
      do {
        try await pager.loadAll()
        await completion?(nil)
      } catch {
        await completion?(error)
      }
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
  actor Actor {
    private let client: any ApolloClientProtocol
    private var firstPageWatcher: GraphQLQueryWatcher<InitialQuery>?
    private var nextPageWatchers: [GraphQLQueryWatcher<PaginatedQuery>] = []
    private let initialQuery: InitialQuery
    private var isLoadingAll: Bool = false
    let nextPageResolver: (PaginationInfo) -> PaginatedQuery?
    let previousPageResolver: (PaginationInfo) -> PaginatedQuery?
    let extractPageInfo: (PageExtractionData) -> PaginationInfo
    var currentPageInfo: PaginationInfo? { pageTransformation() }
    var previousPageInfo: PaginationInfo? { previousPageTransformation() }

    @Published var currentValue: Result<Output, Error>?
    private var queuedValue: Result<Output, Error>?
    private var subscribers: [AnyCancellable] = []

    @Published var initialPageResult: InitialQuery.Data?
    var latest: ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data])? {
      guard let initialPageResult else { return nil }
      return (
        Array(previousPageVarMap.values).reversed(),
        initialPageResult,
        Array(nextPageVarMap.values)
      )
    }

    /// Maps each query variable set to latest results from internal watchers.
    @Published var nextPageVarMap: OrderedDictionary<AnyHashable, PaginatedQuery.Data> = [:]
    @Published var previousPageVarMap: OrderedDictionary<AnyHashable, PaginatedQuery.Data> = [:]

    private var activeTask: Task<Void, Never>?
    private var initialFetchTask: Task<Void, Never>?
    private var activeContinuation: CheckedContinuation<Void, Never>?
    private var initialContinuation: CheckedContinuation<Void, Never>?

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
      extractPageInfo: @escaping (PageExtractionData) -> P,
      nextPageResolver: ((P) -> PaginatedQuery)?,
      previousPageResolver: ((P) -> PaginatedQuery)?
    ) {
      self.client = client
      self.initialQuery = initialQuery
      self.extractPageInfo = extractPageInfo
      self.nextPageResolver = { page in
        guard let page = page as? P else { return nil }
        return nextPageResolver?(page)
      }
      self.previousPageResolver = { page in
        guard let page = page as? P else { return nil }
        return previousPageResolver?(page)
      }
    }

    deinit {
      nextPageWatchers.forEach { $0.cancel() }
      firstPageWatcher?.cancel()
      subscribers.forEach { $0.cancel() }
      activeContinuation?.resume(with: .success(()))
      initialContinuation?.resume(with: .success(()))
    }

    // MARK: - Public API

    public func loadAll() async throws {
      isLoadingAll = true
      await fetch()

      while currentPageInfo?.canLoadMore ?? false {
        try await loadMore()
      }
      while previousPageInfo?.canLoadPrevious ?? false {
        try await loadPrevious()
      }
      isLoadingAll = false
      if let queuedValue {
        currentValue = queuedValue
      }
      queuedValue = nil
    }

    public func loadPrevious(
      cachePolicy: CachePolicy = .fetchIgnoringCacheData
    ) async throws {
      guard let previousPageInfo else {
        assertionFailure("No page info detected -- are you calling `loadMore` prior to calling the initial fetch?")
        throw PaginationError.missingInitialPage
      }
      guard let previousPageQuery = previousPageResolver(previousPageInfo),
            previousPageInfo.canLoadPrevious
      else { throw PaginationError.pageHasNoMoreContent }
      guard activeTask == nil, activeContinuation == nil else {
        throw PaginationError.loadInProgress
      }

      let task = Task {
        let publisher = CurrentValueSubject<Void, Never>(())
        await withCheckedContinuation { continuation in
          activeContinuation = continuation
          let watcher = GraphQLQueryWatcher(client: client, query: previousPageQuery) { [weak self] result in
            guard let self else { return continuation.resume() }
            Task {
              await self.onPreviousFetch(
                cachePolicy: cachePolicy,
                result: result,
                publisher: publisher,
                query: previousPageQuery
              )
            }
          }
          nextPageWatchers.append(watcher)
          publisher.sink(receiveCompletion: { [weak self] _ in
            guard let self else { return continuation.resume() }
            Task {
              await self.continuationResumption()
              await self.onTaskCancellation()
            }
          }, receiveValue: { })
          .store(in: &subscribers)
          watcher.refetch(cachePolicy: cachePolicy)
        }
      }
      activeTask = task
      await task.value
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
      guard activeTask == nil, activeContinuation == nil else {
        throw PaginationError.loadInProgress
      }

      let task = Task {
        let publisher = CurrentValueSubject<Void, Never>(())
        await withCheckedContinuation { continuation in
          activeContinuation = continuation
          let watcher = GraphQLQueryWatcher(client: client, query: nextPageQuery) { [weak self] result in
            guard let self else { return continuation.resume() }
            Task {
              await self.onSubsequentFetch(
                cachePolicy: cachePolicy,
                result: result,
                publisher: publisher,
                query: nextPageQuery
              )
            }
          }
          nextPageWatchers.append(watcher)
          publisher.sink(receiveCompletion: { [weak self] _ in
            guard let self else { return continuation.resume() }
            Task {
              await self.continuationResumption()
              await self.onTaskCancellation()
            }
          }, receiveValue: { })
          .store(in: &subscribers)
          watcher.refetch(cachePolicy: cachePolicy)
        }
      }
      activeTask = task
      await task.value
    }

    public func subscribe(onUpdate: @MainActor @escaping (Result<Output, Error>) -> Void) -> AnyCancellable {
      $currentValue.compactMap({ $0 }).sink { [weak self] result in
        guard let self else { return }
        Task {
          let isLoadingAll = await self.isLoadingAll
          guard !isLoadingAll else { return }
          await onUpdate(result)
        }
      }
    }

    /// Reloads all data, starting at the first query, resetting pagination state.
    /// - Parameter cachePolicy: Preferred cache policy for first-page fetches. Defaults to `returnCacheDataAndFetch`
    public func refetch(cachePolicy: CachePolicy = .fetchIgnoringCacheData) async {
      assert(firstPageWatcher != nil, "To create consistent product behaviors, calling `fetch` before calling `refetch` will use cached data while still refreshing.")
      cancel()
      await fetch(cachePolicy: cachePolicy)
    }

    public func fetch() async {
      cancel()
      await fetch(cachePolicy: .returnCacheDataAndFetch)
    }

    /// Cancel any in progress fetching operations and unsubscribe from the store.
    public func cancel() {
      nextPageWatchers.forEach { $0.cancel() }
      nextPageWatchers = []
      firstPageWatcher?.cancel()
      firstPageWatcher = nil
      continuationResumption()
      initialContinuationResumption()
      previousPageVarMap = [:]
      nextPageVarMap = [:]
      initialPageResult = nil
      activeTask?.cancel()
      activeTask = nil
      initialFetchTask?.cancel()
      initialFetchTask = nil
      subscribers.forEach { $0.cancel() }
      subscribers.removeAll()
    }

    /// Whether or not we can load more information based on the current page.
    public var canLoadNext: Bool {
      currentPageInfo?.canLoadMore ?? false
    }

    public var canLoadPrevious: Bool {
      previousPageInfo?.canLoadPrevious ?? false
    }

    // MARK: - Private

    private func fetch(cachePolicy: CachePolicy = .returnCacheDataAndFetch) async {
      guard initialFetchTask == nil, activeContinuation == nil else {
        await initialFetchTask?.value
        return
      }
      let task = Task {
        let publisher = CurrentValueSubject<Void, Never>(())
        await withCheckedContinuation { continuation in
          initialContinuation = continuation
          if firstPageWatcher == nil {
            firstPageWatcher = GraphQLQueryWatcher(
              client: client,
              query: initialQuery,
              resultHandler: { [weak self] result in
                guard let self else { return continuation.resume() }
                Task {
                  await self.onInitialFetch(cachePolicy: cachePolicy, result: result, publisher: publisher)
                }
              }
            )
          }
          publisher.sink(receiveCompletion: { [weak self] _ in
            guard let self else { return continuation.resume() }
            Task {
              await self.initialContinuationResumption()
              await self.onTaskCancellation()
            }
          }, receiveValue: { })
          .store(in: &subscribers)
          firstPageWatcher?.refetch(cachePolicy: cachePolicy)
        }
      }
      initialFetchTask = task
      await task.value
    }

    private func onInitialFetch(
      cachePolicy: CachePolicy,
      result: Result<GraphQLResult<InitialQuery.Data>, Error>,
      publisher: CurrentValueSubject<Void, Never>
    ) {
      switch result {
      case .success(let data):
        initialPageResult = data.data
        guard let firstPageData = data.data else {
          publisher.send(completion: .finished)
          return
        }
        let shouldUpdate: Bool
        if cachePolicy == .returnCacheDataAndFetch && data.source == .cache {
          shouldUpdate = false
        } else {
          shouldUpdate = true
        }
        if let latest {
          let (previousPages, _, nextPage) = latest
          currentValue = .success(
            Output(
              previousPages: previousPages,
              initialPage: firstPageData,
              nextPages: nextPage,
              updateSource: data.source == .cache ? .cache : .fetch
            )
          )
        }
        if shouldUpdate {
          publisher.send(completion: .finished)
        }
      case .failure(let error):
        currentValue = .failure(error)
        publisher.send(completion: .finished)
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
        nextPageVarMap[variables] = nextPageData

        if let latest {
          let (previousPages, firstPage, nextPage) = latest
          let value: Result<Output, Error> = .success(
            Output(
              previousPages: previousPages,
              initialPage: firstPage,
              nextPages: nextPage,
              updateSource: data.source == .cache ? .cache : .fetch
            )
          )
          if isLoadingAll {
            queuedValue = value
          } else {
            currentValue = value
          }
        }
        if shouldUpdate {
          publisher.send(completion: .finished)
        }
      case .failure(let error):
        currentValue = .failure(error)
        publisher.send(completion: .finished)
      }
    }

    private func onPreviousFetch(
      cachePolicy: CachePolicy,
      result: Result<GraphQLResult<PaginatedQuery.Data>, Error>,
      publisher: CurrentValueSubject<Void, Never>,
      query: PaginatedQuery
    ) {
      switch result {
      case .success(let data):
        guard let previousPageData = data.data else {
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
        previousPageVarMap[variables] = previousPageData

        if let latest {
          let (previousPages, firstPage, nextPage) = latest
          let value: Result<Output, Error> = .success(
            Output(
              previousPages: previousPages,
              initialPage: firstPage,
              nextPages: nextPage,
              updateSource: data.source == .cache ? .cache : .fetch
            )
          )
          if isLoadingAll {
            queuedValue = value
          } else {
            currentValue = value
          }
        }
        if shouldUpdate {
          publisher.send(completion: .finished)
        }
      case .failure(let error):
        currentValue = .failure(error)
        publisher.send(completion: .finished)
      }
    }

    private func onTaskCancellation() async {
      activeTask?.cancel()
      activeTask = nil
      initialFetchTask?.cancel()
      initialFetchTask = nil
      subscribers.forEach { $0.cancel() }
      subscribers = []
    }

    private func pageTransformation() -> PaginationInfo? {
      guard let last = nextPageVarMap.values.last else {
        return initialPageResult.flatMap { extractPageInfo(.initial($0)) }
      }
      return extractPageInfo(.paginated(last))
    }

    private func previousPageTransformation() -> PaginationInfo? {
      guard let first = previousPageVarMap.values.last else {
        return initialPageResult.flatMap { extractPageInfo(.initial($0)) }
      }
      return extractPageInfo(.paginated(first))
    }

    private func continuationResumption() {
      activeContinuation?.resume(with: .success(()))
      activeContinuation = nil
    }

    private func initialContinuationResumption() {
      initialContinuation?.resume(with: .success(()))
      initialContinuation = nil
    }
  }
}
