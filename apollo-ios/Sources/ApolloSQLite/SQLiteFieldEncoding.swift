import Foundation
@_spi(Execution) import Apollo

/// Encodes a single `Record` field value (or a single list element)
/// into the typed-column slot of the row-per-element records-table
/// layout, and reconstructs the value back from a fetched row.
///
/// The encoder operates per VALUE, not per array. Lists are not
/// encoded into a single column — each list element is stored as its
/// own row at `position = 0..N-1` and the database layer iterates
/// element-by-element, calling this encoder once per element. This
/// file therefore never sees `[Record.Value]` inputs at the top
/// level; arrays are flattened into multiple rows at a higher layer
/// and the encoder rejects them defensively.
///
/// Column mapping for a single value:
///
///   `Bool` (incl. `NSNumber`-boxed bool) → `bool_value` (stored as `0` / `1`)
///   `Int` / `Int64` (incl. integer `NSNumber`)        → `int_value`             (INTEGER)
///   `Double` (incl. floating-point `NSNumber`)        → `float_value`           (REAL)
///   `String`                                          → `string_value`
///   `CacheReference`                                  → `child_key_value`       (stores `.key`)
///   `NSNull` (the GraphQL null marker)                → `custom_scalar_value`   (`"null"`)
///   `[String: Record.Value]` and other JSON shapes    → `custom_scalar_value`   (JSON)
///
/// Exactly one value column is non-null on a well-formed row.
///
/// **Type-identity on round-trip.** SQLite `INTEGER` is 64-bit; the
/// decoder returns `Int` (which is 64-bit on every Apple deployment
/// target this SDK supports). A field originally written as `Int64`
/// reads back as `Int` — values are preserved exactly, but the Swift
/// type identity does change. Callers comparing via `AnyHashable`
/// should account for this.
internal enum SQLiteFieldEncoding {

  /// A `Record.Value` already classified into the column slot it
  /// occupies on a row. The case payload carries the typed-Swift
  /// representation of the value as it will be bound to the
  /// statement, and the case tag identifies the destination column
  /// (`bool_value`, `int_value`, `float_value`, `string_value`,
  /// `child_key_value`, or `custom_scalar_value`).
  internal enum TypedValue: Equatable {
    case bool(Bool)
    case int(Int64)
    case real(Double)
    case string(String)
    case childKey(String)
    case customScalar(String)
  }

  /// Classifies a single value into its destination column slot.
  ///
  /// Numeric values (whether native Swift `Int` / `Double` or
  /// `NSNumber`-bridged from JSON) all reach the `as NSNumber` case
  /// first via Foundation's implicit bridging. `CFGetTypeID` then
  /// distinguishes booleans (`CFBooleanGetTypeID`) from numeric kinds,
  /// keeping `NSNumber(value: 1)` in `int_value` and
  /// `NSNumber(value: true)` in `bool_value` — they would otherwise
  /// both satisfy `as Bool`.
  static func encode(_ value: Record.Value) throws -> TypedValue {
    switch value {
    case let n as NSNumber:
      if CFGetTypeID(n) == CFBooleanGetTypeID() {
        return .bool(n.boolValue)
      }
      switch CFNumberGetType(n) {
      case .sInt8Type, .sInt16Type, .sInt32Type, .sInt64Type,
           .charType, .shortType, .intType, .longType, .longLongType,
           .nsIntegerType, .cfIndexType:
        return .int(n.int64Value)
      default:
        return .real(n.doubleValue)
      }
    case let v as String:
      return .string(v)
    case let ref as CacheReference:
      return .childKey(ref.key)
    case is [Record.Value]:
      // List-typed fields are exploded into multiple rows at the
      // database layer; the per-value encoder must not be called for
      // them. Throwing here surfaces a programming error early
      // instead of silently producing a malformed `custom_scalar`.
      throw SQLiteFieldEncodingError.arrayAtValueLevel
    default:
      // `JSONSerialization` raises `NSInvalidArgumentException` (an
      // ObjC exception, not a Swift error) when passed a non-
      // Foundation type, which would bypass `do/catch` and abort the
      // process. Wrapping in a single-element array satisfies
      // `isValidJSONObject`'s "must be array or dict at the top
      // level" requirement so scalar JSON-compatibility is
      // validated.
      guard JSONSerialization.isValidJSONObject([value]) else {
        throw SQLiteFieldEncodingError.unsupportedValueType(String(describing: type(of: value)))
      }
      return .customScalar(try Self.encodeJSON(value))
    }
  }

  /// Reconstructs a value from a fetched row. Exactly one of the
  /// optional column values should be non-nil; populated-column
  /// priority matches the encoding order above so that wrong-multi-
  /// column rows fail fast on the first encountered slot.
  static func decode(
    boolValue: Int64?,
    intValue: Int64?,
    floatValue: Double?,
    stringValue: String?,
    childKeyValue: String?,
    customScalarValue: String?
  ) throws -> Record.Value {
    if let bool = boolValue {
      return bool != 0
    }
    if let int = intValue {
      return Int(int)
    }
    if let real = floatValue {
      return real
    }
    if let str = stringValue {
      return str
    }
    if let childKey = childKeyValue {
      return CacheReference(childKey)
    }
    if let customText = customScalarValue {
      let parsed = try Self.decodeJSON(customText)
      guard let value = Self.recordValueFromJSON(parsed) else {
        throw SQLiteFieldEncodingError.malformedCustomScalar
      }
      return value
    }
    throw SQLiteFieldEncodingError.noValueColumnPopulated
  }

  // MARK: - JSON helpers

  /// Stable wrapper key matching the JSON-blob layout's representation
  /// for cache references nested inside dictionaries. Keeping the same
  /// key ensures dicts serialized by the legacy layer round-trip
  /// identically through this layer.
  private static let referenceWrapperKey = "$reference"

  /// `.sortedKeys` makes the on-disk TEXT representation deterministic
  /// — the same logical content always produces the same string
  /// regardless of dictionary iteration order. `.fragmentsAllowed`
  /// lets the custom-scalar fallback encode bare JSON fragments (e.g.
  /// `null` for `NSNull`).
  private static func encodeJSON(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys, .fragmentsAllowed]
    )
    guard let text = String(data: data, encoding: .utf8) else {
      throw SQLiteFieldEncodingError.invalidUTF8
    }
    return text
  }

  private static func decodeJSON(_ text: String) throws -> Any {
    guard let data = text.data(using: .utf8) else {
      throw SQLiteFieldEncodingError.invalidUTF8
    }
    return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
  }

  /// Narrows a `JSONSerialization` output (`NSNumber`/`NSString`/
  /// `NSArray`/`NSDictionary`/`NSNull` and their Swift bridges) into a
  /// concrete `Record.Value`. Returns `nil` only for shapes that don't
  /// map — in practice this means types `JSONSerialization` itself
  /// can't produce.
  ///
  /// `NSNull` is the documented GraphQL null marker and is preserved
  /// as-is so it survives a write/read round-trip.
  ///
  /// A `$reference` wrapper is recognized only when the dict has
  /// **exactly one key** — a dict that happens to use that key
  /// alongside other keys (a legitimate custom scalar collision)
  /// falls through to the generic-dict branch instead, so its full
  /// payload survives.
  ///
  /// `Bool` is checked before `Int` because `NSNumber` boolean
  /// bridging satisfies `as? Int`; ordering keeps booleans as booleans.
  private static func recordValueFromJSON(_ json: Any) -> Record.Value? {
    if json is NSNull {
      return NSNull()
    }
    if let dict = json as? [String: Any] {
      if dict.count == 1, let key = dict[referenceWrapperKey] as? String {
        return CacheReference(key)
      }
      let narrowed = dict.mapValues { Self.deserializeJSONValue($0) }
      return narrowed as Record.Value
    }
    if let array = json as? [Any] {
      return array.map { Self.deserializeJSONValue($0) } as Record.Value
    }
    if let v = json as? Bool { return v }
    if let v = json as? Int { return v }
    if let v = json as? Double { return v }
    if let v = json as? String { return v }
    return nil
  }

  private static func deserializeJSONValue(_ json: Any) -> Record.Value {
    Self.recordValueFromJSON(json) ?? String(describing: json)
  }
}

internal enum SQLiteFieldEncodingError: Error, CustomStringConvertible {
  case noValueColumnPopulated
  case malformedCustomScalar
  case invalidUTF8
  case unsupportedValueType(String)
  case arrayAtValueLevel

  var description: String {
    switch self {
    case .noValueColumnPopulated:
      return "Row has no populated value column"
    case .malformedCustomScalar:
      return "custom_scalar_value did not decode to a Hashable & Sendable JSON value"
    case .invalidUTF8:
      return "Failed to convert JSON between Data and String"
    case .unsupportedValueType(let typeName):
      return "Field value of type \(typeName) cannot be JSON-encoded"
    case .arrayAtValueLevel:
      return "Array values are list-typed fields and must be exploded into multiple rows; the per-value encoder should not be called for them"
    }
  }
}
