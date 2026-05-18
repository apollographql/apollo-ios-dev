@_spi(Internal) import ApolloAPI
import Foundation

/// A single cached field's value alongside its write metadata.
///
/// In 3.0, `Record.fields` changes from `[CacheKey: Value]` to
/// `[CacheKey: CachedField]` (see [ADR 0002](../../Design/adr/0002-record-abstraction.md)).
/// Each field carries its own `writtenAt` timestamp so TTL evaluation under
/// `@cacheControl(maxAge:)` is local to the field — no parallel metadata
/// side-channel is required.
///
/// PR-005 introduces the type with no consumers; PR-006 changes `Record.fields`
/// to use it. Phase 2 metadata (`lastAccessedAt` for LRU, parent references
/// for `@onDelete`, etc.) will land as additional stored properties on this
/// struct as those features ship.
public struct CachedField: Sendable, Hashable {

  /// The value stored at this field. Matches `Record.Value`'s constraint —
  /// any value that is both `Hashable` (for record-set deduplication) and
  /// `Sendable` (for cross-actor cache traversal).
  public typealias Value = any Hashable & Sendable

  /// The field's value.
  public let value: Value

  /// Epoch seconds at which this field was last written to the cache. TTL
  /// evaluation reads `writtenAt + maxAge < now` to decide if the field is
  /// stale (ADR 0003 §2).
  public let writtenAt: Int64

  public init(value: Value, writtenAt: Int64) {
    self.value = value
    self.writtenAt = writtenAt
  }

  /// Convenience: accept a `Date` and truncate to epoch seconds.
  /// `Date.timeIntervalSince1970` is a fractional `Double`; we drop the
  /// sub-second portion because TTL semantics in 3.0 are second-precision.
  public init(value: Value, writtenAt: Date) {
    self.init(value: value, writtenAt: Int64(writtenAt.timeIntervalSince1970))
  }

  public static func == (lhs: CachedField, rhs: CachedField) -> Bool {
    lhs.writtenAt == rhs.writtenAt &&
      AnySendableHashable.equatableCheck(lhs.value, rhs.value)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(writtenAt)
    hasher.combine(AnyHashable(value))
  }
}

extension CachedField: CustomStringConvertible {
  public var description: String {
    "(\(value) @ \(writtenAt))"
  }
}
