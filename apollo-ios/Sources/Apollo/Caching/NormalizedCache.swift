public protocol NormalizedCache: AnyObject, ReadOnlyNormalizedCache {

  /// Loads records corresponding to the given keys.
  ///
  /// - Parameters:
  ///   - key: The cache keys to load data for
  /// - Returns: A dictionary of cache keys to records containing the records that have been found.
  func loadRecords(forKeys keys: Set<CacheKey>) async throws -> [CacheKey: Record]

  /// Merges a set of records into the cache.
  ///
  /// - Parameters:
  ///   - records: The set of records to merge.
  /// - Returns: A set of ``CacheDependentKey``s identifying every
  ///   `(cacheKey, fieldName)` pair whose stored value changed. These
  ///   are the same dependency-tracking keys recorded by
  ///   `GraphQLDependencyTracker` and consumed by
  ///   ``ApolloStoreSubscriber/store(_:didChangeKeys:)`` /
  ///   ``GraphQLQueryWatcher`` for dirty-set computation.
  func merge(records: RecordSet) async throws -> Set<CacheDependentKey>

  /// Removes a record for the specified key. This method will only
  /// remove whole records, not individual fields.
  ///
  /// If you attempt to pass a cache key for a  single field, this
  /// method will do nothing since it won't be able to locate a
  /// record to remove based on that key.
  ///
  /// This method does not support cascading delete - it will only
  /// remove the record for the specified key, and not any references to it or from it.
  ///
  /// - Parameters:
  ///   - key: The cache key to remove the record for
  func removeRecord(for key: CacheKey) async throws

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
  func removeRecords(matching pattern: CacheKey) async throws

  /// Clears all records.
  func clear() async throws
}

/// A read-only view of a ``NormalizedCache`` for use within a ``ReadTransaction``.
public protocol ReadOnlyNormalizedCache: AnyObject {

  /// Loads records corresponding to the given keys.
  ///
  /// - Parameters:
  ///   - key: The cache keys to load data for
  /// - Returns: A dictionary of cache keys to records containing the records that have been found.
  func loadRecords(forKeys keys: Set<CacheKey>) async throws -> [CacheKey: Record]

  /// Loads the field values described by `projections`, returning each
  /// requested record's fields as a partial `Record` containing only the
  /// fields the caller asked for. Per ADR 0007 this is the projection-
  /// aware replacement for ``loadRecords(forKeys:)``; the executor
  /// (PR-009d) and `ApolloStore` (PR-009e) migrate to this method
  /// during sub-phase 1A.5, and PR-009g lands SQL-level column
  /// projection on the SQLite backend.
  ///
  /// - Parameters:
  ///   - projections: The set of fields to read. Each
  ///     ``FieldProjection`` identifies one `(cacheKey, fieldName)`
  ///     pair plus its storage shape. Multiple projections may share
  ///     a `cacheKey` to request different fields on the same record.
  ///     Duplicate projections are tolerated; their results coalesce.
  ///
  ///     **Precondition:** the caller must not supply two projections
  ///     with the same `(cacheKey, fieldName)` but a different
  ///     `columnShape` or `cardinality`. The cache backend stores each
  ///     field under a single column-shape (determined at write time
  ///     by the field's GraphQL type) and cannot answer two
  ///     incompatible projections for the same row. ``FieldProjection``'s
  ///     `Hashable` conformance hashes by the full tuple, so the
  ///     pending set in `ProjectionLoader` won't dedupe such conflicts
  ///     — they will reach the backend as two separate projections
  ///     that ask for inconsistent answers. The
  ///     `FieldProjectionCollector` path derives `columnShape` /
  ///     `cardinality` from `Selection.Field.OutputType`, which GraphQL
  ///     validation guarantees is identical for every selection of the
  ///     same `(cacheKey, fieldName)`, so this can only happen when
  ///     callers hand-construct projections via the direct
  ///     ``FieldProjection/init(cacheKey:fieldName:columnShape:cardinality:)``
  ///     initializer. PR-009g's SQL projection path enforces the
  ///     precondition implicitly by picking one storage column per
  ///     field.
  ///
  /// - Returns: A dictionary of cache keys to partial records. A cache
  ///   key appears in the result if and only if the *record* exists in
  ///   the cache — independent of whether the specific projected
  ///   fields are present. A record that exists but holds none of the
  ///   requested fields is returned as a `Record` with empty `fields`.
  ///   The distinction matters for the executor: `record exists,
  ///   field missing` surfaces a per-field `missingValue` error with
  ///   response-path context, whereas `record absent` is handled as
  ///   a record-level lookup miss by the caller. Returned
  ///   `Record.fields` is otherwise restricted to the requested field
  ///   names that were present; unrequested fields on the same record
  ///   are excluded.
  @_spi(Execution)
  func loadFields(_ projections: [FieldProjection]) async throws -> [CacheKey: Record]

}

@_spi(Execution)
extension ReadOnlyNormalizedCache {

  /// Default implementation. Delegates to ``loadRecords(forKeys:)`` to
  /// fetch the full records for the projections' cache keys, then
  /// filters each record's `fields` to the requested field names.
  ///
  /// This is the "fallback" path the ADR 0007 table references for the
  /// SQLite backend during the 1A.5 transition: until PR-009g lands
  /// SQL-level column projection, every backend that conforms to
  /// ``ReadOnlyNormalizedCache`` automatically inherits a correct (if
  /// unoptimized) `loadFields` implementation by reading whole records
  /// and filtering in Swift. Custom cache implementors get the same
  /// behavior without a forced API migration; they may override the
  /// method with a projection-aware path when they're ready.
  ///
  /// **Performance:** this default is `O(records.count * filteredFields.count)`
  /// with one new dict allocation per surfaced record (the `record.fields.filter`
  /// closure produces a fresh `[CacheKey: CachedField]`). That's fine for the
  /// in-memory backend, which is already paying the dict-walk cost. Backends
  /// where the inherited behavior would surface as a regression versus a
  /// hand-rolled `loadRecords`-backed path (e.g. when a partial-row read is
  /// significantly cheaper than a full-row read) should override.
  public func loadFields(_ projections: [FieldProjection]) async throws -> [CacheKey: Record] {
    guard !projections.isEmpty else { return [:] }

    let projectionsByKey = Dictionary(grouping: projections, by: \.cacheKey)
    let keys = Set(projectionsByKey.keys)
    let records = try await loadRecords(forKeys: keys)

    var result: [CacheKey: Record] = [:]
    for (key, fieldProjections) in projectionsByKey {
      guard let record = records[key] else { continue }
      let requestedFieldNames = Set(fieldProjections.map(\.fieldName))
      let filteredFields = record.fields.filter { requestedFieldNames.contains($0.key) }
      // Keep the key in the result even when `filteredFields` is empty
      // (record exists, but the requested fields don't). The caller
      // distinguishes "record absent" (key absent from result) from
      // "record present but field missing" (key present with empty
      // fields); the executor needs that distinction to surface per-
      // field `missingValue` errors with response-path context.
      result[key] = Record(key: key, fields: filteredFields)
    }
    return result
  }
}
