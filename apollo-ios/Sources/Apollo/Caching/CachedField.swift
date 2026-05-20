@_spi(Internal) import ApolloAPI
import Foundation

/// A single cached field's value alongside its write metadata.
///
/// Each field in a `Record` carries its own `writtenAt` timestamp so TTL
/// evaluation under `@cacheControl(maxAge:)` is local to the field rather
/// than stored in a parallel side-channel.
public struct CachedField: Sendable, Hashable {

  /// The value stored at this field. Any value that is both `Hashable`
  /// (for record-set deduplication) and `Sendable` (for cross-actor cache
  /// traversal).
  public typealias Value = any Hashable & Sendable

  /// The field's value.
  public let value: Value

  /// Epoch seconds at which this field was last written to the cache.
  /// TTL evaluation reads `writtenAt + maxAge < now` to decide if the
  /// field is stale.
  public let writtenAt: Int64

  public init(value: Value, writtenAt: Int64) {
    self.value = value
    self.writtenAt = writtenAt
  }

  /// Convenience: accept a `Date` and truncate to epoch seconds.
  /// `Date.timeIntervalSince1970` is a fractional `Double`; the sub-second
  /// portion is dropped because `writtenAt` is second-precision.
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
