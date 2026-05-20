@_spi(Internal) import ApolloAPI

/// A cache key for a record.
public typealias CacheKey = String

/// A cache record.
public struct Record: Sendable, Hashable {
  public let key: CacheKey

  /// A field value carried by a record. Any value that is both `Hashable`
  /// (for record-set deduplication) and `Sendable` (for cross-actor cache
  /// traversal).
  public typealias Value = any Hashable & Sendable

  /// The map of field name to cached field. Each `CachedField` pairs the
  /// stored value with the timestamp at which it was last written.
  public typealias Fields = [CacheKey: CachedField]

  public internal(set) var fields: Fields

  /// Construct a record from a fully-formed field dictionary. Use this
  /// initializer when the caller has explicit `writtenAt` timestamps for
  /// each field — e.g. when deserializing from storage.
  public init(key: CacheKey, fields: Fields = [:]) {
    self.key = key
    self.fields = fields
  }

  /// Convenience initializer for callers that have raw field values and
  /// no per-field timestamps. Each value is wrapped in a `CachedField`
  /// stamped with the supplied `writtenAt` (default `0`).
  public init(key: CacheKey, _ values: [CacheKey: Value], writtenAt: Int64 = 0) {
    self.key = key
    self.fields = values.mapValues { CachedField(value: $0, writtenAt: writtenAt) }
  }

  /// Value-only access to a field. The setter wraps the new value in a
  /// `CachedField` with `writtenAt = 0`; use `fields` directly (within
  /// the module) when an explicit timestamp must be preserved.
  public subscript(key: CacheKey) -> Value? {
    get {
      return fields[key]?.value
    }
    set {
      if let newValue {
        fields[key] = CachedField(value: newValue, writtenAt: 0)
      } else {
        fields[key] = nil
      }
    }
  }

  /// Metadata-aware accessor for callers that need the field's
  /// `writtenAt` timestamp alongside its value.
  public func cachedField(for key: CacheKey) -> CachedField? {
    fields[key]
  }

}

extension Record: CustomStringConvertible {
  public var description: String {
    return "#\(key) -> \(fields)"
  }
}
