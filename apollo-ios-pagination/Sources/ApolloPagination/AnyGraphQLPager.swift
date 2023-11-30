import Apollo
import ApolloAPI
import Combine

/// Type-erases a query pager, transforming data from a generic type to a specific type, often a view model or array of view models.
public class AnyGraphQLQueryPager<Model> {
  public typealias Output = Result<(Model, UpdateSource), Error>

  private var _subject: CurrentValueSubject<Output?, Never> = .init(nil)
  private var cancellables = [AnyCancellable]()
  private var pager: any PagerType

  public var canLoadNext: Bool { pager.canLoadNext }
  public var canLoadPrevious: Bool { pager.canLoadPrevious }

  /// Type-erases a given pager, transforming data to a model as pagination receives new results.
  /// - Parameters:
  ///   - pager: Pager to type-erase.
  ///   - transform: Transformation from an initial page and array of paginated pages to a given view model.
  public init<Pager: GraphQLQueryPager<InitialQuery, NextQuery>, InitialQuery, NextQuery>(
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
          let transformedModels = try transform(output.previousPages.elements, output.initialPage, output.nextPages.elements)
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

  /// Type-erases a given pager, transforming the initial page to an array of models, and the
  /// subsequent pagination to an additional array of models, concatenating the results of each into one array.
  /// - Parameters:
  ///   - pager: Pager to type-erase.
  ///   - initialTransform: Initial transformation from the initial page to an array of models.
  ///   - nextPageTransform: Transformation to execute on each subseqent page to an array of models.
  public convenience init<
    Pager: GraphQLQueryPager<InitialQuery, NextQuery>,
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

  /// Subscribe to the results of the pager, returning an `AnyCancellable` for the caller to manage.
  /// - Parameter completion: The closure to trigger when new values come in.
  /// - Returns: an `AnyCancellable` value that has not been stored internal to the `AnyGraphQLPager`.
  public func sink(completion: @MainActor @escaping (Output) -> Void) -> AnyCancellable {
    return _subject.compactMap({ $0 }).sink { result in
      Task { await completion(result) }
    }
  }

  /// Subscribe to the results of the pager, with the management of the subscriber being stored internally to the `AnyGraphQLQueryPager`.
  /// - Parameter completion: The closure to trigger when new values come in.
  public func subscribe(completion: @MainActor @escaping (Output) -> Void) {
    sink(completion: completion).store(in: &cancellables)
  }

  /// Load the next page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `returnCacheDataAndFetch`.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadNext(
    cachePolicy: CachePolicy = .returnCacheDataAndFetch,
    completion: (@MainActor (Error?) -> Void)? = nil
  ) {
    pager.loadNext(cachePolicy: cachePolicy, completion: completion)
  }

  /// Load the previous page, if available.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `returnCacheDataAndFetch`.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadPrevious(
    cachePolicy: CachePolicy = .returnCacheDataAndFetch,
    completion: (@MainActor (Error?) -> Void)? = nil
  ) {
    pager.loadPrevious(cachePolicy: cachePolicy, completion: completion)
  }

  /// Loads all pages.
  /// - Parameters:
  ///   - fetchFromInitialPage: Pass true to begin loading from the initial page; otherwise pass false.  Defaults to `true`.  **NOTE**: Loading all pages with this value set to `false` requires that the initial page has already been loaded previously.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadAll(
    fetchFromInitialPage: Bool = true,
    completion: (@MainActor (Error?) -> Void)? = nil
  ) {
    pager.loadAll(fetchFromInitialPage: fetchFromInitialPage, completion: completion)
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
}

extension GraphQLQueryPager.Actor {
  nonisolated func eraseToAnyPager<T>(
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> T
  ) -> AnyGraphQLQueryPager<T> {
    AnyGraphQLQueryPager(
      pager: GraphQLQueryPager(pager: self),
      transform: transform
    )
  }

  nonisolated func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    initialTransform: @escaping (InitialQuery.Data) throws -> S,
    pageTransform: @escaping (PaginatedQuery.Data) throws -> S
  ) -> AnyGraphQLQueryPager<S> where T == S.Element {
    AnyGraphQLQueryPager(
      pager: GraphQLQueryPager(pager: self),
      initialTransform: initialTransform,
      pageTransform: pageTransform
    )
  }

  nonisolated func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    transform: @escaping (InitialQuery.Data) throws -> S
  ) -> AnyGraphQLQueryPager<S> where InitialQuery == PaginatedQuery, T == S.Element {
    AnyGraphQLQueryPager(
      pager: GraphQLQueryPager(pager: self),
      initialTransform: transform,
      pageTransform: transform
    )
  }
}

public extension GraphQLQueryPager {
  func eraseToAnyPager<T>(
    transform: @escaping ([PaginatedQuery.Data], InitialQuery.Data, [PaginatedQuery.Data]) throws -> T
  ) -> AnyGraphQLQueryPager<T> {
    AnyGraphQLQueryPager(pager: self, transform: transform)
  }

  func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    initialTransform: @escaping (InitialQuery.Data) throws -> S,
    nextPageTransform: @escaping (PaginatedQuery.Data) throws -> S
  ) -> AnyGraphQLQueryPager<S> where T == S.Element {
    AnyGraphQLQueryPager(
      pager: self,
      initialTransform: initialTransform,
      pageTransform: nextPageTransform
    )
  }

  func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    transform: @escaping (InitialQuery.Data) throws -> S
  ) -> AnyGraphQLQueryPager<S> where InitialQuery == PaginatedQuery, T == S.Element {
    AnyGraphQLQueryPager(
      pager: self,
      initialTransform: transform,
      pageTransform: transform
    )
  }
}
