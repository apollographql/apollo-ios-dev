import ApolloAPI

/// A request to read a set of fields from one record in the
/// normalized cache.
///
/// `RecordProjection` is the value-type expression of ADR 0007's
/// selection-set-aware cache reads: the executor builds one projection
/// per record by traversing the operation's selection sets, and the
/// cache fulfills them in one batched read, returning only the
/// requested fields instead of whole records.
///
/// The projection deliberately carries no type or shape metadata.
/// Storage backends return the whole stored value for each requested
/// field — the row-per-element SQLite schema (ADR 0006) infers
/// scalar-vs-list shape from the stored rows' `position` values at
/// read time, and the in-memory cache returns the stored entries
/// as-is. If a stored shape disagrees with the shape the generated
/// models declare (a non-backwards-compatible schema change shipped
/// without clearing the cache), the mismatch surfaces to the caller as
/// a `JSONDecodingError.wrongType` execution error — the same behavior
/// as Apollo iOS 2.x — rather than being masked by the read layer.
///
/// # Duplicate cache keys
///
/// `RecordProjection` is a transfer type, not an accumulation type:
/// two projections with the same `cacheKey` but different `fieldNames`
/// are distinct values (`Hashable` covers both properties), and APIs
/// that accept `[RecordProjection]` treat repeated cache keys as a
/// request for the *union* of their field names. Code that accumulates
/// projection state across call sites should use a
/// `[CacheKey: Set<String>]` dictionary and convert at the API
/// boundary.
///
/// # See Also
///
/// - ``CacheDependentKey`` — the watcher-side sibling. A dependent key
///   names a single `(cacheKey, fieldName)` pair a *result depends
///   on*; a projection names the field set a *read requests* for one
///   record. They are separate types because their identities evolve
///   differently: a projection may later gain request-only metadata
///   (e.g. a type condition for SQL-level inline-fragment filtering)
///   that must never participate in dependency matching.
/// - [ADR 0007 — Selection-set-aware cache reads](../Design/adr/0007-selection-aware-cache-reads.md)
/// - [ADR 0006 — List storage strategy](../Design/adr/0006-list-storage-strategy.md)
@_spi(Execution)
public struct RecordProjection: Hashable, Sendable {

  /// The cache key of the record whose fields are being read.
  public let cacheKey: CacheKey

  /// The names of the requested fields on that record. Matches the
  /// storage-layer field names verbatim; aliasing is applied upstream
  /// of the projection by the executor (the projection carries
  /// storage field names, not response keys).
  public let fieldNames: Set<String>

  public init(cacheKey: CacheKey, fieldNames: Set<String>) {
    self.cacheKey = cacheKey
    self.fieldNames = fieldNames
  }
}
