import ApolloAPI
import Foundation

/// The type of a test mock field whose response key is selected with schema fields that have
/// incompatible types, such as different scalars, or a scalar and an object.
///
/// The field accepts any value that is valid for one of those schema fields: a scalar, a ``Mock``,
/// or a list of them.
public enum AnyFieldValue: ErasedMockFieldValue {
  public static var _mockValueDescription: String { "a scalar, a Mock, or a list of them" }

  public static func _isValidMockValue(_ value: Any) -> Bool {
    guard let value = unwrappedMockValue(value) else { return false }

    switch value {
    case is any AnyMock, is any AnyScalarType, is NSNumber:
      return true

    case let list as [Any]:
      return list.allSatisfy { element in
        unwrappedMockValue(element) == nil || _isValidMockValue(element)
      }

    default:
      return false
    }
  }
}

/// A test mock field type that can be set to any field value at some list depth.
///
/// This is ``AnyFieldValue``, or a list or optional wrapping it.
public protocol ErasedMockFieldValue: Sendable {
  /// A description of the values a test mock field of this type accepts.
  static var _mockValueDescription: String { get }

  /// Whether `value` can be set on a test mock field of this type.
  static func _isValidMockValue(_ value: Any) -> Bool
}

extension Array: ErasedMockFieldValue where Element: ErasedMockFieldValue {
  public static var _mockValueDescription: String {
    "a list whose elements are each \(Element._mockValueDescription)"
  }

  public static func _isValidMockValue(_ value: Any) -> Bool {
    guard let list = unwrappedMockValue(value) as? [Any] else { return false }
    return list.allSatisfy { Element._isValidMockValue($0) }
  }
}

extension Optional: ErasedMockFieldValue where Wrapped: ErasedMockFieldValue {
  public static var _mockValueDescription: String {
    "nil or \(Wrapped._mockValueDescription)"
  }

  public static func _isValidMockValue(_ value: Any) -> Bool {
    unwrappedMockValue(value) == nil || Wrapped._isValidMockValue(value)
  }
}

/// `value` without any `AnyHashable` or `Optional` wrappers, or `nil` if it wraps `nil`.
func unwrappedMockValue(_ value: Any) -> Any? {
  if type(of: value) == AnyHashable.self, let hashable = value as? AnyHashable {
    return unwrappedMockValue(hashable.base)
  }

  let mirror = Mirror(reflecting: value)
  guard mirror.displayStyle == .optional else { return value }
  return mirror.children.first.flatMap { unwrappedMockValue($0.value) }
}

/// `value` as test mock data: `nil` if it wraps `nil`, lists as `[AnyHashable?]` at every depth,
/// and other values as they are.
func normalizedMockValue(_ value: Any) -> AnyHashable? {
  guard let value = unwrappedMockValue(value) else { return nil }

  if let list = value as? [Any] {
    return list.map(normalizedMockValue)
  }
  return value as? AnyHashable
}
