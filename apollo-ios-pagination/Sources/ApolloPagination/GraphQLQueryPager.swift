import Apollo
import ApolloAPI
import Combine
import Dispatch
import Foundation

/// Type-erases a query pager, transforming data from a generic type to a specific type, often a view model or array of view models.
public class GraphQLQueryPager<Model>: Publisher {
  public typealias Failure = Never
  public typealias Output = Result<(Model, UpdateSource), Error>
  let _subject: CurrentValueSubject<Output?, Never> = .init(nil)
  var publisher: AnyPublisher<Output, Never> { _subject.compactMap { $0 }.eraseToAnyPublisher() }
  public var cancellables: Set<AnyCancellable> = []
  public let pager: any PagerType

  public var canLoadNext: Bool { pager.canLoadNext }
  public var canLoadPrevious: Bool { pager.canLoadPrevious }

  /// Type-erases a given pager, transforming data to a model as pagination receives new results.
  /// - Parameters:
  ///   - pager: Pager to type-erase.
  ///   - transform: Transformation from an initial page and array of paginated pages to a given view model.
  public init<Pager: GraphQLQueryPagerCoordinator<InitialQuery, NextQuery>, InitialQuery, NextQuery>(
    pager: Pager,
    transform: @escaping ([NextQuery.Data], InitialQuery.Data, [NextQuery.Data]) throws -> Model
  ) {
    self.pager = pager
    pager.subscribe { [weak self] result in
      guard let self else { return }
      let returnValue: Output

      switch result {
      case let .success(output):
        do {
          let transformedModels = try transform(output.previousPages, output.initialPage, output.nextPages)
          returnValue = .success((transformedModels, output.updateSource))
        } catch {
          returnValue = .failure(error)
        }
      case let .failure(error):
        returnValue = .failure(error)
      }

      _subject.send(returnValue)
    }
  }

  /// Type-erases a given pager, transforming data to a model as pagination receives new results.
  /// - Parameters:
  ///   - pager: Pager to type-erase.
  public init<Pager: GraphQLQueryPagerCoordinator<InitialQuery, NextQuery>, InitialQuery, NextQuery>(
    pager: Pager
  ) where Model == PaginationOutput<InitialQuery, NextQuery> {
    self.pager = pager
    pager.subscribe { [weak self] result in
      guard let self else { return }
      let returnValue: Output

      switch result {
      case let .success(output):
        returnValue = .success((output, output.updateSource))
      case let .failure(error):
        returnValue = .failure(error)
      }

      _subject.send(returnValue)
    }
  }

  /// Type-erases a given pager, transforming the initial page to an array of models, and the
  /// subsequent pagination to an additional array of models, concatenating the results of each into one array.
  /// - Parameters:
  ///   - pager: Pager to type-erase.
  ///   - initialTransform: Initial transformation from the initial page to an array of models.
  ///   - nextPageTransform: Transformation to execute on each subseqent page to an array of models.
  public convenience init<
    Pager: GraphQLQueryPagerCoordinator<InitialQuery, NextQuery>,
    InitialQuery,
    NextQuery,
    Element
  >(
    pager: Pager,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (NextQuery.Data) throws -> Model
  ) where Model: RangeReplaceableCollection, Model.Element == Element {
    self.init(
      pager: pager,
      transform: { previousData, initialData, nextData in
        let previous = try previousData.flatMap { try pageTransform($0) }
        let initial = try initialTransform(initialData)
        let next = try nextData.flatMap { try pageTransform($0) }
        return previous + initial + next
      }
    )
  }

  deinit {
    pager.cancel()
  }

  /// Subscribe to the results of the pager, with the management of the subscriber being stored internally to the `AnyGraphQLQueryPager`.
  /// - Parameter completion: The closure to trigger when new values come in. Guaranteed to run on the main thread.
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
  /// - Parameter cachePolicy: The apollo cache policy to trigger the first fetch with. Defaults to `fetchIgnoringCacheData`.
  public func refetch(cachePolicy: CachePolicy = .fetchIgnoringCacheData) {
    pager.refetch(cachePolicy: cachePolicy)
  }

  /// Fetches the first page.
  public func fetch() {
    pager.fetch()
  }

  /// Resets pagination state and cancels further updates from the pager.
  public func cancel() {
    pager.cancel()
  }

  public func receive<S>(
    subscriber: S
  ) where S : Subscriber, Never == S.Failure, Result<(Model, UpdateSource), Error> == S.Input {
    let subscription = PagerSubscription(pager: self, subscriber: subscriber)
    subscriber.receive(subscription: subscription)
  }
}

private class PagerSubscription<SubscriberType: Subscriber, Pager: GraphQLQueryPager<Model>, Model>: Subscription where SubscriberType.Input == Pager.Output {
  private var subscriber: SubscriberType?
  private var pager: Pager
  private var cancellable: AnyCancellable?

  init(pager: Pager, subscriber: SubscriberType) {
    self.subscriber = subscriber
    self.pager = pager
    cancellable = pager.publisher.sink(receiveValue: {
      _ = subscriber.receive($0)
    })
  }

  func request(_ demand: Subscribers.Demand) { }

  func cancel() {
    subscriber = nil
  }
}

public extension GraphQLQueryPagerCoordinator {
  func eraseToAnyPager<T>(
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> T
  ) -> GraphQLQueryPager<T> {
    GraphQLQueryPager(pager: self, transform: transform)
  }

  func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    initialTransform: @escaping (InitialQuery.Data) throws -> S,
    nextPageTransform: @escaping (PaginatedQuery.Data) throws -> S
  ) -> GraphQLQueryPager<S> where T == S.Element {
    GraphQLQueryPager(
      pager: self,
      initialTransform: initialTransform,
      pageTransform: nextPageTransform
    )
  }

  func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    transform: @escaping (InitialQuery.Data) throws -> S
  ) -> GraphQLQueryPager<S> where InitialQuery == PaginatedQuery, T == S.Element {
    GraphQLQueryPager(
      pager: self,
      initialTransform: transform,
      pageTransform: transform
    )
  }
}
