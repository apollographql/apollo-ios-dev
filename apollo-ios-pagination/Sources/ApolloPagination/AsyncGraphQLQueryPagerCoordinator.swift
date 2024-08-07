import Apollo
import ApolloAPI
import Combine
import Foundation
import OrderedCollections

public protocol AsyncPagerType {
  associatedtype InitialQuery: GraphQLQuery
  associatedtype PaginatedQuery: GraphQLQuery
  var canLoadNext: Bool { get async }
  var canLoadPrevious: Bool { get async }
  func reset() async
  func loadPrevious(cachePolicy: CachePolicy) async throws
  func loadNext(cachePolicy: CachePolicy) async throws
  func loadAll(fetchFromInitialPage: Bool) async throws
  func refetch(cachePolicy: CachePolicy) async
  func fetch() async
}

actor AsyncGraphQLQueryPagerCoordinator<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>: AsyncPagerType {
  private let client: any ApolloClientProtocol
  private var firstPageWatcher: GraphQLQueryWatcher<InitialQuery>?
  private var nextPageWatchers: [GraphQLQueryWatcher<PaginatedQuery>] = []
  let initialQuery: InitialQuery
  var isLoadingAll: Bool = false
  var isFetching: Bool = false
  let nextPageResolver: (any PaginationInfo) -> PaginatedQuery?
  let previousPageResolver: (any PaginationInfo) -> PaginatedQuery?
  let extractPageInfo: (PageExtractionData<InitialQuery, PaginatedQuery, PaginationOutput<InitialQuery, PaginatedQuery>?>) -> any PaginationInfo
  var nextPageInfo: (any PaginationInfo)? { nextPageTransformation() }
  var previousPageInfo: (any PaginationInfo)? { previousPageTransformation() }

  var canLoadPages: (next: Bool, previous: Bool) {
    (canLoadNext, canLoadPrevious)
  }

  var publishers: (
    previousPageVarMap: Published<OrderedDictionary<Set<JSONValue>, GraphQLResult<PaginatedQuery.Data>>>.Publisher,
    initialPageResult: Published<GraphQLResult<InitialQuery.Data>?>.Publisher,
    nextPageVarMap: Published<OrderedDictionary<Set<JSONValue>, GraphQLResult<PaginatedQuery.Data>>>.Publisher
  ) {
    return ($previousPageVarMap, $initialPageResult, $nextPageVarMap)
  }

  typealias ResultType = Result<PaginationOutput<InitialQuery, PaginatedQuery>, any Error>

  @Published var currentValue: ResultType?
  private var queuedValue: ResultType?

  @Published var initialPageResult: GraphQLResult<InitialQuery.Data>?
  var latest: (previous: [GraphQLResult<PaginatedQuery.Data>], initial: GraphQLResult<InitialQuery.Data>, next: [GraphQLResult<PaginatedQuery.Data>])? {
    guard let initialPageResult else { return nil }
    return (
      Array(previousPageVarMap.values).reversed(),
      initialPageResult,
      Array(nextPageVarMap.values)
    )
  }

  /// Maps each query variable set to latest results from internal watchers.
  @Published var nextPageVarMap: OrderedDictionary<Set<JSONValue>, GraphQLResult<PaginatedQuery.Data>> = [:]
  @Published var previousPageVarMap: OrderedDictionary<Set<JSONValue>, GraphQLResult<PaginatedQuery.Data>> = [:]
  private var tasks: Set<Task<Void, any Error>> = []
  private var taskGroup: ThrowingTaskGroup<Void, any Error>?
  private var watcherCallbackQueue: DispatchQueue

  /// Designated Initializer
  /// - Parameters:
  ///   - client: Apollo Client
  ///   - initialQuery: The initial query that is being watched
  ///   - extractPageInfo: The `PageInfo` derived from `PageExtractionData`
  ///   - nextPageResolver: The resolver that can derive the query for loading more. This can be a different query than the `initialQuery`.
  ///   - onError: The callback when there is an error.
  init<P: PaginationInfo>(
    client: any ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractPageInfo: @escaping (PageExtractionData<InitialQuery, PaginatedQuery, PaginationOutput<InitialQuery, PaginatedQuery>?>) -> P,
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?
  ) {
    self.client = client
    self.initialQuery = initialQuery
    self.extractPageInfo = extractPageInfo
    self.watcherCallbackQueue = watcherDispatchQueue
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
    taskGroup?.cancelAll()
    tasks.forEach { $0.cancel() }
    tasks.removeAll()
  }

  // MARK: - Public API

  func loadAll(fetchFromInitialPage: Bool = true) async throws {
    return try await withThrowingTaskGroup(of: Void.self) { group in
      taskGroup = group
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

      // We begin by setting the initial state. The group needs some job to perform or it will perform nothing.
      if fetchFromInitialPage {
        // If we are fetching from an initial page, then we will want to reset state and then add a task for the initial load.
        reset()
        isLoadingAll = true
        group.addTask { [weak self] in
          await self?.fetch(cachePolicy: .fetchIgnoringCacheData)
        }
      } else if initialPageResult == nil {
        // Otherwise, we have to make sure that we have an `initialPageResult`
        throw PaginationError.missingInitialPage
      } else {
        isLoadingAll = true
        appendJobs()
      }

      // We only have one job in the group per execution.
      // Calling `next()` will either throw or give the next result (irrespective of order added into the queue).
      // Upon cancellation, the error is propogated to the task group and all remaining child tasks in the group are cancelled.
      while try await group.next() != nil && isLoadingAll {
        appendJobs()
      }

      // Setup return state
      isLoadingAll = false
      if let queuedValue {
        currentValue = queuedValue
      }
      queuedValue = nil
      taskGroup = nil
    }
  }

  func loadPrevious(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData
  ) async throws {
    try await paginationFetch(direction: .previous, cachePolicy: cachePolicy)
  }

  /// Loads the next page, using the currently saved pagination information to do so.
  /// Thread-safe, and supports multiple subscribers calling from multiple threads.
  /// **NOTE**: Requires having already called `fetch` or `refetch` prior to this call.
  /// - Parameters:
  ///   - cachePolicy: Preferred cache policy for fetching subsequent pages. Defaults to `fetchIgnoringCacheData`.
  func loadNext(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData
  ) async throws {
    try await paginationFetch(direction: .next, cachePolicy: cachePolicy)
  }

  func subscribe(
    onUpdate: @escaping (Result<PaginationOutput<InitialQuery, PaginatedQuery>, any Error>) -> Void
  ) -> AnyCancellable {
    $currentValue.compactMap({ $0 })
      .flatMap { [weak self] result in
        Future<Result<PaginationOutput<InitialQuery, PaginatedQuery>, any Error>?, Never> { [weak self] promise in
          Task { [weak self] in
            guard let self else { return }
            let isLoadingAll = await self.isLoadingAll
            guard !isLoadingAll else { return promise(.success(nil)) }
            promise(.success(result))
          }
        }
      }
      .sink { (result: Result<PaginationOutput<InitialQuery, PaginatedQuery>, any Error>?)  in
        result.flatMap(onUpdate)
      }
  }

  /// Reloads all data, starting at the first query, resetting pagination state.
  /// - Parameter cachePolicy: Preferred cache policy for first-page fetches. Defaults to `returnCacheDataAndFetch`
  func refetch(cachePolicy: CachePolicy = .fetchIgnoringCacheData) async {
    assert(firstPageWatcher != nil, "To create consistent product behaviors, calling `fetch` before calling `refetch` will use cached data while still refreshing.")
    reset()
    await fetch(cachePolicy: cachePolicy)
  }

  func fetch() async {
    reset()
    await fetch(cachePolicy: .returnCacheDataAndFetch)
  }

  /// Cancels any in-flight fetching operations and unsubscribes from the store.
  func reset() {
    nextPageWatchers.forEach { $0.cancel() }
    nextPageWatchers = []
    firstPageWatcher?.cancel()
    firstPageWatcher = nil
    previousPageVarMap = [:]
    nextPageVarMap = [:]
    initialPageResult = nil

    // Ensure any active networking operations are halted.
    taskGroup?.cancelAll()
    tasks.forEach { $0.cancel() }
    tasks.removeAll()
    isFetching = false
    isLoadingAll = false
  }

  /// Whether or not we can load more information based on the current page.
  var canLoadNext: Bool {
    nextPageInfo?.canLoadNext ?? false
  }

  var canLoadPrevious: Bool {
    previousPageInfo?.canLoadPrevious ?? false
  }

  // MARK: - Private

  private func fetch(cachePolicy: CachePolicy = .returnCacheDataAndFetch) async {
    await execute { [weak self] publisher in
      guard let self else { return }
      if await self.firstPageWatcher == nil {
        let watcher = GraphQLQueryWatcher(client: client, query: initialQuery, callbackQueue: await watcherCallbackQueue) { [weak self] result in
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
      let watcher = GraphQLQueryWatcher(client: self.client, query: pageQuery, callbackQueue: await watcherCallbackQueue) { [weak self] result in
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
    result: Result<GraphQLResult<DataType>, any Error>,
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
      let shouldUpdate: Bool
      if cachePolicy == .returnCacheDataAndFetch && data.source == .cache {
        shouldUpdate = false
      } else {
        shouldUpdate = true
      }

      var value: Result<PaginationOutput<InitialQuery, PaginatedQuery>, any Error>?
      var output: PaginationOutput<InitialQuery, PaginatedQuery>?
      var didFail = false
      switch fetchType {
      case .initial:
        initialPageResult = data as? GraphQLResult<InitialQuery.Data>
        initialPageResult = data as? GraphQLResult<InitialQuery.Data>
        output = initialPageResult.flatMap { result in
          .init(
            previousPages: latest?.previous ?? [],
            initialPage: latest?.initial,
            nextPages: latest?.next ?? [],
            lastUpdatedPage: .initial(result)
          )
        }
        if initialPageResult?.data == nil {
          didFail = true
        }
      case .paginated(let direction, let query):
        let variables = Set(query.__variables?.underlyingJson ?? [])
        let underlyingData = data.data as? PaginatedQuery.Data
        switch direction {
        case .next:
          nextPageVarMap[variables] = data as? GraphQLResult<PaginatedQuery.Data>
        case .previous:
          previousPageVarMap[variables] = data as? GraphQLResult<PaginatedQuery.Data>
        }

        if let latest, let paginatedResult = data as? GraphQLResult<PaginatedQuery.Data> {
          output = .init(
            previousPages: latest.previous,
            initialPage: latest.initial,
            nextPages: latest.next,
            lastUpdatedPage: .paginated(paginatedResult)
          )
        }
        if underlyingData == nil {
          didFail = true
        }
      }

      value = output.flatMap { paginationOutput in
        Result.success(paginationOutput)
      }

      if let value {
        if isLoadingAll {
          queuedValue = value
        } else {
          currentValue = value
        }
      }
      if didFail, isLoadingAll {
        isLoadingAll = false
        publisher.send(completion: .finished)
      } else if shouldUpdate {
        publisher.send(completion: .finished)
      }
    }
  }

  private func nextPageTransformation() -> (any PaginationInfo)? {
    let currentValue = try? currentValue?.get()
    guard let last = nextPageVarMap.values.last?.data else {
      return initialPageResult?.data.flatMap { extractPageInfo(.initial($0, currentValue)) }
    }
    return extractPageInfo(.paginated(last, currentValue))
  }

  private func previousPageTransformation() -> (any PaginationInfo)? {
    let currentValue = try? currentValue?.get()
    guard let first = previousPageVarMap.values.last?.data else {
      return initialPageResult?.data.flatMap { extractPageInfo(.initial($0, currentValue)) }
    }
    return extractPageInfo(.paginated(first, currentValue))
  }

  private func execute(operation: @escaping (CurrentValueSubject<Void, Never>) async throws -> Void) async {
    let tasksCopy = tasks
    await withCheckedContinuation { continuation in
      let task = Task {
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
          Task {
            await fetchContainer.cancel()
          }
        }
      }
      tasks.insert(task)
    }
    let remainder = tasks.subtracting(tasksCopy)
    remainder.forEach { task in
      tasks.remove(task)
    }
  }

  private func appendPaginationWatcher(watcher: GraphQLQueryWatcher<PaginatedQuery>) {
    nextPageWatchers.append(watcher)
  }

  private func setFirstPageWatcher(watcher: GraphQLQueryWatcher<InitialQuery>) {
    firstPageWatcher = watcher
  }
}

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
private extension AsyncGraphQLQueryPagerCoordinator {
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

internal extension GraphQLResult {
  var updateSource: UpdateSource {
    source == .cache ? .cache : .server
  }
}
