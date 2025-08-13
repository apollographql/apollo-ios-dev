import Foundation

/// A structure that wraps the underlying data for a ``SelectionSet``.
public struct DataDict: Hashable {
  @usableFromInline var _storage: _Storage

  /// The underlying data for a `SelectionSet`.
  ///
  /// - Warning: This is not identical to the JSON response from a GraphQL network request.
  /// The data should be normalized for consumption by a ``SelectionSet``. This means:
  ///
  /// * Values for entity fields are represented by ``DataDict`` values
  /// * Custom scalars are serialized and converted to their concrete types.
  ///
  /// The process of converting a JSON response into a ``SelectionSet`` is done by using a
  /// `GraphQLExecutor` with a`GraphQLSelectionSetMapper`. This can be performed manually
  /// by using `SelectionSet.init(data: JSONObject, variables: GraphQLOperation.Variables?)` in
  /// the `Apollo` library.
  @inlinable public var _data: [String: AnyHashable] {
    get { _storage.data }
    set {
      if !isKnownUniquelyReferenced(&_storage) {
        _storage = _storage.copy()
      }
      _storage.data = newValue
    }
    _modify {
      if !isKnownUniquelyReferenced(&_storage) {
        _storage = _storage.copy()
      }
      var data = _storage.data
      defer { _storage.data = data }
      yield &data
    }
  }

  /// The set of fragments types that are fulfilled by the data of the ``SelectionSet``.
  ///
  /// During GraphQL execution, the fragments which have had their selections executed are tracked.
  /// This allows conversion of a ``SelectionSet`` to its fragment models to be done safely.
  ///
  /// Each `ObjectIdentifier` in the set corresponds to a specific `SelectionSet` type.
  @inlinable public var _fulfilledFragments: Set<ObjectIdentifier> {
    _storage.fulfilledFragments
  }

  /// The set of fragments that have not yet been fulfilled and will be delivered in a future
  /// response.
  ///
  /// Each `ObjectIdentifier` in the set corresponds to a specific `SelectionSet` type.
  @inlinable public var _deferredFragments: Set<ObjectIdentifier> {
    _storage.deferredFragments
  }

  public init(
    data: [String: AnyHashable],
    fulfilledFragments: Set<ObjectIdentifier>,
    deferredFragments: Set<ObjectIdentifier> = []
  ) {
    self._storage = .init(
      data: data,
      fulfilledFragments: fulfilledFragments,
      deferredFragments: deferredFragments
    )
  }

  @inlinable public subscript<T: AnyScalarType & Hashable>(_ key: String) -> T {
    get {
      if DataDict._AnyHashableCanBeCoerced {
        return _data[key] as! T
      } else {
        let value = _data[key]
        if value == DataDict._NullValue {
          return (Optional<T>.none as Any) as! T
        } else {
          return (value?.base as? T) ?? (value._asAnyHashable as! T)
        }
      }
    }
    set {
      _data[key] = newValue
    }
    _modify {
      var value = _data[key] as! T
      defer { _data[key] = value }
      yield &value
    }
  }

  @inlinable public subscript<T: SelectionSetEntityValue>(_ key: String) -> T {
    get { T.init(_fieldData: _data[key]) }
    set {
      _data[key] = newValue._fieldData
    }
    _modify {
      var value = T.init(_fieldData: _data[key])
      defer { _data[key] = value._fieldData }
      yield &value
    }
  }

  @inlinable public func hash(into hasher: inout Hasher) {
    hasher.combine(_data)
  }

  @inlinable public static func ==(lhs: DataDict, rhs: DataDict) -> Bool {
    lhs._data == rhs._data
  }

  @usableFromInline func fragmentIsFulfilled<T: SelectionSet>(_ type: T.Type) -> Bool {
    let id = ObjectIdentifier(T.self)
    return _fulfilledFragments.contains(id)
  }

  @usableFromInline func fragmentsAreFulfilled(_ types: [any SelectionSet.Type]) -> Bool {
    let typeIds = types.lazy.map(ObjectIdentifier.init)
    return _fulfilledFragments.isSuperset(of: typeIds)
  }

  // MARK: - DataDict._Storage
  @usableFromInline class _Storage: Hashable {
    @usableFromInline var data: [String: AnyHashable]
    @usableFromInline let fulfilledFragments: Set<ObjectIdentifier>
    @usableFromInline let deferredFragments: Set<ObjectIdentifier>

    init(
      data: [String: AnyHashable],
      fulfilledFragments: Set<ObjectIdentifier>,
      deferredFragments: Set<ObjectIdentifier>
    ) {
      self.data = data
      self.fulfilledFragments = fulfilledFragments
      self.deferredFragments = deferredFragments
    }

    @usableFromInline static func ==(lhs: DataDict._Storage, rhs: DataDict._Storage) -> Bool {
      lhs.data == rhs.data &&
      lhs.fulfilledFragments == rhs.fulfilledFragments &&
      lhs.deferredFragments == rhs.deferredFragments
    }

    @usableFromInline func hash(into hasher: inout Hasher) {
      hasher.combine(data)
      hasher.combine(fulfilledFragments)
      hasher.combine(deferredFragments)
    }

    @usableFromInline func copy() -> _Storage {
      _Storage(
        data: self.data,
        fulfilledFragments: self.fulfilledFragments,
        deferredFragments: self.deferredFragments
      )
    }
  }
}

// MARK: - Null Value Definition
extension DataDict {
  /// A common value used to represent a null value in a `DataDict`.
  ///
  /// This value can be cast to `NSNull` and will bridge automatically.
  public static let _NullValue = {
    if DataDict._AnyHashableCanBeCoerced {
      return AnyHashable(Optional<AnyHashable>.none)
    } else {
      return NSNull()
    }
  }()

  /// Indicates if `AnyHashable` can be coerced via casting into its underlying type.
  ///
  /// In iOS versions 14.4 and lower, `AnyHashable` coercion does not work. On these platforms,
  /// we need to do some additional unwrapping and casting of the values to avoid crashes and other
  /// run time bugs.
  public static let _AnyHashableCanBeCoerced: Bool = {
    if #available(iOS 14.5, macOS 11.3, tvOS 14.5, watchOS 7.4, *) {
      return true
    } else {
      return false
    }
  }()

}

// MARK: - Encodable
struct StringKey: CodingKey {
  let stringValue: String
  
  init?(stringValue: String) {
    self.stringValue = stringValue
  }
  
  init(_ key: String) {
    self.stringValue = key
  }
  
  var intValue: Int? { nil }
  
  init?(intValue: Int) {
    nil
  }
    
}

extension DataDict: Encodable {
  public func encode(to encoder: any Encoder) throws {
    let keys = _data.keys.sorted()
    var container = encoder.container(keyedBy: StringKey.self)
    for key in keys {
      if let value = _data[key] {
        try value.encode(in: &container, at: StringKey(key))
      }
    }
  }
}

extension AnyHashable {
  func encode(in container: inout KeyedEncodingContainer<StringKey>, at key: StringKey) throws {
    if let encodableValue = self.base as? (any Encodable) {
      try encodableValue.encode(to: container.superEncoder(forKey: key))
    } else if let array = self.base as? [AnyHashable] {
      var arrayContainer = container.nestedUnkeyedContainer(forKey: key)
      for item in array {
        try item.encode(in: &arrayContainer)
      }
    } else if let array = self.base as? [AnyHashable?] {
      var arrayContainer = container.nestedUnkeyedContainer(forKey: key)
      for item in array {
        if let item = item {
          try item.encode(in: &arrayContainer)
        } else {
          try arrayContainer.encodeNil()
        }
      }
    } else if let optional = self.base as? Optional<AnyHashable> {
      if let value = optional {
        try value.encode(in: &container, at: key)
      } else {
        try container.encodeNil(forKey: key)
      }
    } else {
      throw EncodingError.invalidValue(self.base, .init(codingPath: container.codingPath, debugDescription: "Unexpected type for encoding: \(type(of: self.base))"))
    }
  }
  
  func encode(in container: inout any UnkeyedEncodingContainer) throws {
    if let encodableValue = self.base as? (any Encodable) {
      try encodableValue.encode(to: container.superEncoder())
    } else if let array = self.base as? [AnyHashable] {
      var arrayContainer = container.nestedUnkeyedContainer()
      for item in array {
        try item.encode(in: &arrayContainer)
      }
    } else if let array = self.base as? [AnyHashable?] {
      var arrayContainer = container.nestedUnkeyedContainer()
      for item in array {
        if let item = item {
          try item.encode(in: &arrayContainer)
        } else {
          try arrayContainer.encodeNil()
        }
      }
    } else if let optional = self.base as? Optional<AnyHashable> {
      if let value = optional {
        try value.encode(in: &container)
      } else {
        try container.encodeNil()
      }
    } else {
      throw EncodingError.invalidValue(self.base, .init(codingPath: container.codingPath, debugDescription: "Unexpected type for encoding: \(type(of: self.base))"))
    }
  }
}


// MARK: - Value Conversion Helpers

public protocol SelectionSetEntityValue {
  /// - Warning: This function is not supported for external use.
  /// Unsupported usage may result in unintended consequences including crashes.
  ///
  /// The `_fieldData` should be the underlying `DataDict` for an entity value.
  /// This is represented as `AnyHashable` because for `Optional` and `Array` you will have an
  /// `Optional<DataDict>` and `[DataDict]` respectively.
  init(_fieldData: AnyHashable?)
  var _fieldData: AnyHashable { get }
}

extension RootSelectionSet {
  /// - Warning: This function is not supported for external use.
  /// Unsupported usage may result in unintended consequences including crashes.
  @inlinable public init(_fieldData data: AnyHashable?) {
    guard let dataDict = data as? DataDict else {
      fatalError("\(Self.self) expected DataDict for entity, got \(type(of: data)).")
    }
    self.init(_dataDict: dataDict)
  }

  @inlinable public var _fieldData: AnyHashable { __data }
}

extension Optional: SelectionSetEntityValue where Wrapped: SelectionSetEntityValue {
  /// - Warning: This function is not supported for external use.
  /// Unsupported usage may result in unintended consequences including crashes.
  @inlinable public init(_fieldData data: AnyHashable?) {
    switch data {
      case .none:
        self = .none
      case .some(let hashable):
      if !DataDict._AnyHashableCanBeCoerced && hashable == DataDict._NullValue {
        self = .none
      } else if let optional = hashable.base as? Optional<AnyHashable>, optional == nil {
        self = .none
      } else {
        self = .some(Wrapped.init(_fieldData: data))
      }
    }
  }

  @inlinable public var _fieldData: AnyHashable { map(\._fieldData) }
}

extension Array: SelectionSetEntityValue where Element: SelectionSetEntityValue {
  /// - Warning: This function is not supported for external use.
  /// Unsupported usage may result in unintended consequences including crashes.
  @inlinable public init(_fieldData data: AnyHashable?) {
    guard let data = data as? [AnyHashable?] else {
      fatalError("\(Self.self) expected list of data for entity.")
    }
    self = data.map {
      if DataDict._AnyHashableCanBeCoerced {
        return Element.init(_fieldData:$0)
      } else {
        return Element.init(_fieldData:$0?.base as? AnyHashable)
      }
    }
  }

  @inlinable public var _fieldData: AnyHashable { map(\._fieldData) }
}
