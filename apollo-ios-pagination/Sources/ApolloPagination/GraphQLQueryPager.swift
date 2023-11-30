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
  func loadNext(
    cachePolicy: CachePolicy,
    completion: (@MainActor (Error?) -> Void)?
  )
  func loadAll(fetchFromInitialPage: Bool, completion: (@MainActor (Error?) -> Void)?)
  func refetch(cachePolicy: CachePolicy)
  func fetch()
}

/// Handles pagination in the queue by managing multiple query watchers.
public class GraphQLQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>: PagerType {

  /// A struct which contains the outputs of pagination
  public struct Output: Hashable {

    /// An array of previous  pages, in pagination order
    /// Earlier pages come first in the array.
    public let previousPages: OrderedSet<PaginatedQuery.Data>

    /// The initial page that we fetched.
    public let initialPage: InitialQuery.Data

    /// An array of pages after the initial page.
    public let nextPages: OrderedSet<PaginatedQuery.Data>

    /// The source of the most recent `Output`: either from the cache or server.
    public let updateSource: UpdateSource

    public init(
      previousPages: OrderedSet<PaginatedQuery.Data>,
      initialPage: InitialQuery.Data,
      nextPages: OrderedSet<PaginatedQuery.Data>,
      updateSource: UpdateSource
    ) {
      self.previousPages = previousPages
      self.initialPage = initialPage
      self.nextPages = nextPages
      self.updateSource = updateSource
    }
  }

  private let pager: Actor
  private var publishSubscriber: AnyCancellable?
  private var subscriptions: [AnyCancellable] = []
  private var canLoadNextSubject: CurrentValueSubject<Bool, Never> = .init(false)
  private var canLoadPreviousSubject: CurrentValueSubject<Bool, Never> = .init(false)

  /// The result of either the initial query or the paginated query, for the purpose of extracting a `PageInfo` from it.
  public enum PageExtractionData {
    case initial(InitialQuery.Data)
    case paginated(PaginatedQuery.Data)
  }

  /// An enumeration that can determine whether we are paginating forward or backwards.
  public enum PaginationDirection: Hashable {
    case next
    case previous
  }

  public init<P: PaginationInfo>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    extractPageInfo: @escaping (PageExtractionData) -> P,
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?
  ) {
    pager = .init(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: extractPageInfo,
      pageResolver: pageResolver
    )
    Task { [weak self] in
      guard let self else { return }
      let (previousPageVarMapPublisher, initialPublisher, nextPageVarMapPublisher) = await pager.publishers
      // It's important that we don't store this in the `subscriptions` variable: The thread sanitizer points out, correctly, that we're creating an access race.
      self.publishSubscriber = previousPageVarMapPublisher.combineLatest(initialPublisher, nextPageVarMapPublisher).sink { _ in
        guard !Task.isCancelled else { return }
        Task { [weak self] in
          guard let self else { return }
          let (canLoadNext, canLoadPrevious) = await self.pager.canLoadPages
          self.canLoadNextSubject.send(canLoadNext)
          self.canLoadPreviousSubject.send(canLoadPrevious)
        }
      }
    }
  }

  init(pager: Actor) {
    self.pager = pager
  }

  /// Allows the caller to subscribe to new pagination results.
  /// - Parameter onUpdate: A closure which provides the most recent pagination result. This closure is guaruanteed to be dispatched to the `MainActor`
  public func subscribe(onUpdate: @MainActor @escaping (Result<Output, Error>) -> Void) {
    Task { [weak self] in
      guard let self else { return }
      await self.pager.subscribe(onUpdate: onUpdate)
        .store(in: &self.subscriptions)
    }
  }

  public var canLoadNext: Bool { canLoadNextSubject.value }
  public var canLoadPrevious: Bool { canLoadPreviousSubject.value }

  /// Reset all pagination state and cancel all in-flight requests.
  public func cancel() {
    Task {
      await pager.cancel()
    }
  }

  /// Loads the previous page, if we can.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `fetchIgnoringCacheData`.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadPrevious(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: (@MainActor (Error?) -> Void)? = nil
  ) {
    Task<_, Never> {
      await withTaskCancellationHandler {
        do {
          try await pager.loadPrevious(cachePolicy: cachePolicy)
          await completion?(nil)
        } catch {
          await completion?(error)
        }
      } onCancel: {
        Task { await completion?(PaginationError.taskCancelled) }
      }
    }
  }

  /// Loads the next page, if we can.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `fetchIgnoringCacheData`.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadNext(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: (@MainActor (Error?) -> Void)? = nil
  ) {
    Task<_, Never> {
      await withTaskCancellationHandler {
        do {
          try await pager.loadNext(cachePolicy: cachePolicy)
          await completion?(nil)
        } catch {
          await completion?(error)
        }
      } onCancel: {
        Task { await completion?(PaginationError.taskCancelled) }
      }
    }
  }

  /// Loads all pages.
  /// - Parameters:
  ///   - fetchFromInitialPage: Pass true to begin loading from the initial page; otherwise pass false.  Defaults to `true`.  **NOTE**: Loading all pages with this value set to `false` requires that the initial page has already been loaded previously.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadAll(fetchFromInitialPage: Bool = true, completion: (@MainActor (Error?) -> Void)? = nil) {
    Task<_, Never> {
      await withTaskCancellationHandler {
        do {
          try await pager.loadAll(fetchFromInitialPage: fetchFromInitialPage)
          await completion?(nil)
        } catch {
          await completion?(error)
        }
      } onCancel: {
        Task { await completion?(PaginationError.taskCancelled) }
      }
    }
  }

  /// Discards pagination state and fetches the first page from scratch.
  /// - Parameter cachePolicy: The apollo cache policy to trigger the first fetch with. Defaults to `fetchIgnoringCacheData`.
  public func refetch(cachePolicy: CachePolicy = .fetchIgnoringCacheData) {
    Task {
      await pager.refetch(cachePolicy: cachePolicy)
    }
  }

  /// Fetches the first page.
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
    var nextPageInfo: PaginationInfo? { nextPageTransformation() }
    var previousPageInfo: PaginationInfo? { previousPageTransformation() }

    var canLoadPages: (next: Bool, previous: Bool) {
      (canLoadNext, canLoadPrevious)
    }

    var publishers: (
      previousPageVarMap: Published<OrderedDictionary<AnyHashable, PaginatedQuery.Data>>.Publisher,
      initialPageResult: Published<InitialQuery.Data?>.Publisher,
      nextPageVarMap: Published<OrderedDictionary<AnyHashable, PaginatedQuery.Data>>.Publisher
    ) {
      return ($previousPageVarMap, $initialPageResult, $nextPageVarMap)
    }

    @Published var currentValue: Result<Output, Error>?
    private var queuedValue: Result<Output, Error>?
    private var paginationSubscriber: AnyCancellable?
    private var initialFetchSubscriber: AnyCancellable?

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
      pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?
    ) {
      self.client = client
      self.initialQuery = initialQuery
      self.extractPageInfo = extractPageInfo
      self.nextPageResolver = { page in
        guard let page = page as? P else { return nil }
        return pageResolver?(page, .next)
      }
      self.previousPageResolver = { page in
        guard let page = page as? P else { return nil }
        return pageResolver?(page, .previous)
      }
    }

    deinit {
      nextPageWatchers.forEach { $0.cancel() }
      firstPageWatcher?.cancel()
      activeContinuation?.resume(with: .success(()))
      initialContinuation?.resume(with: .success(()))
    }

    // MARK: - Public API

    public func loadAll(fetchFromInitialPage: Bool = true) async throws {
      isLoadingAll = true
      if fetchFromInitialPage {
        cancel()
        // As we are loading all data from all pages before notifying the caller, we don't care about cached responses
        await fetch(cachePolicy: .fetchIgnoringCacheData)
      }

      while nextPageInfo?.canLoadNext ?? false {
        try await loadNext()
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
      try await paginationFetch(direction: .previous, cachePolicy: cachePolicy)
    }

    /// Loads the next page, using the currently saved pagination information to do so.
    /// Thread-safe, and supports multiple subscribers calling from multiple threads.
    /// **NOTE**: Requires having already called `fetch` or `refetch` prior to this call.
    /// - Parameters:
    ///   - cachePolicy: Preferred cache policy for fetching subsequent pages. Defaults to `fetchIgnoringCacheData`.
    public func loadNext(
      cachePolicy: CachePolicy = .fetchIgnoringCacheData
    ) async throws {
      try await paginationFetch(direction: .next, cachePolicy: cachePolicy)
    }

    public func subscribe(onUpdate: @MainActor @escaping (Result<Output, Error>) -> Void) -> AnyCancellable {
      $currentValue.compactMap({ $0 })
        .removeDuplicates(by: { previous, current in
          switch (previous, current) {
          case (.success(let lhs), .success(let rhs)):
            return lhs == rhs
          case (.failure(let lhs), .failure(let rhs)):
            if let lhs = lhs as? PaginationError, let rhs = rhs as? PaginationError {
              return lhs == rhs
            } else {
              return lhs.localizedDescription == rhs.localizedDescription
            }
          case (.failure, .success), (.success, .failure):
            return false
          }
        })
        .sink { [weak self] result in
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
      paginationSubscriber = nil
      initialFetchSubscriber = nil
    }

    /// Whether or not we can load more information based on the current page.
    public var canLoadNext: Bool {
      nextPageInfo?.canLoadNext ?? false
    }

    public var canLoadPrevious: Bool {
      previousPageInfo?.canLoadPrevious ?? false
    }

    // MARK: - Private

    private func fetch(cachePolicy: CachePolicy = .returnCacheDataAndFetch) async {
      guard initialFetchTask == nil, initialContinuation == nil else {
        await initialFetchTask?.value
        return
      }
      let task = Task {
        let publisher = CurrentValueSubject<Void, Never>(())
        await withTaskCancellationHandler {
          await withCheckedContinuation { continuation in
            initialContinuation = continuation
            if firstPageWatcher == nil {
              firstPageWatcher = GraphQLQueryWatcher(
                client: client,
                query: initialQuery,
                resultHandler: { [weak self] result in
                  guard let self else { return continuation.resume() }
                  Task {
                    await self.onInitialFetch(
                      cachePolicy: cachePolicy,
                      result: result,
                      publisher: publisher
                    )
                  }
                }
              )
            }
            initialFetchSubscriber = publisher.sink(receiveCompletion: { [weak self] _ in
              guard let self else { return continuation.resume() }
              Task {
                await self.initialContinuationResumption()
                await self.onInitialTaskCancellation()
              }
            }, receiveValue: { })
            firstPageWatcher?.refetch(cachePolicy: cachePolicy)
          }
        } onCancel: {
          Task { [weak self] in
            await self?.initialContinuationResumption()
            await self?.onInitialTaskCancellation()
          }
        }
      }
      initialFetchTask = task
      await task.value
    }

    private func paginationFetch(
      direction: PaginationDirection,
      cachePolicy: CachePolicy
    ) async throws {
      if initialContinuation != nil || initialFetchTask != nil {
        // If we are here, it means we are attempting to load the next (or previous) page on the basis of
        // cached data. That can lead to inconsistent pagination state. We will pause execution here until
        // the initial fetch completes.
        PaginationLogger.log(
          "We have entered a pagination fetch while an initial fetch task is still active",
          logLevel: .debug
        )
        await initialFetchTask?.value
      }
      let pageQuery: PaginatedQuery?
      switch direction {
      case .previous:
        guard let previousPageInfo else { throw PaginationError.missingInitialPage }
        guard previousPageInfo.canLoadPrevious else { throw PaginationError.pageHasNoMoreContent }
        pageQuery = previousPageResolver(previousPageInfo)
      case .next:
        guard let nextPageInfo else { throw PaginationError.missingInitialPage }
        guard nextPageInfo.canLoadNext else { throw PaginationError.pageHasNoMoreContent }
        pageQuery = nextPageResolver(nextPageInfo)
      }
      guard let pageQuery else { throw PaginationError.noQuery }
      guard activeTask == nil, activeContinuation == nil else {
        throw PaginationError.loadInProgress
      }

      let task = Task {
        let publisher = CurrentValueSubject<Void, Never>(())
        await withTaskCancellationHandler {
          await withCheckedContinuation { continuation in
            activeContinuation = continuation
            let watcher = GraphQLQueryWatcher(client: client, query: pageQuery) { [weak self] result in
              guard let self else { return continuation.resume() }
              Task {
                await self.onPaginationFetch(
                  direction: direction,
                  cachePolicy: cachePolicy,
                  result: result,
                  publisher: publisher,
                  query: pageQuery
                )
              }
            }
            nextPageWatchers.append(watcher)
            paginationSubscriber = publisher.sink(receiveCompletion: { [weak self] _ in
              guard let self else { return continuation.resume() }
              Task {
                await self.continuationResumption()
                await self.onTaskCancellation()
              }
            }, receiveValue: { })
            watcher.refetch(cachePolicy: cachePolicy)
          }
        } onCancel: {
          Task { [weak self] in
            await self?.continuationResumption()
            await self?.onTaskCancellation()
          }
        }
      }
      activeTask = task
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
          let (previousPages, _, nextPages) = latest
          let value: Result<Output, Error> = .success(
            Output(
              previousPages: .init(previousPages),
              initialPage: firstPageData,
              nextPages: .init(nextPages),
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
        if isLoadingAll {
          queuedValue = .failure(error)
        } else {
          currentValue = .failure(error)
        }
        publisher.send(completion: .finished)
      }
    }

    private func onPaginationFetch(
      direction: PaginationDirection,
      cachePolicy: CachePolicy,
      result: Result<GraphQLResult<PaginatedQuery.Data>, Error>,
      publisher: CurrentValueSubject<Void, Never>,
      query: PaginatedQuery
    ) {
      switch result {
      case .success(let data):
        guard let pageData = data.data else {
          publisher.send(completion: .finished)
          return
        }

        let shouldUpdate: Bool
        if cachePolicy == .returnCacheDataAndFetch && data.source == .cache {
          shouldUpdate = false
        } else {
          shouldUpdate = true
        }
        let variables = query.__variables?.underlyingJson ?? []
        switch direction {
        case .next:
          nextPageVarMap[variables] = pageData
        case .previous:
          previousPageVarMap[variables] = pageData
        }

        if let latest {
          let (previousPages, firstPage, nextPages) = latest
          let value: Result<Output, Error> = .success(
            Output(
              previousPages: .init(previousPages),
              initialPage: firstPage,
              nextPages: .init(nextPages),
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
        if isLoadingAll {
          queuedValue = .failure(error)
        } else {
          currentValue = .failure(error)
        }
        publisher.send(completion: .finished)
      }
    }

    private func onTaskCancellation() async {
      activeTask?.cancel()
      activeTask = nil
      paginationSubscriber = nil
      await onInitialTaskCancellation()
    }

    private func onInitialTaskCancellation() async {
      initialFetchTask?.cancel()
      initialFetchTask = nil
      initialFetchSubscriber = nil
    }

    private func nextPageTransformation() -> PaginationInfo? {
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

private extension GraphQLOperation.Variables {
  var underlyingJson: [JSONValue] {
    values.compactMap { $0._jsonEncodableValue?._jsonValue }
  }
}
