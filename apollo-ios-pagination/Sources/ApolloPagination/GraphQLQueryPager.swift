import Apollo
import ApolloAPI
import Combine
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

  init<Pager: GraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>, InitialQuery, PaginatedQuery>(
    pager: Pager,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
  ) {
    self.pager = pager
    pager.subscribe { [weak self] result in
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

  convenience init<
    Pager: GraphQLQueryPagerCoordinator<InitialQuery, PaginatedQuery>,
    InitialQuery,
    PaginatedQuery,
    Element
  >(
    pager: Pager,
    initialTransform: @escaping (InitialQuery.Data) throws -> Model,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> Model
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

  public convenience init<
    P: PaginationInfo,
    InitialQuery: GraphQLQuery,
    PaginatedQuery: GraphQLQuery
  >(
    client: ApolloClientProtocol,
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
  ) where Model: RangeReplaceableCollection, Model.Element == Element {
    let pager = GraphQLQueryPagerCoordinator(
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
    self.init(
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
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?,
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> Model
  ) {
    let pager = GraphQLQueryPagerCoordinator(
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
    self.init(
      pager: pager,
      transform: transform
    )

    func convertOutput(result: PaginationOutput<InitialQuery, PaginatedQuery>?) -> Model? {
      guard let result else { return nil }
      return try? transform(result.previousPages, result.initialPage, result.nextPages)
    }
  }

  deinit {
    pager.reset()
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
  ) where S: Subscriber, Never == S.Failure, Result<(Model, UpdateSource), Error> == S.Input {
    publisher.subscribe(subscriber)
  }
}

extension GraphQLQueryPager: Equatable where Model: Equatable {
  public static func == (lhs: GraphQLQueryPager<Model>, rhs: GraphQLQueryPager<Model>) -> Bool {
    let left = lhs._subject.value
    let right = rhs._subject.value

    switch (left, right) {
    case (.success((let leftValue, let leftSource)), .success((let rightValue, let rightSource))):
      return leftValue == rightValue && leftSource == rightSource
    case (.failure(let leftError), .failure(let rightError)):
      return leftError.localizedDescription == rightError.localizedDescription
    case (.none, .none):
      return true
    default:
      return false
    }
  }
}
