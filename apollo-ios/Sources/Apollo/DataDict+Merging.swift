import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

// MARK: Internal

extension DataDict {
  enum MergeError: Error, LocalizedError {
    case invalidPathDataType(String)
    case cannotOverwriteData(AnyHashable, AnyHashable)

    public var errorDescription: String? {
      switch self {
      case let .invalidPathDataType(invalidType):
        return "Invalid data type for incremental merge. Expected DataDict, got \(invalidType)."

      case let .cannotOverwriteData(current, new):
        return "Incremental data merge cannot overwrite field data value '\(current)' with mismatched value '\(new)'."
      }
    }
  }

  /// Creates a new `DataDict` instance by merging the given `DataDict` into this `DataDict` at the
  /// specified path.
  ///
  /// - Parameters:
  ///   - newDataDict: The `DataDict` to merge.
  ///   - path: The target path at which `newDataDict` should be merged.
  /// - Returns: A new `DataDict` with the combined keys and values of this `DataDict` and `newDataDict`.
  func merging(_ newDataDict: DataDict, at path: [PathComponent]) throws -> DataDict {
    let value = try value(at: path)
    guard let pathDataDict = value as? DataDict else {
      throw MergeError.invalidPathDataType(String(describing: type(of: value)))
    }

    let mergedData = try pathDataDict._data.merging(newDataDict._data) { current, new in
      if current != new {
        throw MergeError.cannotOverwriteData(current, new)
      }

      return current
    }

    let mergedFulfilledFragments = pathDataDict._fulfilledFragments
      .union(newDataDict._fulfilledFragments)

    let mergedDeferredFragments = pathDataDict._deferredFragments
      .subtracting(newDataDict._fulfilledFragments)
      .union(newDataDict._deferredFragments)

    let mergedDataDict = DataDict(
      data: mergedData,
      fulfilledFragments: mergedFulfilledFragments,
      deferredFragments: mergedDeferredFragments
    )

    var result = self
    try result.set(value: mergedDataDict, at: path)

    return result
  }
}

enum PathComponentError: Error, LocalizedError {
  case emptyMergePath
  case unsupportedUnderlyingDataType
  case invalidPathComponentForDataType(PathComponent, String)

  public var errorDescription: String? {
    switch self {
    case .emptyMergePath:
      return "The merge path cannot be empty."

    case .unsupportedUnderlyingDataType:
      return "The underlying data type is not accessible by path component."

    case let .invalidPathComponentForDataType(pathComponent, dataType):
      return "Invalid path component, cannot access \(dataType) with \(pathComponent)."
    }
  }
}

// MARK: - Private

/// Functions that provide the ability to get and set a value when type-specific access to the
/// underlying data storage is required.
fileprivate protocol PathComponentAccessible {
  func value(at path: PathComponent) throws -> AnyHashable?
  mutating func set(value newValue: AnyHashable?, at path: PathComponent) throws
}

/// Common implementations for working with an array of path components - `[PathComponent]`.
extension PathComponentAccessible {
  fileprivate func value(at path: [PathComponent]) throws -> AnyHashable? {
    switch path.headAndTail() {
    case nil:
      throw PathComponentError.emptyMergePath

    case let (head, remaining)? where remaining.isEmpty:
      return try value(at: head)

    case let (head, remaining)?:
      switch try value(at: head) {
      case let dict as DataDict:
        return try dict.value(at: remaining)

      case let array as [AnyHashable?]:
        return try array.value(at: remaining)

      default:
        throw PathComponentError.unsupportedUnderlyingDataType
      }
    }
  }

  fileprivate mutating func set(value newValue: AnyHashable?, at path: [PathComponent]) throws {
    switch path.headAndTail() {
    case nil:
      throw PathComponentError.emptyMergePath

    case let (head, remaining)? where remaining.isEmpty:
      try set(value: newValue, at: head)

    case let (head, remaining)?:
      switch try value(at: head) {
      case var dict as DataDict:
        try dict.set(value: newValue, at: remaining)
        try set(value: dict, at: head)

      case var array as [AnyHashable?]:
        try array.set(value: newValue, at: remaining)
        try set(value: array, at: head)

      default:
        throw PathComponentError.unsupportedUnderlyingDataType
      }
    }
  }
}

extension DataDict: PathComponentAccessible {
  fileprivate func value(at path: PathComponent) throws -> AnyHashable? {
    guard case let .field(field) = path else {
      throw PathComponentError.invalidPathComponentForDataType(path, String(describing: self))
    }

    return self._data[field]
  }

  fileprivate mutating func set(value: AnyHashable?, at path: PathComponent) throws {
    guard case let .field(field) = path else {
      throw PathComponentError.invalidPathComponentForDataType(path, String(describing: self))
    }

    self._data[field] = value
  }
}

extension Array: PathComponentAccessible where Element == AnyHashable? {
  fileprivate func value(at path: PathComponent) throws -> AnyHashable? {
    guard case let .index(index) = path else {
      throw PathComponentError.invalidPathComponentForDataType(path, String(describing: self))
    }

    return self[index]
  }

  fileprivate mutating func set(value: AnyHashable?, at path: PathComponent) throws {
    guard case let .index(index) = path else {
      throw PathComponentError.invalidPathComponentForDataType(path, String(describing: self))
    }

    self[index] = value
  }
}

/// Splits the first `PathComponent` element returning the first element and an array of all
/// remaining elements.
extension Array where Element == PathComponent {
  fileprivate func headAndTail() -> (head: PathComponent, tail: [PathComponent])? {
    guard !isEmpty else { return nil }

    var tail = self
    let head = tail.removeFirst()

    return (head, tail)
  }
}
