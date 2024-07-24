import Apollo
import ApolloAPI
import Combine
import Foundation

/// Type-erases a query pager, transforming data from a generic type to a specific type, often a view model or array of view models.
public class AsyncGraphQLQueryPager<Model>: Publisher {
  public typealias Failure = Never
  public typealias Output = Result<Model, any Error>
  let _subject: CurrentValueSubject<Output?, Never> = .init(nil)
  var publisher: AnyPublisher<Output, Never> { _subject.compactMap({ $0 }).eraseToAnyPublisher() }
  @Atomic public var cancellables: Set<AnyCancellable> = []
  public let pager: any AsyncPagerType

  public var canLoadNext: Bool { get async { await pager.canLoadNext } }
  public var canLoadPrevious: Bool { get async { await pager.canLoadPrevious } }

  init<Pager: AsyncGraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager,
    transform: @escaping (PaginationOutput<InitialQuery, PaginatedQuery>) throws -> Model
  ) {
    self.pager = pager
    Task {
      let cancellable = await pager.subscribe { [weak self] result in
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
      _ = $cancellables.mutate { $0.insert(cancellable) }
    }
  }

  init<Pager: AsyncGraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager
  ) where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    self.pager = pager
    Task {
      let cancellable = await pager.subscribe { [weak self] result in
        guard let self else { return }
        _subject.send(result)
      }
      _ = $cancellables.mutate { $0.insert(cancellable) }
    }
  }

  public convenience init<
    P: PaginationInfo,
    InitialQuery: GraphQLQuery,
    PaginatedQuery: GraphQLQuery
  >(
    client: any ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractPageInfo: @escaping (PageExtractionData<InitialQuery, PaginatedQuery, Model?>) -> P,
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?
  ) where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    let pager = AsyncGraphQLQueryPagerCoordinator(
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
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractPageInfo: @escaping (PageExtractionData<InitialQuery, PaginatedQuery, Model?>) -> P,
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?,
    transform: @escaping (PaginationOutput<InitialQuery, PaginatedQuery>) throws -> Model
  ) where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    let pager = AsyncGraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
      extractPageInfo: extractPageInfo,
      pageResolver: pageResolver
    )
    self.init(pager: pager, transform: transform)
  }

  /// Subscribe to the results of the pager, with the management of the subscriber being stored internally to the `AnyGraphQLQueryPager`.
  /// - Parameter completion: The closure to trigger when new values come in.
  @available(*, deprecated, message: "Will be removed in a future version of ApolloPagination. Use the `Combine` publishers instead. If you need to dispatch to the main thread, make sure to use a `.receive(on: RunLoop.main)` as part of your `Combine` operation.")
  public func subscribe(completion: @MainActor @escaping (Output) -> Void) {
    let cancellable = publisher.sink { result in
      Task { await completion(result) }
    }
    _ = $cancellables.mutate { $0.insert(cancellable) }
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

  /// Resets pagination state and cancels in-flight updates from the pager.
  public func reset() async {
    await pager.reset()
  }

  public func receive<S>(
    subscriber: S
  ) where S: Subscriber, Never == S.Failure, Result<Model, any Error> == S.Input {
    publisher.subscribe(subscriber)
  }
}
