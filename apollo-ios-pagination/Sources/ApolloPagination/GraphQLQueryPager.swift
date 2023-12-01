import Apollo
import ApolloAPI
import Combine

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

  // The `Actor` performs all of the behaviors of the `GraphQLQueryPager`. The `Actor` is isolated to its own thread, and thus the
  // `GraphQLQueryPager` delegates all of its actions to the `Actor`. The `GraphQLQueryPager` is effectively a synchronous API-wrapper around
  // the otherwise asynchronous `Actor`.
  private let pager: Actor
  private var publishSubscriber: AnyCancellable?
  private var subscriptions: [AnyCancellable] = []

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
    // We have to be careful with `Task`s in this class, especially when we reference properties on `self`.
    // Reading properties on `self` is fine, but writing properties to `self` can be tricky.
    // Generally, in `Combine`, we want to call `store(in:)` to store the resulting `AnyCancellable` that represents
    // a subscriber. However, that API specifically takes an `inout` collection. That means that this can lead to
    // an access race if we are making calls to `store(in:)` on the same variable in multiple locations.
    // Generally speaking, that means that within the bounds of this class, which is a wrapper around the isolated
    // `Actor` class, that we must make sure that any property we are writing to is only being written to in one
    // place. We can do so either through use of mutexes, `@Atomic` properties (MAYBE), or by just using separate
    // `AnyCancellable` storage variables per Combine publisher.
    Task { [weak self] in
      guard let self else { return }
      let (previousPageVarMapPublisher, initialPublisher, nextPageVarMapPublisher) = await pager.publishers
      self.publishSubscriber = previousPageVarMapPublisher.combineLatest(initialPublisher, nextPageVarMapPublisher).sink { _ in
        guard !Task.isCancelled else { return }
        Task { [weak self] in
          guard let self else { return }
          let (canLoadNext, canLoadPrevious) = await self.pager.canLoadPages
          self.canLoadNext = canLoadNext
          self.canLoadPrevious = canLoadPrevious
        }
      }
    }
  }

  /// Convenience initializer, internal only.
  /// - Parameter pager: An `Actor`.
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

  /// Whether or not we can load the next page. Initializes with a `false` value that is updated after the initial fetch.
  public var canLoadNext: Bool = false
  /// Whether or not we can load the previous page. Initializes with a `false` value that is updated after the initial fetch.
  public var canLoadPrevious: Bool = false

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
      do {
        try await pager.loadPrevious(cachePolicy: cachePolicy)
        await completion?(nil)
      } catch {
        await completion?(error)
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
      do {
        try await pager.loadNext(cachePolicy: cachePolicy)
        await completion?(nil)
      } catch {
        await completion?(error)
      }
    }
  }

  /// Loads all pages.
  /// - Parameters:
  ///   - fetchFromInitialPage: Pass true to begin loading from the initial page; otherwise pass false.  Defaults to `true`.  **NOTE**: Loading all pages with this value set to `false` requires that the initial page has already been loaded previously.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadAll(fetchFromInitialPage: Bool = true, completion: (@MainActor (Error?) -> Void)? = nil) {
    Task<_, Never> {
      do {
        try await pager.loadAll(fetchFromInitialPage: fetchFromInitialPage)
        await completion?(nil)
      } catch {
        await completion?(error)
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
