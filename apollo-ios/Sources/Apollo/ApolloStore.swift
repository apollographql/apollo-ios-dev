import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// The `ApolloStoreSubscriber` provides a means to observe changes to items in the ApolloStore.
/// This protocol is available for advanced use cases only. Most users will prefer using `ApolloClient.watch(query:)`.
public protocol ApolloStoreSubscriber: AnyObject {
  
  /// A callback that can be received by subscribers when keys are changed within the database
  ///
  /// - Parameters:
  ///   - store: The store which made the changes
  ///   - changedKeys: The list of changed keys
  ///   - contextIdentifier: [optional] A unique identifier for the request that kicked off this change, to assist in de-duping cache hits for watchers.
  /// @deprecated
  func store(_ store: ApolloStore,
             didChangeKeys changedKeys: Set<CacheKey>,
             contextIdentifier: UUID?)

  /// A callback that can be received by subscribers for a particular activity case described in `ApolloStore.Activity`
  ///
  /// - Parameters:
  ///   - store: The store which made the changes
  ///   - activity: The activity that triggered this callback
  ///   - contextIdentifier: [optional] A unique identifier for the request that kicked off this change, to assist in de-duping cache hits for watchers.
  func store(_ store: ApolloStore,
            activity: ApolloStore.Activity,
            contextIdentifier: UUID?) throws
}

/// The `ApolloStore` class acts as a local cache for normalized GraphQL results.
public class ApolloStore {
  public enum Activity: Hashable {
    /// Peceived by subscribers BEFORE an action is executed, where the action can be prevented if an error is thrown.
    /// - Parameters:
    ///   - perform: The type of action being performed, e.g., load, merge, remove
    case will(perform: Action)

    /// Received by subscribers AFTER an action has been executed.
    /// - Parameters:
    ///   - perform: The type of action that was performed, e.g., load, merge, remove
    ///   - result: The result of the action, including any relevant data or changed keys
    case did(perform: Action, outcome: Action.Outcome)

    // Enum to define the types of actions performed in the store
    public enum Action: Hashable {
      /// Received by subscribers for records to be loaded from the database for the provided keys.
      /// - Parameters:
      ///   - forKeys: The keys that were provided to the store to load records for
      case loadRecords(forKeys: Set<Apollo.CacheKey>)
      /// Received by subscribers for records to be merged into the database.
      /// - Parameters:
      ///   - records: The records that will be merged into the store
      case merge(records: RecordSet)
      /// Received by subscribers for a record to be removed from the database.
      /// - Parameters:
      ///   - for: The key for of record that was removed
      case removeRecord(for: CacheKey)
      /// Received by subscribers for records matching the provided pattern to be removed from the database.
      /// - Parameters:
      ///   - matching: The pattern for whcih matching records were removed
      case removeRecords(matching: Apollo.CacheKey)
      /// Received by subscribers for when the database is cleared.
      case clear

      // Enum to represent the outcome of an action, which can be customized to include more data as needed
      public enum Outcome: Hashable {
        case success
        case records([Apollo.CacheKey: Apollo.Record])
        case changedKeys(Set<Apollo.CacheKey>)
      }
    }
  }

  private let cache: NormalizedCache
  private let queue: DispatchQueue

  internal var subscribers: [ApolloStoreSubscriber] = []

  /// Designated initializer
  /// - Parameters:
  ///   - cache: An instance of `normalizedCache` to use to cache results.
  ///            Defaults to an `InMemoryNormalizedCache`.
  public init(cache: NormalizedCache = InMemoryNormalizedCache()) {
    self.cache = cache
    self.queue = DispatchQueue(label: "com.apollographql.ApolloStore", attributes: .concurrent)
  }

  fileprivate func notify(_ activity: ApolloStore.Activity, identifier: UUID?) throws {
    for subscriber in self.subscribers {
      try subscriber.store(self, activity: activity, contextIdentifier: identifier)
      // TODO: Remove this after a round of deprecation
      if case .did(perform: .merge(records: _), outcome: .changedKeys(let changedKeys)) = activity {
        subscriber.store(self, didChangeKeys: changedKeys, contextIdentifier: identifier)
      }
    }
  }

  /// Clears the instance of the cache. Note that a cache can be shared across multiple `ApolloClient` objects, so clearing that underlying cache will clear it for all clients.
  ///
  /// - Parameters:
  ///   - callbackQueue: The queue to call the completion block on. Defaults to `DispatchQueue.main`.
  ///   - completion: [optional] A completion block to be called after records are merged into the cache.
  public func clearCache(callbackQueue: DispatchQueue = .main, completion: ((Result<Void, Swift.Error>) -> Void)? = nil) {
    queue.async(flags: .barrier) {
      let result = Result {
        try self.notify(.will(perform: .clear), identifier: nil)
        try self.cache.clear()
        try self.notify(.did(perform: .clear, outcome: .success), identifier: nil)
      }
      DispatchQueue.returnResultAsyncIfNeeded(
        on: callbackQueue,
        action: completion,
        result: result
      )
    }
  }

  /// Merges a `RecordSet` into the normalized cache.
  /// - Parameters:
  ///   - records: The records to be merged into the cache.
  ///   - identifier: [optional] A unique identifier for the request that kicked off this change,
  ///                 to assist in de-duping cache hits for watchers.
  ///   - callbackQueue: The queue to call the completion block on. Defaults to `DispatchQueue.main`.
  ///   - completion: [optional] A completion block to be called after records are merged into the cache.
  public func publish(records: RecordSet, identifier: UUID? = nil, callbackQueue: DispatchQueue = .main, completion: ((Result<Void, Swift.Error>) -> Void)? = nil) {
    queue.async(flags: .barrier) {
      do {
        try self.notify(.will(perform: .merge(records: records)), identifier: identifier)
        let changedKeys = try self.cache.merge(records: records)
        try self.notify(.did(perform: .merge(records: records), outcome: .changedKeys(changedKeys)), identifier: identifier)
        DispatchQueue.returnResultAsyncIfNeeded(
          on: callbackQueue,
          action: completion,
          result: .success(())
        )
      } catch {
        DispatchQueue.returnResultAsyncIfNeeded(
          on: callbackQueue,
          action: completion,
          result: .failure(error)
        )
      }
    }
  }

  /// Subscribes to notifications of ApolloStore content changes
  ///
  /// - Parameters:
  ///    - subscriber: A subscriber to receive content change notificatons. To avoid a retain cycle,
  ///                  ensure you call `unsubscribe` on this subscriber before it goes out of scope.
  public func subscribe(_ subscriber: ApolloStoreSubscriber) {
    queue.async(flags: .barrier) {
      self.subscribers.append(subscriber)
    }
  }

  /// Unsubscribes from notifications of ApolloStore content changes
  ///
  /// - Parameters:
  ///    - subscriber: A subscribe that has previously been added via `subscribe`. To avoid retain cycles,
  ///                  call `unsubscribe` on all active subscribers before they go out of scope.
  public func unsubscribe(_ subscriber: ApolloStoreSubscriber) {
    queue.async(flags: .barrier) {
      self.subscribers = self.subscribers.filter({ $0 !== subscriber })
    }
  }

  /// Performs an operation within a read transaction
  ///
  /// - Parameters:
  ///   - body: The body of the operation to perform.
  ///   - callbackQueue: [optional] The callback queue to use to perform the completion block on. Will perform on the current queue if not provided. Defaults to nil.
  ///   - completion: [optional] The completion block to perform when the read transaction completes. Defaults to nil.
  public func withinReadTransaction<T>(
    _ body: @escaping (ReadTransaction) throws -> T,
    callbackQueue: DispatchQueue? = nil,
    completion: ((Result<T, Swift.Error>) -> Void)? = nil
  ) {
    self.queue.async {
      do {
        let returnValue = try body(ReadTransaction(store: self))
        
        DispatchQueue.returnResultAsyncIfNeeded(
          on: callbackQueue,
          action: completion,
          result: .success(returnValue)
        )
      } catch {
        DispatchQueue.returnResultAsyncIfNeeded(
          on: callbackQueue,
          action: completion,
          result: .failure(error)
        )
      }
    }
  }
  
  /// Performs an operation within a read-write transaction
  ///
  /// - Parameters:
  ///   - body: The body of the operation to perform
  ///   - callbackQueue: [optional] a callback queue to perform the action on. Will perform on the current queue if not provided. Defaults to nil.
  ///   - completion: [optional] a completion block to fire when the read-write transaction completes. Defaults to nil.
  public func withinReadWriteTransaction<T>(
    _ body: @escaping (ReadWriteTransaction) throws -> T,
    callbackQueue: DispatchQueue? = nil,
    completion: ((Result<T, Swift.Error>) -> Void)? = nil
  ) {
    self.queue.async(flags: .barrier) {
      do {
        let returnValue = try body(ReadWriteTransaction(store: self))
        
        DispatchQueue.returnResultAsyncIfNeeded(
          on: callbackQueue,
          action: completion,
          result: .success(returnValue)
        )
      } catch {
        DispatchQueue.returnResultAsyncIfNeeded(
          on: callbackQueue,
          action: completion,
          result: .failure(error)
        )
      }
    }
  }

  /// Loads the results for the given query from the cache.
  ///
  /// - Parameters:
  ///   - query: The query to load results for
  ///   - resultHandler: The completion handler to execute on success or error
  public func load<Operation: GraphQLOperation>(
    _ operation: Operation,
    callbackQueue: DispatchQueue? = nil,
    resultHandler: @escaping GraphQLResultHandler<Operation.Data>
  ) {
    withinReadTransaction({ transaction in
      let (data, dependentKeys) = try transaction.readObject(
        ofType: Operation.Data.self,
        withKey: CacheReference.rootCacheReference(for: Operation.operationType).key,
        variables: operation.__variables,
        accumulator: zip(GraphQLSelectionSetMapper<Operation.Data>(),
                         GraphQLDependencyTracker())
      )
      
      return GraphQLResult(
        data: data,
        extensions: nil,
        errors: nil,
        source:.cache,
        dependentKeys: dependentKeys
      )
    }, callbackQueue: callbackQueue, completion: resultHandler)
  }

  public enum Error: Swift.Error {
    case notWithinReadTransaction
  }

  public class ReadTransaction {
    fileprivate weak var store: ApolloStore?
    fileprivate lazy var loader: DataLoader<CacheKey, Record> = DataLoader { [weak store] keys in
      guard let store else { return nil }
      try store.notify(.will(perform: .loadRecords(forKeys: keys)), identifier: nil)
      let records = try store.cache.loadRecords(forKeys: keys)
      try store.notify(.did(perform: .loadRecords(forKeys: keys), outcome: .records(records)), identifier: nil)
      return records
    }
    fileprivate lazy var executor = GraphQLExecutor(
      executionSource: CacheDataExecutionSource(transaction: self)
    ) 

    fileprivate init(store: ApolloStore) {
      self.store = store
    }

    public func read<Query: GraphQLQuery>(query: Query) throws -> Query.Data {
      return try readObject(
        ofType: Query.Data.self,
        withKey: CacheReference.rootCacheReference(for: Query.operationType).key,
        variables: query.__variables
      )
    }

    public func readObject<SelectionSet: RootSelectionSet>(
      ofType type: SelectionSet.Type,
      withKey key: CacheKey,
      variables: GraphQLOperation.Variables? = nil
    ) throws -> SelectionSet {
      return try self.readObject(
        ofType: type,
        withKey: key,
        variables: variables,
        accumulator: GraphQLSelectionSetMapper<SelectionSet>()
      )
    }

    func readObject<SelectionSet: RootSelectionSet, Accumulator: GraphQLResultAccumulator>(
      ofType type: SelectionSet.Type,
      withKey key: CacheKey,
      variables: GraphQLOperation.Variables? = nil,
      accumulator: Accumulator
    ) throws -> Accumulator.FinalResult {
      let object = try loadObject(forKey: key).get()

      return try executor.execute(
        selectionSet: type,
        on: object,
        withRootCacheReference: CacheReference(key),
        variables: variables,
        accumulator: accumulator
      )
    }
    
    final func loadObject(forKey key: CacheKey) -> PossiblyDeferred<Record> {
      self.loader[key].map { record in
        guard let record = record else { throw JSONDecodingError.missingValue }
        return record
      }
    }
  }

  public final class ReadWriteTransaction: ReadTransaction {

    override init(store: ApolloStore) {
      super.init(store: store)
    }

    public func update<CacheMutation: LocalCacheMutation>(
      _ cacheMutation: CacheMutation,
      _ body: (inout CacheMutation.Data) throws -> Void
    ) throws {
      try updateObject(
        ofType: CacheMutation.Data.self,
        withKey: CacheReference.rootCacheReference(for: CacheMutation.operationType).key,
        variables: cacheMutation.__variables,
        body
      )
    }

    public func updateObject<SelectionSet: MutableRootSelectionSet>(
      ofType type: SelectionSet.Type,
      withKey key: CacheKey,
      variables: GraphQLOperation.Variables? = nil,
      _ body: (inout SelectionSet) throws -> Void
    ) throws {
      var object = try readObject(
        ofType: type,
        withKey: key,
        variables: variables,
        accumulator: GraphQLSelectionSetMapper<SelectionSet>(
          handleMissingValues: .allowForOptionalFields
        )
      )

      try body(&object)
      try write(selectionSet: object, withKey: key, variables: variables)
    }

    public func write<CacheMutation: LocalCacheMutation>(
      data: CacheMutation.Data,
      for cacheMutation: CacheMutation
    ) throws {
      try write(selectionSet: data,
                withKey: CacheReference.rootCacheReference(for: CacheMutation.operationType).key,
                variables: cacheMutation.__variables)
    }

    public func write<Operation: GraphQLOperation>(
      data: Operation.Data,
      for operation: Operation
    ) throws {
      try write(selectionSet: data,
                withKey: CacheReference.rootCacheReference(for: Operation.operationType).key,
                variables: operation.__variables)
    }

    public func write<SelectionSet: RootSelectionSet>(
      selectionSet: SelectionSet,
      withKey key: CacheKey,
      variables: GraphQLOperation.Variables? = nil
    ) throws {
      guard let store else { return }
        
      let normalizer = ResultNormalizerFactory.selectionSetDataNormalizer()

      let executor = GraphQLExecutor(executionSource: SelectionSetModelExecutionSource())

      let records = try executor.execute(
        selectionSet: SelectionSet.self,
        on: selectionSet.__data,
        withRootCacheReference: CacheReference(key),
        variables: variables,
        accumulator: normalizer
      )

      try store.notify(.will(perform: .merge(records: records)), identifier: nil)
      let changedKeys = try store.cache.merge(records: records)

      // Remove cached records, so subsequent reads
      // within the same transaction will reload the updated value.
      loader.removeAll()

      try store.notify(.did(perform: .merge(records: records), outcome: .changedKeys(changedKeys)), identifier: nil)
    }
    
    /// Removes the object for the specified cache key. Does not cascade
    /// or allow removal of only certain fields. Does nothing if an object
    /// does not exist for the given key.
    ///
    /// - Parameters:
    ///   - key: The cache key to remove the object for
    public func removeObject(for key: CacheKey) throws {
      guard let store else { return }
      try store.notify(.will(perform: .removeRecord(for: key)), identifier: nil)
      try store.cache.removeRecord(for: key)
      try store.notify(.did(perform: .removeRecord(for: key), outcome: .success), identifier: nil)
    }

    /// Removes records with keys that match the specified pattern. This method will only
    /// remove whole records, it does not perform cascading deletes. This means only the
    /// records with matched keys will be removed, and not any references to them. Key
    /// matching is case-insensitive.
    ///
    /// If you attempt to pass a cache path for a single field, this method will do nothing
    /// since it won't be able to locate a record to remove based on that path.
    ///
    /// - Note: This method can be very slow depending on the number of records in the cache.
    /// It is recommended that this method be called in a background queue.
    ///
    /// - Parameters:
    ///   - pattern: The pattern that will be applied to find matching keys.
    public func removeObjects(matching pattern: CacheKey) throws {
      guard let store else { return }
      try store.notify(.will(perform: .removeRecords(matching: pattern)), identifier: nil)
      try store.cache.removeRecords(matching: pattern)
      try store.notify(.did(perform: .removeRecords(matching: pattern), outcome: .success), identifier: nil)
    }

  }
}
