import Apollo
import ApolloAPI
import Combine
import Foundation
import OrderedCollections

extension GraphQLQueryPager {
  actor Actor {
    private let client: any ApolloClientProtocol
    private var firstPageWatcher: GraphQLQueryWatcher<InitialQuery>?
    private var nextPageWatchers: [GraphQLQueryWatcher<PaginatedQuery>] = []
    private let initialQuery: InitialQuery
    private var isLoadingAll: Bool = false
    private var isFetching: Bool = false
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

    @Published var initialPageResult: InitialQuery.Data?
    var latest: (previous: [PaginatedQuery.Data], initial: InitialQuery.Data, next: [PaginatedQuery.Data])? {
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
    }

    // MARK: - Public API

    public func loadAll(fetchFromInitialPage: Bool = true) async throws {
      return try await withThrowingTaskGroup(of: Void.self) { group in
        func appendJobs() {
          if nextPageInfo?.canLoadNext ?? false {
            group.addTask { [weak self] in
              try await self?.loadNext()
            }
          } else if previousPageInfo?.canLoadPrevious ?? false {
            group.addTask { [weak self] in
              try await self?.loadPrevious()
            }
          }
        }
        isLoadingAll = true

        // We begin by setting the initial state. The group needs some job to perform or it will perform nothing.
        if fetchFromInitialPage {
          // If we are fetching from an initial page, then we will want to reset state and then add a task for the initial load.
          cancel()
          group.addTask { [weak self] in
            await self?.fetch(cachePolicy: .fetchIgnoringCacheData)
          }
        } else if initialPageResult == nil {
          // Otherwise, we have to make sure that we have an `initialPageResult`
          throw PaginationError.missingInitialPage
        } else {
          appendJobs()
        }

        // We only have one job in the group per execution.
        // Calling `next()` will either throw or give the next result (irrespective of order added into the queue).
        // Upon cancellation, the error is propogated to the task group and all remaining child tasks in the group are cancelled.
        while try await group.next() != nil {
          appendJobs()
        }

        // Setup return state
        isLoadingAll = false
        if let queuedValue {
          currentValue = queuedValue
        }
        queuedValue = nil
      }
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
        .sink { [weak self] result in
          Task { [weak self] in
            guard let self else { return }
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
      previousPageVarMap = [:]
      nextPageVarMap = [:]
      initialPageResult = nil
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
      await execute { [weak self] publisher in
        guard let self else { return }
        if await self.firstPageWatcher == nil {
          let watcher = GraphQLQueryWatcher(client: client, query: initialQuery) { [weak self] result in
            Task { [weak self] in
              await self?.onFetch(
                fetchType: .initial,
                cachePolicy: cachePolicy,
                result: result,
                publisher: publisher
              )
            }
          }
          await self.setFirstPageWatcher(watcher: watcher)
        }
        await self.firstPageWatcher?.refetch(cachePolicy: cachePolicy)
      }
    }

    private func paginationFetch(
      direction: PaginationDirection,
      cachePolicy: CachePolicy
    ) async throws {
      // Access to `isFetching` is mutually exclusive, so these checks and modifications will prevent
      // other attempts to call this function in rapid succession.
      if isFetching { throw PaginationError.loadInProgress }
      isFetching = true
      defer { isFetching = false }

      // Determine the query based on whether we are paginating forward or backwards
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

      await execute { [weak self] publisher in
        guard let self else { return }
        let watcher = GraphQLQueryWatcher(client: self.client, query: pageQuery) { [weak self] result in
          Task { [weak self] in
            await self?.onFetch(
              fetchType: .paginated(direction, pageQuery),
              cachePolicy: cachePolicy,
              result: result,
              publisher: publisher
            )
          }
        }
        await self.appendPaginationWatcher(watcher: watcher)
        watcher.refetch(cachePolicy: cachePolicy)
      }
    }

    private func onFetch<DataType: RootSelectionSet>(
      fetchType: FetchType,
      cachePolicy: CachePolicy,
      result: Result<GraphQLResult<DataType>, Error>,
      publisher: CurrentValueSubject<Void, Never>
    ) {
      switch result {
      case .failure(let error):
        if isLoadingAll {
          queuedValue = .failure(error)
        } else {
          currentValue = .failure(error)
        }
        publisher.send(completion: .finished)
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

        var value: Result<Output, Error>?
        var output: ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data])?
        switch fetchType {
        case .initial:
          guard let pageData = pageData as? InitialQuery.Data else { return }
          initialPageResult = pageData
          if let latest {
            output = (latest.previous, pageData, latest.next)
          }
        case .paginated(let direction, let query):
          guard let pageData = pageData as? PaginatedQuery.Data else { return }

          let variables = query.__variables?.underlyingJson ?? []
          switch direction {
          case .next:
            nextPageVarMap[variables] = pageData
          case .previous:
            previousPageVarMap[variables] = pageData
          }

          if let latest {
            output = latest
          }
        }

        value = output.flatMap { previousPages, initialPage, nextPages in
          Result.success(Output(
            previousPages: previousPages,
            initialPage: initialPage,
            nextPages: nextPages,
            updateSource: data.source == .cache ? .cache : .fetch
          ))
        }

        if let value {
          if isLoadingAll {
            queuedValue = value
          } else {
            currentValue = value
          }
        }
        if shouldUpdate {
          publisher.send(completion: .finished)
        }
      }
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

    private func execute(operation: @escaping (CurrentValueSubject<Void, Never>) async throws -> Void) async {
      await withCheckedContinuation { continuation in
        Task {
          let fetchContainer = FetchContainer()
          let publisher = CurrentValueSubject<Void, Never>(())
          let subscriber = publisher.sink(receiveCompletion: { _ in
            Task { await fetchContainer.cancel() }
          }, receiveValue: { })
          await fetchContainer.setValues(subscriber: subscriber, continuation: continuation)
          try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await operation(publisher)
          } onCancel: {
            Task { await fetchContainer.cancel() }
          }
        }
      }
    }

    private func appendPaginationWatcher(watcher: GraphQLQueryWatcher<PaginatedQuery>) {
      nextPageWatchers.append(watcher)
    }

    private func setFirstPageWatcher(watcher: GraphQLQueryWatcher<InitialQuery>) {
      firstPageWatcher = watcher
    }
  }
}

private extension GraphQLQueryPager {
  private actor FetchContainer {
    var subscriber: AnyCancellable? {
      willSet { subscriber?.cancel() }
    }
    var continuation: CheckedContinuation<Void, Never>? {
      willSet { continuation?.resume() }
    }

    init(
      subscriber: AnyCancellable? = nil,
      continuation: CheckedContinuation<Void, Never>? = nil
    ) {
      self.subscriber = subscriber
      self.continuation = continuation
    }

    deinit {
      continuation?.resume()
    }

    func cancel() {
      subscriber = nil
      continuation = nil
    }

    func setValues(
      subscriber: AnyCancellable?,
      continuation: CheckedContinuation<Void, Never>?
    ) {
      self.subscriber = subscriber
      self.continuation = continuation
    }
  }
}

private extension GraphQLQueryPager {
  enum FetchType {
    case initial
    case paginated(PaginationDirection, PaginatedQuery)
  }
}

private extension GraphQLOperation.Variables {
  var underlyingJson: [JSONValue] {
    values.compactMap { $0._jsonEncodableValue?._jsonValue }
  }
}
