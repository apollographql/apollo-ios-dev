import GraphQLCompiler

protocol DefaultMockValueProviding {
  func defaultMockValue(config: ApolloCodegen.ConfigurationContext) -> String
}

extension GraphQLType {
  func defaultMockValue(config: ApolloCodegen.ConfigurationContext) -> String {
    switch self {
    case .list:
      return "[]"
    case let .nonNull(innerType):
      return innerType.defaultMockValue(config: config)
    case let .entity(compositeType):
      guard let defaultMockingType = compositeType as? any DefaultMockValueProviding else {
        fatalError("Composite type does not provide a default mock object")
      }
      return defaultMockingType.defaultMockValue(config: config)
    case let .scalar(scalarType):
      return scalarType.defaultMockValue(config: config)
    case let .`enum`(enumType):
      return enumType.defaultMockValue(config: config)
    case .inputObject:
      fatalError("InputObjects aren't mocked")
    }
  }
}

extension GraphQLScalarType: DefaultMockValueProviding {
  func defaultMockValue(config: ApolloCodegen.ConfigurationContext) -> String {
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
  func defaultMockValue(config: ApolloCodegen.ConfigurationContext) -> String {
    guard let first = values.first else {
      fatalError("Cannot provide a default value for caseless enum \(name)")
    }
    return ".case(.\(first.render(as: .enumCase, config: config)))"
  }
}

extension GraphQLObjectType: DefaultMockValueProviding {
  func defaultMockValue(config: ApolloCodegen.ConfigurationContext) -> String {
    return "Mock<\(self.render(as: .typename))>()"
  }
}

extension GraphQLInterfaceType: DefaultMockValueProviding {
  func defaultMockValue(config: ApolloCodegen.ConfigurationContext) -> String {
    guard let implementingObject = implementingObjects.first else {
      fatalError("Cannot provide a default value for interface \(name) because no types conform to it.")
    }
    return "Mock<\(implementingObject.name)>()"
  }
}

extension GraphQLUnionType: DefaultMockValueProviding {
  func defaultMockValue(config: ApolloCodegen.ConfigurationContext) -> String {
    guard let implementingType = types.first else {
      fatalError("Cannot provide a default value for empty union \(name)")
    }
    return "Mock<\(implementingType.name)>()"
  }
}
