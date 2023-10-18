import Apollo
import ApolloAPI
import Combine

/// Type-erases a query pager, transforming data from a generic type to a specific type, often a view model or array of view models.
public class AnyGraphQLQueryPager<Model> {
  public typealias Output = Result<(Model, UpdateSource), Error>

  private var _subject: CurrentValueSubject<Output?, Never>? = .init(nil)
  private var cancellables = [AnyCancellable]()
  private var pager: any PagerType

  /// Type-erases a given pager, transforming data to a model as pagination receives new results.
  /// - Parameters:
  ///   - pager: Pager to type-erase.
  ///   - transform: Transformation from an initial page and array of paginated pages to a given view model.
  public init<Pager: GraphQLQueryPager<InitialQuery, NextQuery>, InitialQuery, NextQuery>(
    pager: Pager,
    transform: @escaping (InitialQuery.Data, [NextQuery.Data]) throws -> Model
  ) {
    self.pager = pager
    pager.subscribe { result in
      let returnValue: Output

      switch result {
      case let .success(value):
        let (initial, next, updateSource) = value
        do {
          let transformedModels = try transform(initial, next)
          returnValue = .success((transformedModels, updateSource))
        } catch {
          returnValue = .failure(error)
        }
      case let .failure(error):
        returnValue = .failure(error)
      }

      self._subject?.send(returnValue)
    }
  }

  /// Type-erases a given pager, transforming the initial page to an array of models, and the
  /// subsequent pagination to an adition array of models, concatenating the results of each into one array.
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
    nextPageTransform: @escaping (NextQuery.Data) throws -> Model
  ) where Model: RangeReplaceableCollection, Model.Element == Element {
    self.init(
      pager: pager,
      transform: { initialData, nextData in
        let initial = try initialTransform(initialData)
        let next = try nextData.flatMap { try nextPageTransform($0) }
        return initial + next
      }
    )
  }

  @discardableResult public func subscribe(completion: @escaping (Output) -> Void) -> AnyCancellable {
    guard let _subject else { return AnyCancellable({ }) }

    let cancellable = _subject.compactMap({ $0 }).sink { result in
      completion(result)
    }
    cancellable.store(in: &cancellables)
    return cancellable
  }

  public func loadMore(
    cachePolicy: CachePolicy = .returnCacheDataAndFetch,
    completion: (@MainActor () -> Void)? = nil
  ) throws {
    try pager.loadMore(cachePolicy: cachePolicy, completion: completion)
  }

  public func loadMoreLegacy(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: (@MainActor () -> Void)? = nil
  ) -> Bool {
    do {
      try loadMore(cachePolicy: cachePolicy, completion: completion)
      return pager.canLoadNext()
    } catch {
      return false
    }
  }

  public func refetch(cachePolicy: CachePolicy = .returnCacheDataAndFetch) {
    pager.refetch(cachePolicy: cachePolicy)
  }

  public func cancel() {
    pager.cancel()
  }
}

extension AnyGraphQLQueryPager where Model: RangeReplaceableCollection {
  public func subscribe(completion: @escaping (WatchResult<Model>) -> Void) {
    _subject?.compactMap({ $0 }).sink { result in
      completion(legacyMapper(result: result))
    }.store(in: &cancellables)
  }
}

public extension GraphQLQueryPager.Actor {
  nonisolated func eraseToAnyPager<T>(
    transform: @escaping (InitialQuery.Data, [PaginatedQuery.Data]) throws -> T
  ) -> AnyGraphQLQueryPager<T> {
    AnyGraphQLQueryPager(
      pager: GraphQLQueryPager(pager: self),
      transform: transform
    )
  }

  nonisolated func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    initialTransform: @escaping (InitialQuery.Data) throws -> S,
    nextPageTransform: @escaping (PaginatedQuery.Data) throws -> S
  ) -> AnyGraphQLQueryPager<S> where T == S.Element {
    AnyGraphQLQueryPager(
      pager: GraphQLQueryPager(pager: self),
      initialTransform: initialTransform,
      nextPageTransform: nextPageTransform
    )
  }

  nonisolated func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    transform: @escaping (InitialQuery.Data) throws -> S
  ) -> AnyGraphQLQueryPager<S> where InitialQuery == PaginatedQuery, T == S.Element {
    AnyGraphQLQueryPager(
      pager: GraphQLQueryPager(pager: self),
      initialTransform: transform,
      nextPageTransform: transform
    )
  }
}

public extension GraphQLQueryPager {
  func eraseToAnyPager<T>(
    transform: @escaping (InitialQuery.Data, [PaginatedQuery.Data]) throws -> T
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
      nextPageTransform: nextPageTransform
    )
  }

  func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    transform: @escaping (InitialQuery.Data) throws -> S
  ) -> AnyGraphQLQueryPager<S> where InitialQuery == PaginatedQuery, T == S.Element {
    AnyGraphQLQueryPager(
      pager: self,
      initialTransform: transform,
      nextPageTransform: transform
    )
  }
}

/// Maps results which include an update source to the legacy WatchResult type.
/// Note that this function is only implemented for `[Model]`, which was the most common consumer of `WatchResult`.
/// - Parameter result: Result containing an update source.
/// - Returns: Watch result mapped to the update source.
private func legacyMapper<Model, S: RangeReplaceableCollection>(result: Result<(S, UpdateSource), Error>) -> WatchResult<S> where S.Element == Model {
  switch result {
  case let .success(value):
    let (pages, update) = value
    return .success(pages, update)
  case .failure(let error):
    return .failure(error)
  }
}
