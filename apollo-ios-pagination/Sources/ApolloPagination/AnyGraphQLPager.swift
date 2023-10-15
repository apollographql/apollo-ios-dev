import Apollo
import ApolloAPI
import Combine

/// Type-erases a query pager, transforming data from a generic type to a specific type, often a view model or array of view models.
public class AnyGraphQLQueryPager<Model> {
  public typealias Output = Result<(Model, UpdateSource), Error>

  private let _fetch: (CachePolicy) -> Void
  private let _loadMore: (CachePolicy, (() -> Void)?) throws -> Void
  private let _refetch: (CachePolicy) -> Void
  private let _cancel: () -> Void
  private let _subject: AnyPublisher<Output, Never>
  private let _canLoadNext: () -> Bool
  private var cancellables = [AnyCancellable]()

  /// Type-erases a given pager, transforming data to a model as pagination receives new results.
  /// - Parameters:
  ///   - pager: Pager to type-erase.
  ///   - transform: Transformation from an initial page and array of paginated pages to a given view model.
  public init<Pager: GraphQLQueryPager<InitialQuery, NextQuery>, InitialQuery, NextQuery>(
    pager: Pager,
    transform: @escaping (InitialQuery.Data, [NextQuery.Data]) throws -> Model
  ) {
    _fetch = pager.fetch
    _loadMore = pager.loadMore
    _refetch = pager.refetch
    _cancel = pager.cancel

    _subject = pager.subject.map { result in
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

      return returnValue
    }.eraseToAnyPublisher()
    _canLoadNext = pager.canLoadNext
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

  public func subscribe(completion: @escaping (Output) -> Void) {
    _subject.sink { result in
      completion(result)
    }.store(in: &cancellables)
  }

  public func fetch(cachePolicy: CachePolicy = .returnCacheDataAndFetch) {
    _fetch(cachePolicy)
  }

  public func loadMore(
    cachePolicy: CachePolicy = .returnCacheDataAndFetch,
    completion: (() -> Void)? = nil
  ) throws {
    try _loadMore(cachePolicy, completion)
  }

  public func refetch(cachePolicy: CachePolicy = .returnCacheDataAndFetch) {
    _refetch(cachePolicy)
  }

  public func cancel() {
    _cancel()
  }
}

public extension GraphQLQueryPager {
  func eraseToAnyPager<T>(
    transform: @escaping (InitialQuery.Data, [PaginatedQuery.Data]) throws -> T
  ) -> AnyGraphQLQueryPager<T> {
    AnyGraphQLQueryPager<T>(pager: self, transform: transform)
  }

  func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    initialTransform: @escaping (InitialQuery.Data) throws -> S,
    nextPageTransform: @escaping (PaginatedQuery.Data) throws -> S
  ) -> AnyGraphQLQueryPager<S> where T == S.Element {
    AnyGraphQLQueryPager<S>(pager: self, initialTransform: initialTransform, nextPageTransform: nextPageTransform)
  }

  func eraseToAnyPager<T, S: RangeReplaceableCollection>(
    transform: @escaping (InitialQuery.Data) throws -> S
  ) -> AnyGraphQLQueryPager<S> where InitialQuery == PaginatedQuery, T == S.Element {
    AnyGraphQLQueryPager<S>(pager: self, initialTransform: transform, nextPageTransform: transform)
  }
}
