import Foundation
@_spi(Unsafe) @_spi(Execution) import ApolloAPI

/// The ``ApolloStoreSubscriber`` provides a means to observe changes to items in the ``ApolloStore``.
/// This protocol is available for advanced use cases only. Most users will prefer using `ApolloClient.watch(query:)`.
public protocol ApolloStoreSubscriber: AnyObject, Sendable {

  /// This function will be called when fields are changed within the cache.
  ///
  /// - Parameters:
  ///   - store: The ``ApolloStore`` which made the changes.
  ///   - changedKeys: The set of ``CacheDependentKey``s identifying each
  ///     `(cacheKey, fieldName)` pair whose stored value changed in the
  ///     underlying cache. Subscribers can intersect this set with the
  ///     dependent-key set recorded on their last read to detect
  ///     whether the change is relevant.
  func store(_ store: ApolloStore, didChangeKeys changedKeys: Set<CacheDependentKey>)
}

/// The ``ApolloStore`` class manages access to a local cache for reading/writing normalized GraphQL results.
///
/// An ``ApolloStore`` wraps an underlying ``NormalizedCache``, providing type-safe and thread-safe APIs for accessing
/// the cache's underlying data.
///
/// ``NormalizedCache`` operates on the untyped cache ``Record``s and is not thread-safe. ``ApolloStore`` validates raw
/// cache data and exposes it via strongly-typed generated operation models. It also uses a read/write lock that
/// ensures thread-safe access to the underlying ``NormalizedCache``.
///
/// - Warning: Using the same ``NormalizedCache`` with multiple ``ApolloStore`` instances at the same time is
/// unsupported and can result in undefined behavior, data races, and crashes.
/// The store uses an internal read/write lock to protect against concurrent write access to the ``NormalizedCache``.
/// This means that the ``NormalizedCache`` implementation does not need to manage thread safety. If a cache is used
/// with multiple ``ApolloStore`` instances, no guarantees about thread safety can be made.
public final class ApolloStore: Sendable {
  private let readerWriterLock = AsyncReadWriteLock()

  /// The underlying cache wrapped by the store.
  ///
  /// - Important: The ``NormalizedCache`` itself is not thread-safe. Access to the cache by a single store is made
  /// thread-safe by using a ``AsyncReadWriteLock``. All access to the cache must be done within the
  /// `readerWriterLock`. For cache writes/removes, use a `readerWriterLock.write { }` block. For read only access,
  /// use a `readerWriterLock.read { }` block.
  nonisolated(unsafe) private let cache: any NormalizedCache

  /// A dictionary that keeps track of subscribers that will receive updates when the store's data changes.
  ///
  /// - Important: In order to comply with `Sendable` requirements, this unsafe property should
  /// only be accessed within a `readerWriterLock.write { }` block.
  nonisolated(unsafe) private(set) var subscribers: [SubscriptionToken: any ApolloStoreSubscriber] = [:]

  /// Designated initializer
  /// - Parameters:
  ///   - cache: A ``NormalizedCache`` used to store cached results.
  ///            Defaults to an ``InMemoryNormalizedCache``.
  public init(cache: any NormalizedCache = InMemoryNormalizedCache()) {
    self.cache = cache
  }

  fileprivate func didChangeKeys(_ changedKeys: Set<CacheDependentKey>) {
    for subscriber in self.subscribers.values {
      subscriber.store(self, didChangeKeys: changedKeys)
    }
  }

  /// Clears all data from the store's underlying cache.
  public func clearCache() async throws {
    try await readerWriterLock.write {
      try await self.cache.clear()
    }
  }

  /// Merges a ``RecordSet`` into the normalized cache.
  ///
  /// - Parameters:
  ///   - records: The records to be merged into the cache.
  public func publish(records: RecordSet) async throws {
    try await readerWriterLock.write {
      let changedKeys = try await self.cache.merge(records: records)
      self.didChangeKeys(changedKeys)
    }
  }

  /// Subscribes to notifications for changes to the store's cache data.
  ///
  /// - Parameters:
  ///    - subscriber: A subscriber to receive content change notificatons. To avoid a retain cycle,
  ///    ensure you call `unsubscribe` passing the returned ``SubscriptionToken`` before it goes out of scope.
  public func subscribe(_ subscriber: any ApolloStoreSubscriber) async -> SubscriptionToken {
    let token = SubscriptionToken(id: ObjectIdentifier(subscriber))
    try? await readerWriterLock.write {
      self.subscribers[token] = subscriber
    }
    return token
  }

  /// Unsubscribes from notifications for changes to the store's cache data.
  ///
  /// - Parameters:
  ///    - subscriptionToken: An opaque token for the subscriber that was provided via `subscribe(_:)`.
  ///    To avoid retain cycles, call `unsubscribe` on all active subscribers before they go out of scope.
  public func unsubscribe(_ subscriptionToken: SubscriptionToken) {
    Task(priority: Task.currentPriority > .medium ? .medium : Task.currentPriority) {
      try? await readerWriterLock.write {
        self.subscribers.removeValue(forKey: subscriptionToken)
      }
    }
  }

  /// Performs an operation within a read transaction
  ///
  /// While inside of a read-only transaction block, concurrent write access to the cache is blocked.
  ///
  /// - Parameters:
  ///   - body: The body of the operation to perform.
  public func withinReadTransaction<T: Sendable>(
    _ body: @Sendable @escaping (ReadTransaction) async throws -> T
  ) async throws -> T {
    nonisolated(unsafe) var value: T!
    try await readerWriterLock.read {
      value = try await body(ReadTransaction(store: self))
    }
    return value
  }

  /// Performs an operation within a read/write transaction
  ///
  /// While inside of a read/write transaction block, concurrent read and write access to the cache is blocked.
  ///
  /// - Parameters:
  ///   - body: The body of the operation to perform
  public func withinReadWriteTransaction<T: Sendable>(
    _ body: @Sendable @escaping (ReadWriteTransaction) async throws -> T
  ) async throws -> T {
    nonisolated(unsafe) var value: T!
    try await readerWriterLock.write {
      value = try await body(ReadWriteTransaction(store: self))
    }
    return value
  }

  /// Loads the results for the given operation from the cache.
  ///
  /// - Parameters:
  ///   - operation: The operation to load results for
  /// - Returns: The ``GraphQLResponse`` loaded from the cache. On a cache miss, this will return `nil`.
  public func load<Operation: GraphQLOperation>(
    _ operation: Operation
  ) async throws -> GraphQLResponse<Operation>? {
    do {
      return try await withinReadTransaction { transaction in
        let (dataDict, dependentKeys) = try await transaction.readObject(
          ofType: Operation.Data.self,
          withKey: CacheReference.rootCacheReference(for: Operation.operationType).key,
          variables: operation.__variables,
          accumulator: zip(
            DataDictMapper(),
            GraphQLDependencyTracker()
          )
        )

        return GraphQLResponse<Operation>(
          data: Operation.Data(_dataDict: dataDict),
          extensions: nil,
          errors: nil,
          source: .cache,
          dependentKeys: dependentKeys
        )
      }
    } catch JSONDecodingError.missingValue {
      return nil
    } catch let error as GraphQLExecutionError {
      if case JSONDecodingError.missingValue = error.underlying {
        return nil
      } else {
        throw error
      }
    }
  }

  // MARK: -

  /// An opaque token used to track an ``ApolloStoreSubscriber`` subscribed to an ``ApolloStore``.
  ///
  /// When ``ApolloStore/subscribe(_:)`` is called, a ``SubscriptionToken`` is returned. This token can be passed to
  /// ``ApolloStore/unsubscribe(_:)`` to unsubscribe the original ``ApolloStoreSubscriber`` from store updates.
  public struct SubscriptionToken: Sendable, Hashable {
    let id: ObjectIdentifier
  }

  // MARK: -
  public enum Error: Swift.Error {
    case notWithinReadTransaction
  }

  // MARK: -

  /// A read-only transaction used to access an ``ApolloStore``'s cache data.
  ///
  /// A ``ReadTransaction`` is provided as a parameter of the transaction block of
  /// ``ApolloStore/withinReadTransaction(_:)``. While inside of a read-only transaction block, concurrent write access
  /// to the cache is blocked.
  ///
  /// - Note: A ``ReadTransaction`` should only be accessed from within the body of the
  /// ``ApolloStore/withinReadTransaction(_:)`` that provided it. Capturing and using the transaction outside of the
  /// transaction block may cause data races or crashes.
  public class ReadTransaction {
    fileprivate let _cache: any NormalizedCache

    /// A read-only view of the underlying ``NormalizedCache`` the transaction is operating upon.
    ///
    /// It is safe to directly load the raw record data of the cache from within the transaction block.
    public var readOnlyCache: any ReadOnlyNormalizedCache { _cache }

    fileprivate lazy var projectionLoader: ProjectionLoader = ProjectionLoader { [weak self] projections in
      guard let self else { return [:] }
      return try await _cache.loadFields(projections)
    }

    fileprivate lazy var executor = GraphQLExecutor(
      executionSource: CacheDataExecutionSource(transaction: self)
    )

    fileprivate init(store: ApolloStore) {
      self._cache = store.cache
    }

    /// Reads a `GraphQLQuery` from the transaction's underlying cache. This read operation loads the records for the
    /// query's data from the cache, validates it, and transforms it into the query's associated reponse model.
    ///
    /// - Parameter query: The `GraphQLQuery` to read from the cache.
    /// - Returns: An instance of the query's response model containing the loaded data.
    public func read<Query: GraphQLQuery>(query: Query) async throws -> Query.Data {
      return try await readObject(
        ofType: Query.Data.self,
        withKey: CacheReference.rootCacheReference(for: Query.operationType).key,
        variables: query.__variables
      )
    }
    
    /// Reads an object from the transaction's underlying cache. This read operation loads the records for the
    /// object's data from the cache, validates it, and transforms it into the provided response model.
    ///
    /// - Parameters:
    ///   - type: A `RootSelectionSet`.Type for the object to read from the cache.
    ///   - key: The ``CacheKey`` of the object to read from the cache.
    ///   - variables: Any operation variables necessary to resolve selected field's on the object. Defaults to `nil`.
    /// - Returns: An instance of the object's response model containing the loaded data.
    public func readObject<SelectionSet: RootSelectionSet>(
      ofType type: SelectionSet.Type,
      withKey key: CacheKey,
      variables: GraphQLOperation.Variables? = nil
    ) async throws -> SelectionSet {
      let dataDict = try await self.readObject(
        ofType: type,
        withKey: key,
        variables: variables,
        accumulator: DataDictMapper()
      )
      return type.init(_dataDict: dataDict)
    }

    func readObject<SelectionSet: RootSelectionSet, Accumulator: GraphQLResultAccumulator>(
      ofType type: SelectionSet.Type,
      withKey key: CacheKey,
      variables: GraphQLOperation.Variables? = nil,
      accumulator: Accumulator
    ) async throws -> Accumulator.FinalResult {
      let object = try await loadObject(
        forKey: key,
        selections: type.__selections,
        variables: variables,
        schema: SelectionSet.Schema.self
      ).get()

      return try await executor.execute(
        selectionSet: type,
        on: object,
        withRootCacheReference: CacheReference(key),
        variables: variables,
        accumulator: accumulator
      )
    }

    /// Loads the projected fields the given selection set would
    /// traverse on the record at `key`, returning the partial Record
    /// containing those fields. Per ADR 0007 sub-phase 1A.5, this is
    /// the projection-driven replacement for the 2.x whole-record
    /// `loadObject(forKey:)` path: the read batches via
    /// `ProjectionLoader`, which coalesces every projection enqueued
    /// across the executor's deferred resolutions into one
    /// `NormalizedCache.loadFields(_:)` call when the first
    /// `PossiblyDeferred` is forced.
    ///
    /// Inline fragments are projected unconditionally
    /// (`includeAllInlineFragments: true`) because the child record's
    /// `__typename` is not yet loaded at projection time. The
    /// executor's later selection-set traversal uses the loaded
    /// `__typename` to pick the matching type case; the unmatched
    /// type-case fields are an over-fetch that PR-009g will narrow
    /// once SQL-level projection lands on the SQLite backend.
    final func loadObject(
      forKey key: CacheKey,
      selections: [Selection],
      variables: GraphQLOperation.Variables?,
      schema: (any SchemaMetadata.Type)? = nil,
      responsePath: ResponsePath = []
    ) -> PossiblyDeferred<Record> {
      let projections: Set<FieldProjection>
      do {
        projections = try FieldProjectionCollector.collect(
          selections: selections,
          cacheKey: key,
          variables: variables,
          resolveRuntimeType: { nil },
          includeAllInlineFragments: true,
          schema: schema,
          responsePath: responsePath
        )
      } catch {
        return .immediate(.failure(error))
      }
      // Empty projection set means every selected field on this record
      // resolves without consulting the parent's storage — typically
      // because all fields are `@fieldPolicy`-redirected and produce
      // their own `CacheReference`s directly. Skip the parent load and
      // hand the executor an empty `Record` to dispatch against; each
      // field's `resolveCacheKey` will derive its value from the
      // strategy alone. Matches Apollo Kotlin's
      // `FieldPolicyCacheResolver`: a policy-resolved field does not
      // require the parent record to exist.
      guard !projections.isEmpty else {
        return .immediate(.success(Record(key: key, fields: [:])))
      }
      projectionLoader.enqueue(projections)
      return projectionLoader.deferredRecord(forKey: key).map { record in
        // `nil` here means the record is *absent* from the cache. The
        // projection-aware `loadFields(_:)` contract preserves the
        // existence signal: records that exist but happen to lack
        // every requested field come back as `Record(fields: [:])`,
        // not nil. That distinction lets the executor's per-field
        // resolution surface `missingValue` with response-path
        // context — matching the legacy whole-record read path's
        // behavior — instead of failing the whole load here.
        guard let record else { throw JSONDecodingError.missingValue }
        return record
      }
    }
  }

  /// A read/write transaction used to access an ``ApolloStore``'s cache data.
  ///
  /// A ``ReadWriteTransaction`` is provided as a parameter of the transaction block of
  /// ``ApolloStore/withinReadWriteTransaction(_:)``. While inside of a read/write transaction block, concurrent
  /// read and write access to the cache is blocked.
  ///
  /// - Note: A ``ReadWriteTransaction`` should only be accessed from within the body of the
  /// ``ApolloStore/withinReadWriteTransaction(_:)`` that provided it. Capturing and using the transaction outside of
  /// the transaction block may cause data races or crashes.
  public final class ReadWriteTransaction: ReadTransaction {

    /// The underlying ``NormalizedCache`` the transaction is operating upon.
    ///
    /// It is safe to directly operate on the raw record data of the cache from within the transaction block.
    public var cache: any NormalizedCache { _cache }
    
    fileprivate var updateChangedKeysFunc: ((Set<CacheDependentKey>) -> Void)?

    override init(store: ApolloStore) {
      self.updateChangedKeysFunc = store.didChangeKeys
      super.init(store: store)
    }

    /// Updates the data for a `LocalCacheMutation` in the transaction's underlying cache. This operation loads the
    /// records for the cache mutation's data from the cache, validates it, and transforms it into the cache mutation's
    /// associated reponse model. The response model for the cache mutation is then passed to the `body` block where it
    /// may be mutated. Once the `body` block completes, the final mutated data is written back to the cache.
    ///
    /// - Parameters:
    ///   - cacheMutation: The `LocalCacheMutation` to mutate data for in the cache.
    ///   - body: A block used to mutate the response data of the cache mutation.
    public func update<CacheMutation: LocalCacheMutation>(
      _ cacheMutation: CacheMutation,
      _ body: (inout CacheMutation.Data) throws -> Void
    ) async throws {
      try await updateObject(
        ofType: CacheMutation.Data.self,
        withKey: CacheReference.rootCacheReference(for: CacheMutation.operationType).key,
        variables: cacheMutation.__variables,
        body
      )
    }

    /// Updates the data for an object in the transaction's underlying cache. This operation loads the records for the
    /// object's data from the cache, validates it, and transforms it into the provided associated reponse model.
    /// The object is then passed to the `body` block where it may be mutated. Once the `body` block completes, the
    /// final mutated data is written back to the cache.
    ///
    /// - Parameters:
    ///   - type: A `MutableRootSelectionSet` to mutate data for in the cache.
    ///   - key: The ``CacheKey`` of the object to read from the cache.
    ///   - variables: Any operation variables necessary to resolve selected field's on the object. Defaults to `nil`.
    ///   - body: A block used to mutate the response data of the object.
    public func updateObject<SelectionSet: MutableRootSelectionSet>(
      ofType type: SelectionSet.Type,
      withKey key: CacheKey,
      variables: GraphQLOperation.Variables? = nil,
      _ body: (inout SelectionSet) throws -> Void
    ) async throws {
      let dataDict = try await readObject(
        ofType: type,
        withKey: key,
        variables: variables,
        accumulator: DataDictMapper(
          handleMissingValues: .allowForOptionalFields
        )
      )
      var object = SelectionSet(_dataDict: dataDict)

      try body(&object)
      try await write(selectionSet: object, withKey: key, variables: variables)
    }
    
    /// Writes the data for a `LocalCacheMutation` to the transaction's underlying cache.
    ///
    /// - Parameters:
    ///   - data: A reponse model for the cache mutation containing the data to write to the cache.
    ///   - cacheMutation: The `LocalCacheMutation` to write the `data` to the cache for.
    public func write<CacheMutation: LocalCacheMutation>(
      data: CacheMutation.Data,
      for cacheMutation: CacheMutation
    ) async throws {
      try await write(
        selectionSet: data,
        withKey: CacheReference.rootCacheReference(for: CacheMutation.operationType).key,
        variables: cacheMutation.__variables
      )
    }
    
    /// Writes the data for a `GraphQLOperation` to the transaction's underlying cache.
    ///
    /// - Parameters:
    ///   - data: An instance of the operation's reponse model containing the data to write to the cache.
    ///   - operation: The `GraphQLOperation` to write the `data` to the cache for.
    public func write<Operation: GraphQLOperation>(
      data: Operation.Data,
      for operation: Operation
    ) async throws {
      try await write(
        selectionSet: data,
        withKey: CacheReference.rootCacheReference(for: Operation.operationType).key,
        variables: operation.__variables
      )
    }
    
    /// Writes the data for an object to the transaction's underlying cache.
    ///
    /// - Parameters:
    ///   - selectionSet: The `RootSelectionSet` model containing the data to write to the cache.
    ///   - key: The ``CacheKey`` of the object to write to the cache. If an object with this key already exists, the
    ///   `selectionSet`'s data will be merged into the existing object.
    ///   - variables: Any operation variables necessary to resolve selected field's on the object. Defaults to `nil`.
    public func write<SelectionSet: RootSelectionSet>(
      selectionSet: SelectionSet,
      withKey key: CacheKey,
      variables: GraphQLOperation.Variables? = nil
    ) async throws {
      let normalizer = ResultNormalizerFactory.selectionSetDataNormalizer()

      let executor = GraphQLExecutor(executionSource: SelectionSetModelExecutionSource())

      let records = try await executor.execute(
        selectionSet: SelectionSet.self,
        on: selectionSet.__data,
        withRootCacheReference: CacheReference(key),
        variables: variables,
        accumulator: normalizer
      )

      let changedKeys = try await self.cache.merge(records: records)

      // Invalidate only the keys whose underlying data just changed.
      // Reads earlier in the transaction for *other* keys keep their
      // warm loader state and won't re-batch on the next ask. The
      // pre-3.0 loader used a blanket clear here; the per-field
      // projection loader can be more surgical because its state map
      // is keyed by cacheKey.
      projectionLoader.invalidate(keys: records.keys)

      if let didChangeKeysFunc = self.updateChangedKeysFunc {
        didChangeKeysFunc(changedKeys)
      }
    }

    /// Removes the object for the specified cache key from the transaction's underlying cache.
    ///
    /// This function does not support cascading deletion or removal of only certain fields. Does nothing if an object
    /// does not exist for the given key.
    ///
    /// - Parameters:
    ///   - key: The cache key of the object to remove from the cache.
    public func removeObject(for key: CacheKey) async throws {
      try await self.cache.removeRecord(for: key)
      // Invalidate the loader's state for this key so a subsequent
      // read in the same transaction surfaces `.absent` instead of
      // a stale `.loaded(record, …)` left behind by a prior read.
      projectionLoader.invalidate(keys: [key])
    }

    /// Removes records with keys that match the specified pattern.
    ///
    /// This method will only remove whole records, it does not perform cascading deletes. This means only the
    /// records with matched keys will be removed, but not any references to them.
    ///
    /// Key matching is case-insensitive.
    ///
    /// - Note: If you attempt to pass a cache path for a single field, this method will do nothing
    /// since it won't be able to locate a record to remove based on that path.
    ///
    /// - Warning: This method can be very slow depending on the number of records in the cache.
    /// It is recommended that this method be called in a background queue.
    ///
    /// - Parameters:
    ///   - pattern: The pattern that will be applied to find matching keys.
    public func removeObjects(matching pattern: CacheKey) async throws {
      try await self.cache.removeRecords(matching: pattern)
      projectionLoader.invalidate(matching: pattern)
    }

  }

  // MARK: - Deprecations

  /// Clears the instance of the cache.
  ///
  /// - Parameters:
  ///   - callbackQueue: The queue to call the completion block on. Defaults to `DispatchQueue.main`.
  ///   - completion: [optional] A completion block to be called after records are merged into the cache.
  @available(*, deprecated, renamed: "clearCache()")
  nonisolated public func clearCache(
    callbackQueue: DispatchQueue = .main,
    completion: (@Sendable (Result<Void, any Swift.Error>) -> Void)? = nil
  ) {
    performInTask(
      {
        try await self.clearCache()
      },
      callbackQueue: callbackQueue,
      completion: completion
    )
  }

  /// Merges a `RecordSet` into the normalized cache.
  /// - Parameters:
  ///   - records: The records to be merged into the cache.
  ///   - identifier: [optional] A unique identifier for the request that kicked off this change,
  ///                 to assist in de-duping cache hits for watchers.
  ///   - callbackQueue: The queue to call the completion block on.
  ///                    Defaults to `DispatchQueue.main`.
  ///   - completion: [optional] A completion block to call after records are merged into the cache.
  @available(*, deprecated, renamed: "publish(records:)")
  public func publish(
    records: RecordSet,
    identifier: UUID? = nil,
    callbackQueue: DispatchQueue = .main,
    completion: (@Sendable (Result<Void, any Swift.Error>) -> Void)? = nil
  ) {
    performInTask(
      {
        try await self.publish(records: records)
      },
      callbackQueue: callbackQueue,
      completion: completion
    )
  }

  /// Performs an operation within a read transaction
  ///
  /// - Parameters:
  ///   - body: The body of the operation to perform.
  ///   - callbackQueue: [optional] The callback queue to use to perform the completion block on.
  ///                    Will perform on the current queue if not provided. Defaults to nil.
  ///   - completion: [optional] The completion block to perform when the transaction completes.
  ///                 Defaults to nil.
  @available(*, deprecated, renamed: "withinReadTransaction(_:)")
  public func withinReadTransaction<T: Sendable>(
    _ body: @escaping @Sendable (ReadTransaction) async throws -> T,
    callbackQueue: DispatchQueue? = nil,
    completion: (@Sendable (Result<T, any Swift.Error>) -> Void)? = nil
  ) {
    performInTask(
      {
        try await self.withinReadTransaction(body)
      },
      callbackQueue: callbackQueue,
      completion: completion
    )
  }

  /// Performs an operation within a read-write transaction
  ///
  /// - Parameters:
  ///   - body: The body of the operation to perform
  ///   - callbackQueue: [optional] a callback queue to perform the action on.
  ///                    Will perform on the current queue if not provided. Defaults to nil.
  ///   - completion: [optional] a completion block to perform when the transaction completes.
  ///                 Defaults to nil.
  @available(*, deprecated, renamed: "withinReadWriteTransaction(_:)")
  public func withinReadWriteTransaction<T: Sendable>(
    _ body: @escaping @Sendable (ReadWriteTransaction) async throws -> T,
    callbackQueue: DispatchQueue? = nil,
    completion: (@Sendable (Result<T, any Swift.Error>) -> Void)? = nil
  ) {
    performInTask(
      {
        try await self.withinReadWriteTransaction(body)
      },
      callbackQueue: callbackQueue,
      completion: completion
    )
  }

  /// Loads the results for the given query from the cache.
  ///
  /// - Parameters:
  ///   - query: The query to load results for
  ///   - resultHandler: The completion handler to execute on success or error
  @available(*, deprecated, renamed: "load(_:)")
  public func load<Operation: GraphQLOperation>(
    _ operation: Operation,
    callbackQueue: DispatchQueue? = nil,
    resultHandler: @escaping GraphQLResultHandler<Operation>
  ) {
    performInTask(
      {
        guard let response = try await self.load(operation) else {
          throw JSONDecodingError.missingValue
        }
        return response
      },
      callbackQueue: callbackQueue,
      completion: resultHandler
    )
  }

  @available(*, deprecated)
  private func performInTask<T: Sendable>(
    _ body: @escaping @Sendable () async throws -> T,
    callbackQueue: DispatchQueue?,
    completion: (@Sendable (Result<T, any Swift.Error>) -> Void)?
  ) {
    Task {
      let result: Result<T, any Swift.Error>

      do {
        let value = try await body()
        result = .success(value)
      } catch {
        result = .failure(error)
      }

      DispatchQueue.returnResultAsyncIfNeeded(
        on: callbackQueue,
        action: completion,
        result: result
      )
    }
  }
}

@available(*, unavailable)
extension ApolloStore.ReadTransaction: Sendable { }
