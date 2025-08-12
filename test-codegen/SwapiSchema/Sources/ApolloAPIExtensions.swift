import ApolloAPI

public protocol Validatable {
  static func validate(value: Self?) throws
}

public enum ValidationError: Error {
  case dataIsNil
  case dataCorrupted
}
  
extension String: Validatable {
  public static func validate(value: String?) throws {
    guard let value = value else {
      throw ValidationError.dataIsNil
    }
    
    guard let _ = value as? String else {
      throw ValidationError.dataCorrupted
    }
  }
}

extension Int: Validatable {
  public static func validate(value: Int?) throws {
    guard let value = value else {
      throw ValidationError.dataIsNil
    }
    
    guard let _ = value as? Int else {
      throw ValidationError.dataCorrupted
    }
  }
}


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

extension SelectionSet {
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
