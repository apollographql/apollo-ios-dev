import JavaScriptCore

/// A GraphQL type.
public indirect enum GraphQLType: Sendable, Hashable {
  case entity(GraphQLCompositeType)
  case scalar(GraphQLScalarType)
  case `enum`(GraphQLEnumType)
  case inputObject(GraphQLInputObjectType)
  case nonNull(GraphQLType)
  case list(GraphQLType)

  public var typeReference: String {
    switch self {
    case let .entity(type as GraphQLNamedType),
         let .scalar(type as GraphQLNamedType),
         let .enum(type as GraphQLNamedType),
         let .inputObject(type as GraphQLNamedType):
      return type.name.schemaName

    case let .nonNull(ofType):
      return "\(ofType.typeReference)!"

    case let .list(ofType):
      return "[\(ofType.typeReference)]"
    }
  }

  public var namedType: GraphQLNamedType {
    switch self {
    case let .entity(type as GraphQLNamedType),
         let .scalar(type as GraphQLNamedType),
         let .enum(type as GraphQLNamedType),
         let .inputObject(type as GraphQLNamedType):
      return type

    case let .nonNull(innerType),
      let .list(innerType):
      return innerType.namedType
    }
  }

  public var innerType: GraphQLType {
    switch self {
    case .entity, .scalar, .enum, .inputObject:
      return self

    case let .nonNull(innerType),
      let .list(innerType):
      return innerType.innerType
    }
  }

  public var isNullable: Bool {
    if case .nonNull = self { return false }
    return true
  }

  public var defaultMockValue: String {
    switch self {
    case let .list(innerType):
      return "[\(innerType.defaultMockValue)]"
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

extension GraphQLType: CustomDebugStringConvertible {
  public var debugDescription: String {
    return "\(typeReference)"
  }
}

extension GraphQLType: JavaScriptObjectDecodable {
  static func fromJSValue(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) -> Self {
    precondition(jsValue.isObject, "Expected JavaScript object but found: \(jsValue)")

    let tag = jsValue[jsValue.context.globalObject["Symbol"]["toStringTag"]].toString()

    switch tag {
    case "GraphQLNonNull":
      let ofType = jsValue["ofType"]
      return .nonNull(GraphQLType.fromJSValue(ofType, bridge: bridge))
    case "GraphQLList":
      let ofType = jsValue["ofType"]
      return .list(GraphQLType.fromJSValue(ofType, bridge: bridge))
    default:
      let namedType = GraphQLNamedType.fromJSValue(jsValue, bridge: bridge)

      switch namedType {
      case let entityType as GraphQLCompositeType:
        return .entity(entityType)

      case let scalarType as GraphQLScalarType:
        return .scalar(scalarType)

      case let enumType as GraphQLEnumType:
        return .enum(enumType)

      case let inputObjectType as GraphQLInputObjectType:
        return .inputObject(inputObjectType)

      default:
        fatalError("JSValue: \(jsValue) is not a recognized GraphQLType value.")
      }
    }
  }
}
