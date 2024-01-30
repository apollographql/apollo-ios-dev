import Apollo
import ApolloAPI
import Combine
import Foundation

/// Type-erases a query pager, transforming data from a generic type to a specific type, often a view model or array of view models.
public class AsyncGraphQLQueryPager<Model>: Publisher {
  public typealias Failure = Never
  public typealias Output = Result<(Model, UpdateSource), Error>
  let _subject: CurrentValueSubject<Output?, Never> = .init(nil)
  var publisher: AnyPublisher<Output, Never> { _subject.compactMap({ $0 }).eraseToAnyPublisher() }
  public var cancellables = [AnyCancellable]()
  public let pager: any AsyncPagerType

  public var canLoadNext: Bool { get async { await pager.canLoadNext } }
  public var canLoadPrevious: Bool { get async { await pager.canLoadPrevious } }

  /// Type-erases a given pager, transforming data to a model as pagination receives new results.
  /// - Parameters:
  ///   - pager: Pager to type-erase.
  ///   - transform: Transformation from an initial page and array of paginated pages to a given view model.
  init<Pager: AsyncGraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
  ) async {
    self.pager = pager
    await pager.subscribe { [weak self] result in
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
    }.store(in: &cancellables)
  }

  /// Type-erases a given pager, transforming data to a model as pagination receives new results.
  /// - Parameters:
  ///   - pager: Pager to type-erase.
  init<Pager: AsyncGraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager
  ) async where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    self.pager = pager
    await pager.subscribe { [weak self] result in
      guard let self else { return }
      let returnValue: Output

      switch result {
      case let .success(output):
        returnValue = .success((output, output.updateSource))
      case let .failure(error):
        returnValue = .failure(error)
      }

      _subject.send(returnValue)
    }.store(in: &cancellables)
  }

  convenience init<
    Pager: AsyncGraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>,
    InitialQuery,
    PaginatedQuery,
    Element
  >(
    pager: Pager,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
  ) async where Model: RangeReplaceableCollection, Model.Element == Element {
    await self.init(
      pager: pager,
      transform: { previousData, initialData, nextData in
        let previous = try previousData.flatMap { try pageTransform($0) }
        let initial = try initialTransform(initialData)
        let next = try nextData.flatMap { try pageTransform($0) }
        return previous + initial + next
      }
    )
  }

  /// Type-erases a given pager, transforming the initial page to an array of models, and the
  /// subsequent pagination to an additional array of models, concatenating the results of each into one array.
  /// - Parameters:
  ///   - pager: Pager to type-erase.
  ///   - initialTransform: Initial transformation from the initial page to an array of models.
  ///   - nextPageTransform: Transformation to execute on each subseqent page to an array of models.
  public convenience init<
    P: PaginationInfo,
    InitialQuery: GraphQLQuery,
    PaginatedQuery: GraphQLQuery,
    Element
  >(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractPageInfo: @escaping (PageExtractionData<InitialQuery, PaginatedQuery>) -> P,
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
  ) async where Model: RangeReplaceableCollection, Model.Element == Element {
    let pager = AsyncGraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
      extractPageInfo: extractPageInfo,
      pageResolver: pageResolver
    )
    await self.init(
      pager: pager,
      initialTransform: initialTransform,
      pageTransform: pageTransform
    )
  }

  /// Subscribe to the results of the pager, with the management of the subscriber being stored internally to the `AnyGraphQLQueryPager`.
  /// - Parameter completion: The closure to trigger when new values come in.
  public func subscribe(completion: @MainActor @escaping (Output) -> Void) {
    publisher.sink { result in
      Task { await completion(result) }
    }.store(in: &cancellables)
  }

  /// Load the next page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `returnCacheDataAndFetch`.
  public func loadNext(
    cachePolicy: CachePolicy = .returnCacheDataAndFetch
  ) async throws {
    try await pager.loadNext(cachePolicy: cachePolicy)
  }

  /// Load the previous page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `returnCacheDataAndFetch`.
  public func loadPrevious(
    cachePolicy: CachePolicy = .returnCacheDataAndFetch
  ) async throws {
    try await pager.loadPrevious(cachePolicy: cachePolicy)
  }

  /// Loads all pages.
  /// - Parameters:
  ///   - fetchFromInitialPage: Pass true to begin loading from the initial page; otherwise pass false.  Defaults to `true`.  **NOTE**: Loading all pages with this value set to `false` requires that the initial page has already been loaded previously.
  public func loadAll(
    fetchFromInitialPage: Bool = true
  ) async throws {
    try await pager.loadAll(fetchFromInitialPage: fetchFromInitialPage)
  }

  /// Discards pagination state and fetches the first page from scratch.
  /// - Parameter cachePolicy: The apollo cache policy to trigger the first fetch with. Defaults to `fetchIgnoringCacheData`.
  public func refetch(cachePolicy: CachePolicy = .fetchIgnoringCacheData) async {
    await pager.refetch(cachePolicy: cachePolicy)
  }

  /// Fetches the first page.
  public func fetch() async {
    await pager.fetch()
  }

  /// Resets pagination state and cancels further updates from the pager.
  public func cancel() async {
    await pager.cancel()
  }

  public func receive<S>(
    subscriber: S
  ) where S : Subscriber, Never == S.Failure, Result<(Model, UpdateSource), Error> == S.Input {
    let subscription = PagerSubscription(pager: self, subscriber: subscriber)
    subscriber.receive(subscription: subscription)
  }
}

private class PagerSubscription<SubscriberType: Subscriber, Pager: AsyncGraphQLQueryPager<Model>, Model>: Subscription where SubscriberType.Input == Pager.Output {
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


extension AsyncGraphQLQueryPagerCoordinator {
  nonisolated func eraseToAnyPager<T>(
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> T
  ) async -> AsyncGraphQLQueryPager<T> {
    await AsyncGraphQLQueryPager(
      pager: self,
      transform: transform
    )
  }

  nonisolated func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    initialTransform: @escaping (InitialQuery.Data) throws -> S,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> S
  ) async -> AsyncGraphQLQueryPager<S> where T == S.Element {
    await AsyncGraphQLQueryPager(
      pager: self,
      initialTransform: initialTransform,
      pageTransform: pageTransform
    )
  }

  nonisolated func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    transform: @escaping (InitialQuery.Data) throws -> S
  ) async -> AsyncGraphQLQueryPager<S> where InitialQuery == PaginatedQuery, T == S.Element {
    await AsyncGraphQLQueryPager(
      pager: self,
      initialTransform: transform,
      pageTransform: transform
    )
  }
}
