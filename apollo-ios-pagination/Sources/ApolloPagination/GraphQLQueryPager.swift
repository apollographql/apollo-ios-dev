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
    completion: (@MainActor (Error?) throws -> Void)?
  )
  func loadNext(
    cachePolicy: CachePolicy,
    completion: (@MainActor (Error?) throws -> Void)?
  )
  func loadAll(
    fetchFromInitialPage: Bool,
    completion: (@MainActor (Error?) throws -> Void)?
  )
  func refetch(cachePolicy: CachePolicy)
  func fetch()
}

/// Handles pagination in the queue by managing multiple query watchers.
public class GraphQLQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>: PagerType {

  private actor Subscriptions {
    var subscriptions: Set<AnyCancellable> = []

    func store(subscription: AnyCancellable) {
      subscriptions.insert(subscription)
    }
  }

  private actor CompletionManager {
    var completion: (@MainActor (Error?) throws -> Void)?

    func set(completion: (@MainActor (Error?) throws -> Void)?) async {
      self.completion = completion
    }

    func execute(error: Error?) async {
      try? await completion?(error)
      completion = nil
    }
  }

  private let pager: Actor
  private var subscriptions = Subscriptions()
  private var completions: [CompletionManager] = []

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
      let publishSubscriber = previousPageVarMapPublisher.combineLatest(
        initialPublisher,
        nextPageVarMapPublisher
      ).sink { [weak self] _ in
        guard !Task.isCancelled else { return }
        Task { [weak self] in
          guard let self else { return }
          let (canLoadNext, canLoadPrevious) = await self.pager.canLoadPages
          self.canLoadNext = canLoadNext
          self.canLoadPrevious = canLoadPrevious
        }
      }
      await subscriptions.store(subscription: publishSubscriber)
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
      let subscription = await self.pager.subscribe(onUpdate: onUpdate)
      await subscriptions.store(subscription: subscription)
    }
  }

  /// Whether or not we can load the next page. Initializes with a `false` value that is updated after the initial fetch.
  public var canLoadNext: Bool = false
  /// Whether or not we can load the previous page. Initializes with a `false` value that is updated after the initial fetch.
  public var canLoadPrevious: Bool = false

  /// Reset all pagination state and cancel all in-flight requests.
  public func cancel() {
    Task { [weak self] in
      guard let self else { return }
      for completion in self.completions {
        await completion.execute(error: PaginationError.cancellation)
      }
      self.completions = []
      await self.pager.cancel()
    }
  }

  /// Loads the previous page, if we can.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `fetchIgnoringCacheData`.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadPrevious(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: (@MainActor (Error?) throws -> Void)? = nil
  ) {
    execute { [weak self] in
      try await self?.pager.loadPrevious(cachePolicy: cachePolicy)
    } completion: { error in
      try completion?(error)
    }
  }

  /// Loads the next page, if we can.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `fetchIgnoringCacheData`.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadNext(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: (@MainActor (Error?) throws -> Void)? = nil
  ) {
    execute { [weak self] in
      try await self?.pager.loadNext(cachePolicy: cachePolicy)
    } completion: { error in
      try completion?(error)
    }
  }

  /// Loads all pages.
  /// - Parameters:
  ///   - fetchFromInitialPage: Pass true to begin loading from the initial page; otherwise pass false.  Defaults to `true`.  **NOTE**: Loading all pages with this value set to `false` requires that the initial page has already been loaded previously.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadAll(fetchFromInitialPage: Bool = true, completion: (@MainActor (Error?) throws -> Void)? = nil) {
    execute { [weak self] in
      try await self?.pager.loadAll(fetchFromInitialPage: fetchFromInitialPage)
    } completion: { error in
      try completion?(error)
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

  private func execute(operation: @escaping () async throws -> Void, completion: (@MainActor (Error?) throws -> Void)?) {
    Task<_, Never> { [weak self] in
      guard let self else { return }
      let completionManager = CompletionManager()
      await completionManager.set(completion: completion)
      self.completions.append(completionManager)
      do {
        try await operation()
        await completionManager.execute(error: nil)
      } catch {
        await completionManager.execute(error: error)
      }
    }
  }
}
