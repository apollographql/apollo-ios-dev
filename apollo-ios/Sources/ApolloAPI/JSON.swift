/// Represents a value in a ``JSONObject``
///
/// Making ``JSONValue`` an `AnyHashable` enables comparing ``JSONObject``s
/// in `Equatable` conformances.
public typealias JSONValue = AnyHashable

/// Represents a JSON Dictionary
///
/// - precondition: A `JSONObject` must only contain values types that are valid for JSON
/// serialization and must be both `Hashable` and `Sendable`. This typealias does not validate
/// that the its values are valid JSON. It functions only as an indicator of the semantic intentions
/// of the underlying value.
///
/// Because this typealias cannot conform to `Sendable`, use ``SendableJSONObject`` to wrap the value
/// whenever you need to send the JSON across isolation boundaries.
public typealias JSONObject = [String: JSONValue]

/// Represents a JSON Dictionary as a wrapper struct that conforms to `Sendable` and `Hashable`.
///
/// This wrapper struct is useful when you need a ``JSONObject`` to conform to `Sendable`.
/// When used in a synchronous context, ``JSONObject`` can be used.
///
/// - warning: No validation of the underlying data is actually performed during initialization.
/// `SendableJSONObject` instances created by `Apollo` are guaranteed to be valid JSON.
public struct SendableJSONObject: @unchecked Sendable, Hashable, ExpressibleByDictionaryLiteral {

  public let base: JSONObject

  /// Designated Initializer
  ///
  /// - Parameter base: A valid ``JSONObject``
  ///
  /// - precondition: The ``JSONObject`` must only contain values types that are valid for JSON
  /// serialization and must be both `Hashable` and `Sendable`.
  @_spi(unsafe_JSON) @inlinable
  public init(unsafe base: JSONObject) {
    self.base = base
  }

  @_spi(unsafe_JSON) @inlinable
  public init?(unsafe base: JSONObject?) {
    guard let base else { return nil }
    self.base = base
  }

  /// ExpressibleByDictionaryLiteral initializer
  ///
  /// - precondition: The ``JSONObject`` must only contain values types that are valid for JSON
  /// serialization and must be both `Hashable` and `Sendable`.
  @_spi(unsafe_JSON) @inlinable
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self.base = Dictionary(elements)
  }

  public subscript(_ key: String) -> JSONValue? {
    base[key]
  }
}

/// Represents a Dictionary that can be converted into a ``JSONObject``
///
/// To convert to a ``JSONObject``:
/// ```swift
/// dictionary.compactMapValues { $0.jsonValue }
/// ```
public typealias JSONEncodableDictionary = [String: any JSONEncodable]

/// A protocol for a type that can be initialized from a ``JSONValue``.
///
/// This is used to interoperate between the type-safe Swift models and the `JSON` in a
/// GraphQL network response/request or the `NormalizedCache`.
public protocol JSONDecodable: AnyHashableConvertible {

  /// Intializes the conforming type from a ``JSONValue``.
  ///
  /// > Important: For a type that conforms to both ``JSONEncodable`` and ``JSONDecodable``,
  /// the `jsonValue` passed to this initializer should be equal to the value returned by the
  /// initialized entity's ``JSONEncodable/jsonValue`` property.
  ///
  /// - Parameter value: The ``JSONValue`` to convert to the ``JSONDecodable`` type.
  ///
  /// - Throws: A ``JSONDecodingError`` if the `jsonValue` cannot be converted to the receiver's
  /// type.
  init(_jsonValue value: JSONValue) throws
}

/// A protocol for a type that can be converted into a ``JSONValue``.
///
/// This is used to interoperate between the type-safe Swift models and the `JSON` in a
/// GraphQL network response/request or the `NormalizedCache`.
public protocol JSONEncodable: Sendable {

  /// Converts the type into a ``JSONValue`` that can be sent in a GraphQL network request or
  /// stored in the `NormalizedCache`.
  ///
  /// > Important: For a type that conforms to both ``JSONEncodable`` and ``JSONDecodable``,
  /// the return value of this function, when passed to ``JSONDecodable/init(jsonValue:)`` should
  /// initialize a value equal to the receiver.
  var _jsonValue: JSONValue { get }
}
