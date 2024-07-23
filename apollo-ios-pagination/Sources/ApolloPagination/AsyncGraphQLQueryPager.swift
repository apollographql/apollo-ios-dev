import Apollo
import ApolloAPI
import Combine
import Foundation

/// Type-erases a query pager, transforming data from a generic type to a specific type, often a view model or array of view models.
public class AsyncGraphQLQueryPager<Model: Hashable>: Publisher {
  public typealias Failure = Never
  public typealias Output = Result<Model, any Error>
  let _subject: CurrentValueSubject<Output?, Never> = .init(nil)
  var publisher: AnyPublisher<Output, Never> { _subject.compactMap({ $0 }).eraseToAnyPublisher() }
  @Atomic public var cancellables: Set<AnyCancellable> = []
  public let pager: any AsyncPagerType

  public var canLoadNext: Bool { get async { await pager.canLoadNext } }
  public var canLoadPrevious: Bool { get async { await pager.canLoadPrevious } }

  init<Pager: AsyncGraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager
  ) where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    self.pager = pager
    Task {
      let cancellable = await pager.subscribe { [weak self] result in
        guard let self else { return }
        let returnValue: Output

        switch result {
        case let .success(output):
          returnValue = .success(output)
        case let .failure(error):
          returnValue = .failure(error)
        }

        _subject.send(returnValue)
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
    self.init(
      pager: pager
    )
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
    publisher
      .removeDuplicates(by: { _lhs, _rhs in
        guard let lhs = try? _lhs.get(), let rhs = try? _rhs.get() else { return false }
        return lhs == rhs
      })
      .subscribe(subscriber)
  }
}

extension AsyncGraphQLQueryPager: Equatable where Model: Equatable {
  public static func == (lhs: AsyncGraphQLQueryPager<Model>, rhs: AsyncGraphQLQueryPager<Model>) -> Bool {
    let left = lhs._subject.value
    let right = rhs._subject.value

    switch (left, right) {
    case (.success(let leftValue), .success(let rightValue)):
      return leftValue == rightValue
    case (.failure(let leftError), .failure(let rightError)):
      return leftError.localizedDescription == rightError.localizedDescription
    case (.none, .none):
      return true
    default:
      return false
    }
  }
}
