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
  public var cancellables: Set<AnyCancellable> = []
  public let pager: any AsyncPagerType

  public var canLoadNext: Bool { get async { await pager.canLoadNext } }
  public var canLoadPrevious: Bool { get async { await pager.canLoadPrevious } }

  init<Pager: AsyncGraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
  ) async {
    self.pager = pager
    await pager.subscribe { [weak self] result in
      guard let self else { return }
      let returnValue: Output

      switch result {
      case let .success((output, source)):
        do {
          let transformedModels = try transform(output.previousPages, output.initialPage, output.nextPages)
          returnValue = .success((transformedModels, source))
        } catch {
          returnValue = .failure(error)
        }
      case let .failure(error):
        returnValue = .failure(error)
      }

      _subject.send(returnValue)
    }.store(in: &cancellables)
  }

  init<Pager: AsyncGraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager
  ) async where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    self.pager = pager
    await pager.subscribe { [weak self] result in
      guard let self else { return }
      let returnValue: Output

      switch result {
      case let .success((output, source)):
        returnValue = .success((output, source))
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

  public convenience init<
    P: PaginationInfo,
    InitialQuery: GraphQLQuery,
    PaginatedQuery: GraphQLQuery,
    Element
  >(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractPageInfo: @escaping (PageExtractionData<InitialQuery, PaginatedQuery, Model?>) -> P,
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
  ) async where Model: RangeReplaceableCollection, Model.Element == Element {
    let pager = AsyncGraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
      extractPageInfo: { data in
        switch data {
        case .initial(let data, let output):
          return extractPageInfo(.initial(data, convertOutput(result: output)))
        case .paginated(let data, let output):
          return extractPageInfo(.paginated(data, convertOutput(result: output)))
        }
      },
      pageResolver: pageResolver
    )
    await self.init(
      pager: pager,
      initialTransform: initialTransform,
      pageTransform: pageTransform
    )

    func convertOutput(result: PaginationOutput<InitialQuery, PaginatedQuery>?) -> Model? {
      guard let result else { return nil }

      let transform: ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model = { previousData, initialData, nextData in
        let previous = try previousData.flatMap { try pageTransform($0) }
        let initial = try initialTransform(initialData)
        let next = try nextData.flatMap { try pageTransform($0) }
        return previous + initial + next
      }
      return try? transform(result.previousPages, result.initialPage, result.nextPages)
    }
  }

  public convenience init<
    P: PaginationInfo,
    InitialQuery: GraphQLQuery,
    PaginatedQuery: GraphQLQuery
  >(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractPageInfo: @escaping (PageExtractionData<InitialQuery, PaginatedQuery, Model?>) -> P,
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?
  ) async where Model == PaginationOutput<InitialQuery, PaginatedQuery> {
    let pager = AsyncGraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
      extractPageInfo: extractPageInfo,
      pageResolver: pageResolver
    )
    await self.init(
      pager: pager
    )
  }

  public convenience init<
    P: PaginationInfo,
    InitialQuery: GraphQLQuery,
    PaginatedQuery: GraphQLQuery
  >(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    watcherDispatchQueue: DispatchQueue = .main,
    extractPageInfo: @escaping (PageExtractionData<InitialQuery, PaginatedQuery, Model?>) -> P,
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
  ) async {
    let pager = AsyncGraphQLQueryPagerCoordinator(
      client: client,
      initialQuery: initialQuery,
      watcherDispatchQueue: watcherDispatchQueue,
      extractPageInfo: { data in
        switch data {
        case .initial(let data, let output):
          return extractPageInfo(.initial(data, convertOutput(result: output)))
        case .paginated(let data, let output):
          return extractPageInfo(.paginated(data, convertOutput(result: output)))
        }
      },
      pageResolver: pageResolver
    )
    await self.init(
      pager: pager,
      transform: transform
    )

    func convertOutput(result: PaginationOutput<InitialQuery, PaginatedQuery>?) -> Model? {
      guard let result else { return nil }
      return try? transform(result.previousPages, result.initialPage, result.nextPages)
    }
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

  /// Resets pagination state and cancels in-flight updates from the pager.
  public func reset() async {
    await pager.reset()    
  }

  public func receive<S>(
    subscriber: S
  ) where S: Subscriber, Never == S.Failure, Result<(Model, UpdateSource), Error> == S.Input {
    publisher.subscribe(subscriber)
  }
}

extension AsyncGraphQLQueryPager: Equatable where Model: Equatable {
  public static func == (lhs: AsyncGraphQLQueryPager<Model>, rhs: AsyncGraphQLQueryPager<Model>) -> Bool {
    let left = lhs._subject.value
    let right = rhs._subject.value

    switch (left, right) {
    case (.success((let leftValue, let leftSource)), .success((let rightValue, let rightSource))):
      return leftValue == rightValue && leftSource == rightSource
    case (.failure(let leftError), .failure(let rightError)):
      return leftError.localizedDescription == rightError.localizedDescription
    default:
      return false
    }
  }
}
