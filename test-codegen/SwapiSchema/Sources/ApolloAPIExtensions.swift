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
    guard let value = value else {
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
