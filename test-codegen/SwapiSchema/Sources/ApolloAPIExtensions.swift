import ApolloAPI

public protocol Validatable {
  static func validate(value: Self?) throws
}

public enum ValidationError: Error {
  case dataIsNil
  case dataCorrupted
}

extension AnyScalarType {
  public static func validate(value: Self?) throws {
    guard value != nil else {
      throw ValidationError.dataIsNil
    }
  }
}

extension String: Validatable {}
extension Int: Validatable {}
extension Bool: Validatable {}
extension Float: Validatable {}
extension Double: Validatable {}
extension GraphQLEnum: Validatable {}

extension Optional: Validatable where Wrapped: Validatable {
  public static func validate(value: Wrapped??) throws {
    switch value {
    case .some(let value):
      try Wrapped.validate(value: value)
    case .none:
      break
    }
  }
}

extension Array: Validatable where Element: Validatable {
  public static func validate(value: [Element]?) throws {
    guard let value = value else {
      throw ValidationError.dataIsNil
    }
    
    for element in value {
      try Element.validate(value: element)
    }
  }
}

extension ApolloAPI.SelectionSet {
  public func validate<T: Validatable & SelectionSetEntityValue>(_: T.Type, for key: String) throws {
    let value: T? = self.__data[key]
    try T.validate(value: value)
  }
  public func validate<T: Validatable & AnyScalarType & Hashable>(_: T.Type, for key: String) throws {
    let value: T? = self.__data[key]
    try T.validate(value: value)
  }
}

extension Validatable {
  public func validate() throws {
    try Self.validate(value: self)
  }
}

// MARK - Codable

//extension String: @retroactive CodingKey {
//  public var stringValue: String {
//    self
//  }
//  public var intValue: Int? {
//    nil
//  }
//  public init?(intValue: Int) {
//    nil
//  }
//  public init?(stringValue: String) {
//    self = stringValue
//  }
//}

extension GraphQLEnum: Codable {
  
}

extension DataDict {
  public init(
    data: [String: AnyHashable],
    fulfilledFragments: [ObjectIdentifier?],
    deferredFragments: [ObjectIdentifier?] = []
  ) {
    self.init(data: data, fulfilledFragments: Set(fulfilledFragments.compactMap { $0 }), deferredFragments: Set(deferredFragments.compactMap { $0 }))
  }
}

extension ApolloAPI.SelectionSet {
  public func encode(to encoder: Encoder) throws {
    try self.__data.encode(to: encoder)
  }
}
