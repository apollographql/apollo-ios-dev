import Apollo
import ApolloAPI
import Combine
import Foundation

/// Type-erases a query pager, transforming data from a generic type to a specific type, often a view model or array of view models.
public class GraphQLQueryPager<Model>: Publisher {
  public typealias Failure = Never
  public typealias Output = Result<Model, any Error>
  let _subject: CurrentValueSubject<Output?, Never> = .init(nil)
  var publisher: AnyPublisher<Output, Never> { _subject.compactMap { $0 }.eraseToAnyPublisher() }
  public var cancellables: Set<AnyCancellable> = []
  public let pager: any PagerType

  public var canLoadNext: Bool { pager.canLoadNext }
  public var canLoadPrevious: Bool { pager.canLoadPrevious }

  init<Pager: GraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager,
    transform: @escaping (PaginationOutput<InitialQuery, PaginatedQuery>) throws -> Model
  ) {
    self.pager = pager
    pager.subscribe { [weak self] result in
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
  }

  init<Pager: GraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager
  ) where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    self.pager = pager
    pager.subscribe { [weak self] result in
      guard let self else { return }
      _subject.send(result)
    }
  }

  public convenience init<
    P: PaginationInfo,
    InitialQuery: GraphQLQuery,
    PaginatedQuery: GraphQLQuery
  >(
    client: any ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    initialQuery: InitialQuery,
    extractPageInfo: @escaping (PageExtractionData<InitialQuery, PaginatedQuery, Model?>) -> P,
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?
  ) where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    let pager = GraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
      extractPageInfo: extractPageInfo,
      pageResolver: pageResolver
    )
    self.init(pager: pager)
  }

  @available(*, deprecated, message: "Will be removed in a future version of ApolloPagination. Use `Combine`'s `.map` function to map outputs to your preferred type.")
  public convenience init<
    P: PaginationInfo,
    InitialQuery: GraphQLQuery,
    PaginatedQuery: GraphQLQuery
  >(
    client: any ApolloClientProtocol,
    watcherDispatchQueue: DispatchQueue = .main,
    initialQuery: InitialQuery,
    extractPageInfo: @escaping (PageExtractionData<InitialQuery, PaginatedQuery, Model?>) -> P,
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?,
    transform: @escaping (PaginationOutput<InitialQuery, PaginatedQuery>) throws -> Model
  ) where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    let pager = GraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
      extractPageInfo: extractPageInfo,
      pageResolver: pageResolver
    )
    self.init(pager: pager, transform: transform)
  }

  deinit {
    pager.reset()
  }

  /// Subscribe to the results of the pager, with the management of the subscriber being stored internally to the `AnyGraphQLQueryPager`.
  /// - Parameter completion: The closure to trigger when new values come in. Guaranteed to run on the main thread.
  @available(*, deprecated, message: "Will be removed in a future version of ApolloPagination. Use the `Combine` publishers instead. If you need to dispatch to the main thread, make sure to use a `.receive(on: RunLoop.main)` as part of your `Combine` operation.")
  public func subscribe(completion: @escaping @MainActor (Output) -> Void) {
    publisher.sink { result in
      Task { await completion(result) }
    }.store(in: &cancellables)
  }

  /// Load the next page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `returnCacheDataAndFetch`.
  ///   - callbackQueue: The `DispatchQueue` that the `completion` fires on. Defaults to `main`.
  ///   - completion: A completion block that will always trigger after the execution of this operation. Passes an optional error, of type `PaginationError`, if there was an internal error related to pagination. Does not surface network errors. Defaults to `nil`.
  public func loadNext(
    cachePolicy: CachePolicy = .returnCacheDataAndFetch,
    callbackQueue: DispatchQueue = .main,
    completion: ((PaginationError?) -> Void)? = nil
  ) {
    pager.loadNext(cachePolicy: cachePolicy, callbackQueue: callbackQueue, completion: completion)
  }

  /// Load the previous page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `returnCacheDataAndFetch`.
  ///   - callbackQueue: The `DispatchQueue` that the `completion` fires on. Defaults to `main`.
  ///   - completion: A completion block that will always trigger after the execution of this operation. Passes an optional error, of type `PaginationError`, if there was an internal error related to pagination. Does not surface network errors. Defaults to `nil`.
  public func loadPrevious(
    cachePolicy: CachePolicy = .returnCacheDataAndFetch,
    callbackQueue: DispatchQueue = .main,
    completion: ((PaginationError?) -> Void)? = nil
  ) {
    pager.loadPrevious(cachePolicy: cachePolicy, callbackQueue: callbackQueue, completion: completion)
  }

  /// Loads all pages.
  /// - Parameters:
  ///   - fetchFromInitialPage: Pass true to begin loading from the initial page; otherwise pass false.  Defaults to `true`.  **NOTE**: Loading all pages with this value set to `false` requires that the initial page has already been loaded previously.
  ///   - callbackQueue: The `DispatchQueue` that the `completion` fires on. Defaults to `main`.
  ///   - completion: A completion block that will always trigger after the execution of this operation. Passes an optional error, of type `PaginationError`, if there was an internal error related to pagination. Does not surface network errors. Defaults to `nil`.
  public func loadAll(
    fetchFromInitialPage: Bool = true,
    callbackQueue: DispatchQueue = .main,
    completion: ((PaginationError?) -> Void)? = nil
  ) {
    pager.loadAll(fetchFromInitialPage: fetchFromInitialPage, callbackQueue: callbackQueue, completion: completion)
  }

  /// Discards pagination state and fetches the first page from scratch.
  /// - Parameters:
  ///   - cachePolicy: The apollo cache policy to trigger the first fetch with. Defaults to `fetchIgnoringCacheData`.
  ///   - callbackQueue: The `DispatchQueue` that the `completion` fires on. Defaults to `main`.
  ///   - completion: A completion block that will always trigger after the execution of this  operation.
  public func refetch(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    callbackQueue: DispatchQueue = .main,
    completion: (() -> Void)? = nil
  ) {
    pager.refetch(cachePolicy: cachePolicy, callbackQueue: callbackQueue, completion: completion)
  }

  /// Fetches the first page.
  /// - Parameters:
  ///   - callbackQueue: The `DispatchQueue` that the `completion` fires on. Defaults to `main`.
  ///   - completion: A completion block that will always trigger after the execution of this  operation.
  public func fetch(
    callbackQueue: DispatchQueue = .main,
    completion: (() -> Void)? = nil
  ) {
    pager.fetch(callbackQueue: callbackQueue, completion: completion)
  }

  /// Resets pagination state and cancels in-flight updates from the pager.
  public func reset() {
    pager.reset()
  }

  public func receive<S>(
    subscriber: S
  ) where S: Subscriber, Never == S.Failure, Result<Model, any Error> == S.Input {
    publisher.subscribe(subscriber)
  }
}
