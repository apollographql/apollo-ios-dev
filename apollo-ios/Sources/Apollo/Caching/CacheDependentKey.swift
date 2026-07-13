/// Identifies one `(cacheKey, fieldName)` pair that a watcher's
/// query depends on, or that a cache merge surfaced as changed.
///
/// The dependency tracker (`GraphQLDependencyTracker`) emits a
/// `CacheDependentKey` for every field a watcher's last read
/// touched; the cache's merge path (`RecordSet.merge`) emits one
/// for every field whose stored value changed. `GraphQLQueryWatcher`
/// computes set intersection between the two: if any changed field
/// matches one the query depended on, the watcher re-runs the query.
///
/// `cacheKey` is the storage-layer record key (matching `Record.key`);
/// `fieldName` is the storage-layer field name (matching the
/// `Record.fields` dictionary key, including any argument-derived
/// suffix). For embedded sub-objects — those without a separate
/// `@typePolicy` cache key — the writer synthesizes a record key
/// from the response path (e.g. `"QUERY_ROOT.animal"`), and the
/// dependency tracker records the corresponding pair as
/// `(cacheKey: "QUERY_ROOT.animal", fieldName: "genus")`. Both
/// the tracker and `RecordSet.merge` produce keys that agree at
/// this record boundary, so set intersection is exact.
///
/// # See Also
///
/// - [ADR 0007 — Selection-set-aware cache reads](../Design/adr/0007-selection-aware-cache-reads.md)
/// - ``FieldProjection`` — the read-request sibling. Both types
///   carry the same `(cacheKey, fieldName)` pair; this one names a
///   field a result *depends on* (watcher dirty-set matching), while
///   `FieldProjection` names a field a read *requests*.
public struct CacheDependentKey: Hashable, Sendable {

  /// The cache key of the record carrying the field.
  public let cacheKey: CacheKey

  /// The field's name on the parent record. Matches the
  /// storage-layer field name verbatim (`Record.fields` dictionary
  /// key).
  public let fieldName: String

  public init(cacheKey: CacheKey, fieldName: String) {
    self.cacheKey = cacheKey
    self.fieldName = fieldName
  }
}

extension CacheDependentKey: CustomStringConvertible {
  /// Format matches the legacy `"\(cacheKey).\(fieldName)"` joined
  /// string used before PR-009f. Useful for debugging and for tests
  /// that previously compared joined-string sets.
  public var description: String { "\(cacheKey).\(fieldName)" }
}
