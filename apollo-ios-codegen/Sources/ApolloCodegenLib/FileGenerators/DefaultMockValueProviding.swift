import GraphQLCompiler
import IR

protocol DefaultMockValueProviding {
  func defaultMockValue(
    config: ApolloCodegen.ConfigurationContext,
    referencedTypes: IR.Schema.ReferencedTypes
  ) -> String?
}

extension GraphQLType {
  func defaultMockValue(
    config: ApolloCodegen.ConfigurationContext,
    referencedTypes: IR.Schema.ReferencedTypes
  ) -> String? {
    switch self {
    case .list:
      return "[]"
    case let .nonNull(innerType):
      return innerType.defaultMockValue(config: config, referencedTypes: referencedTypes)
    case let .entity(compositeType):
      guard let defaultMockingType = compositeType as? any DefaultMockValueProviding else {
        fatalError("Composite type does not provide a default mock object")
      }
      return defaultMockingType.defaultMockValue(config: config, referencedTypes: referencedTypes)
    case let .scalar(scalarType):
      return scalarType.defaultMockValue(config: config, referencedTypes: referencedTypes)
    case let .`enum`(enumType):
      return enumType.defaultMockValue(config: config, referencedTypes: referencedTypes)
    case .inputObject:
      fatalError("InputObjects aren't mocked")
    }
  }
}

extension GraphQLScalarType: DefaultMockValueProviding {
  func defaultMockValue(
    config: ApolloCodegen.ConfigurationContext,
    referencedTypes: IR.Schema.ReferencedTypes
  ) -> String? {
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
      return ".defaultMockValue"
    }
  }
}

extension GraphQLEnumType: DefaultMockValueProviding {
  func defaultMockValue(
    config: ApolloCodegen.ConfigurationContext,
    referencedTypes: IR.Schema.ReferencedTypes
  ) -> String? {
    let filteredValues: [GraphQLEnumValue]
    if config.options.deprecatedEnumCases == .exclude {
      filteredValues = values.filter { !$0.isDeprecated }
    } else {
      filteredValues = values
    }
    guard let first = filteredValues.first else {
      fatalError("Cannot provide a default value for caseless enum \(name)")
    }
    return ".case(.\(first.render(as: .enumCase, config: config)))"
  }
}

extension GraphQLObjectType: DefaultMockValueProviding {
  func defaultMockValue(
    config: ApolloCodegen.ConfigurationContext,
    referencedTypes: IR.Schema.ReferencedTypes
  ) -> String? {
    return "Mock<\(self.render(as: .typename()))>()"
  }
}

extension GraphQLInterfaceType: DefaultMockValueProviding {
  func defaultMockValue(
    config: ApolloCodegen.ConfigurationContext,
    referencedTypes: IR.Schema.ReferencedTypes
  ) -> String? {
    guard let implementingObject = implementingObjects.first(where: {
      !config.options.reduceGeneratedSchemaTypes || referencedTypes.objects.contains($0)
    }) else {
      if config.options.reduceGeneratedSchemaTypes {
        return nil
      } else {
        fatalError("Cannot provide a default value for interface \(name) because no types conform to it.")
      }
    }
    return "Mock<\(implementingObject.render(as: .typename()))>()"
  }
}

extension GraphQLUnionType: DefaultMockValueProviding {
  func defaultMockValue(
    config: ApolloCodegen.ConfigurationContext,
    referencedTypes: IR.Schema.ReferencedTypes
  ) -> String? {
    guard let implementingType = types.first(where: {
      !config.options.reduceGeneratedSchemaTypes || referencedTypes.objects.contains($0)
    }) else {
      if config.options.reduceGeneratedSchemaTypes {
        return nil
      } else {
        fatalError("Cannot provide a default value for empty union \(name)")
      }
    }
    return "Mock<\(implementingType.render(as: .typename()))>()"
  }
}
