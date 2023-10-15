import Apollo
import ApolloAPI
import Combine
import Foundation

/// Handles pagination in the queue by managing multiple query watchers.
public class GraphQLQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery> {

  /// The result of either the initial query or the paginated query, for the purpose of extracting a `PageInfo` from it.
  public enum PageExtractionData {
    case initial(InitialQuery.Data)
    case paginated(PaginatedQuery.Data)
  }

  public typealias Output = (InitialQuery.Data, [PaginatedQuery.Data], UpdateSource)

  private let client: any ApolloClientProtocol
  private var firstPageWatcher: GraphQLQueryWatcher<InitialQuery>?
  private var nextPageWatchers: [GraphQLQueryWatcher<PaginatedQuery>] = []
  private let initialQuery: InitialQuery
  let nextPageResolver: (PaginationInfo) -> PaginatedQuery?
  let extractPageInfo: (PageExtractionData) -> PaginationInfo
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

  var _subject: CurrentValueSubject<Result<Output, Error>?, Never> = .init(nil)
  public var subject: AnyPublisher<Result<Output, Error>, Never> { _subject.compactMap({ $0 }).eraseToAnyPublisher() }
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
    extractPageInfo: @escaping (PageExtractionData) -> P,
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

  // MARK: - Public API

  /// Subscribe to new data from this watcher, using a callback
  /// - Parameter onUpdate: A callback function that supplies a `Result<Output, Error>`
  public func subscribe(
    onUpdate: @MainActor @escaping (Result<Output, Error>) -> Void
  ) {
    subject.sink { value in
      Task {
        await onUpdate(value)
      }
    }.store(in: &subscribers)
  }

  /// Loads the first page of results.
  /// This method is non-destructive: It will re-fetch the contents of the first page, without modifying any of the other pages, should there be any.
  /// - Parameter cachePolicy: Preferred cache policy for first-page fetches. Defaults to `returnCacheDataAndFetch`
  func fetch(cachePolicy: CachePolicy = .returnCacheDataAndFetch) {
    defer { firstPageWatcher?.refetch(cachePolicy: cachePolicy) }
    guard firstPageWatcher == nil else { return }
    self.firstPageWatcher = GraphQLQueryWatcher(
      client: client,
      query: initialQuery,
      resultHandler: { [weak self] result in
        guard let self else { return }
        switch result {
        case .success(let data):
          self.initialPageResult = data.data
          guard let firstPageData = data.data else { return }
          if let latest = self.latest {
            let (_, nextPage) = latest
            self._subject.send(.success((firstPageData, nextPage, data.source == .cache ? .cache : .fetch)))
          }
        case .failure(let error):
          self._subject.send(.failure(error))
        }
      }
    )
  }


  /// A convenience wrapper around the asynchronous `loadMore` function.
  public func loadMore(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: (() -> Void)? = nil
  ) throws {
    Task {
      try await loadMore(cachePolicy: cachePolicy, completion: completion)
    }
  }

  /// Loads the next page, using the currently saved pagination information to do so.
  /// Thread-safe, and supports multiple subscribers calling from multiple threads.
  /// **NOTE**: Requires having already called `fetch` or `refetch` prior to this call.
  /// - Parameters:
  ///   - cachePolicy: Preferred cache policy for fetching subsequent pages. Defaults to `fetchIgnoringCacheData`.
  public func loadMore(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: (() -> Void)? = nil
  ) async throws {
    guard let currentPageInfo else {
      assertionFailure("No page info detected -- are you calling `loadMore` prior to calling the initial fetch?")
      throw PaginationError.missingInitialPage
    }
    guard let nextPageQuery = nextPageResolver(currentPageInfo),
          currentPageInfo.canLoadMore
    else { throw PaginationError.pageHasNoMoreContent }
    guard activeTask == nil else {
      _ = await activeTask?.value
      return
    }

    let task = Task {
      let publisher = CurrentValueSubject<Void, Never>(())
      await withCheckedContinuation { continuation in
        let watcher = GraphQLQueryWatcher(client: client, query: nextPageQuery) { [weak self] result in
          guard let self else { return }
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
            let variables = initialQuery.__variables?.values.compactMap { $0._jsonEncodableValue?._jsonValue } ?? []
            if shouldUpdate {
              self.pageOrder.append(variables)
              publisher.send(completion: .finished)
            }
            self.varMap[variables] = nextPageData

            if let latest = self.latest {
              let (firstPage, nextPage) = latest
              self._subject.send(.success((firstPage, nextPage, data.source == .cache ? .cache : .fetch)))
            }
          case .failure(let error):
            self._subject.send(.failure(error))
            publisher.send(completion: .finished)
          }
        }
        nextPageWatchers.append(watcher)
        publisher.sink(receiveCompletion: { [weak self] _ in
          continuation.resume(with: .success(()))
          self?.activeTask?.cancel()
          self?.activeTask = nil
          completion?()
        }, receiveValue: { })
        .store(in: &subscribers)
        watcher.refetch(cachePolicy: cachePolicy)
      }
    }
    self.activeTask = task
    await task.value
  }

  /// Reloads all data, starting at the first query, resetting pagination state.
  /// - Parameter cachePolicy: Preferred cache policy for first-page fetches. Defaults to `returnCacheDataAndFetch`
  public func refetch(cachePolicy: CachePolicy = .returnCacheDataAndFetch) {
    cancel()
    fetch(cachePolicy: cachePolicy)
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
    _subject.send(nil)
    activeTask?.cancel()
    activeTask = nil
  }

  /// Whether or not we can load more information based on the current page.
  public func canLoadNext() -> Bool {
    currentPageInfo?.canLoadMore ?? false
  }

  deinit {
    firstPageWatcher?.cancel()
    nextPageWatchers.forEach { $0.cancel() }
    _subject.send(completion: .finished)
  }
}
