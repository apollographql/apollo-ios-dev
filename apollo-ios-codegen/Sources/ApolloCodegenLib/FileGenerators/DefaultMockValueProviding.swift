import GraphQLCompiler

public protocol DefaultMockValueProviding {
  var defaultMockValue: String { get }
}

extension GraphQLType {
  public var defaultMockValue: String {
    switch self {
    case let .list(innerType):
      return "[]"
    case let .nonNull(innerType):
      return innerType.defaultMockValue
    case let .entity(compositeType):
      guard let defaultMockingType = compositeType as? any DefaultMockValueProviding else {
        fatalError("Composite type does not provide a default mock object")
      }
      return defaultMockingType.defaultMockValue
    case let .scalar(scalarType):
      return scalarType.defaultMockValue
    case let .`enum`(enumType):
      return enumType.defaultMockValue
    case .inputObject:
      fatalError("InputObjects aren't mocked")
    }
  }
}

extension GraphQLScalarType: DefaultMockValueProviding {
  public var defaultMockValue: String {
    switch name.schemaName {
    case "String", "ID":
      return "\"\""
    case "Int":
      return "0"
    case "Float":
      return "0.0"
    case "Boolean":
      return "false"
    default:
      return "try! .init(_jsonValue: \"\")"
    }
  }
}

extension GraphQLEnumType: DefaultMockValueProviding {
  public var defaultMockValue: String {
    guard let first = values.first else {
      fatalError("Cannot provide a default value for caseless enum \(name)")
    }
    return ".\(first.name)"
  }
}

extension GraphQLObjectType: DefaultMockValueProviding {
  public var defaultMockValue: String {
    return "Mock<\(name)>()"
  }
}

extension GraphQLInterfaceType: DefaultMockValueProviding {
  public var defaultMockValue: String {
    guard let implementingObject = implementingObjects.first else {
      fatalError("Cannot provide a default value for interface \(name) because no types conform to it.")
    }
    return "Mock<\(implementingObject.name)>()"
  }
}

extension GraphQLUnionType: DefaultMockValueProviding {
  public var defaultMockValue: String {
    guard let implementingType = types.first else {
      fatalError("Cannot provide a default value for empty union \(name)")
    }
    return "Mock<\(implementingType.name)>()"
  }
}
