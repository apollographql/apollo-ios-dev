import ApolloAPI

/// A request to read one field's value(s) from one record in the
/// normalized cache.
///
/// `FieldProjection` is the value-type expression of ADR 0007's
/// selection-set-aware cache reads: the executor builds projections
/// upfront by traversing the operation's selection sets, and the
/// cache fulfills them in one batched read, returning only the
/// requested `(cacheKey, fieldName)` pairs instead of whole records.
///
/// The projection deliberately carries no type or shape metadata.
/// Storage backends return the whole stored value for the pair — the
/// row-per-element SQLite schema (ADR 0006) infers scalar-vs-list
/// shape from the stored rows' `position` values at read time, and
/// the in-memory cache returns the stored entry as-is. If the stored
/// shape disagrees with the shape the generated models declare (a
/// non-backwards-compatible schema change shipped without clearing
/// the cache), the mismatch surfaces to the caller as a
/// `JSONDecodingError.wrongType` execution error — the same behavior
/// as Apollo iOS 2.x — rather than being masked by the read layer.
///
/// # See Also
///
/// - [ADR 0007 — Selection-set-aware cache reads](../Design/adr/0007-selection-aware-cache-reads.md)
/// - [ADR 0006 — List storage strategy](../Design/adr/0006-list-storage-strategy.md)
@_spi(Execution)
public struct FieldProjection: Hashable, Sendable {

  /// The cache key of the record whose field is being read.
  public let cacheKey: CacheKey

  /// The name of the field on that record. Matches the storage-
  /// layer `field_name` column verbatim; aliasing is applied
  /// upstream of the projection by the executor (the projection
  /// carries the storage field name, not the response key).
  public let fieldName: String

  public init(cacheKey: CacheKey, fieldName: String) {
    self.cacheKey = cacheKey
    self.fieldName = fieldName
  }
}
