import Foundation

/// A type erased wrapper for optional values.
///
/// This is used to help handle nested optional values in dyanmic JSON data.
@_spi(Internal)
public protocol AnyOptional {
  /// `true` iff the underlying optional is `.none`. Allows code that has already type-erased
  /// an optional to `any AnyOptional` to distinguish `.none` from `.some` without a `Mirror`
  /// or knowledge of the wrapped type.
  var _isNone: Bool { get }
}

@_spi(Internal)
extension Optional: AnyOptional {
  public var _isNone: Bool {
    if case .none = self { return true }
    return false
  }
}

extension Optional where Wrapped: Sendable {

  /// Converts the optional to a `GraphQLNullable.
  ///
  /// - Double nested optional (ie. `Optional.some(nil)`) -> `GraphQLNullable.null`.
  /// - `Optional.none` -> `GraphQLNullable.none`
  /// - `Optional.some` -> `GraphQLNullable.some`
  @_spi(Internal)
  @inlinable
  public var asNullable: GraphQLNullable<Wrapped> {
    unwrapAsNullable()
  }

  @usableFromInline
  func unwrapAsNullable(nullIfNil: Bool = false) -> GraphQLNullable<Wrapped> {
    switch self {
    case .none: return nullIfNil ? .null : .none

    case .some(let value as any AnyOptional):
      return (value as! Self).unwrapAsNullable(nullIfNil: true)

    case .some(is NSNull):
      return .null

    case .some(let value):
      return .some(value)
    }
  }
}
