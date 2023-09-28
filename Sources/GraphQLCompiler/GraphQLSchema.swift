import JavaScriptCore
import OrderedCollections

// These classes correspond directly to the ones in
// https://github.com/graphql/graphql-js/tree/master/src/type
// and are partially described in https://graphql.org/graphql-js/type/

/// A GraphQL schema.
public final class GraphQLSchema: JavaScriptReferencedObject, JavaScriptCallable {

  let jsValue: JSValue
  let bridge: JavaScriptBridge

  static func initializeNewObject(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) -> Self {
    self.init(jsValue: jsValue, bridge: bridge)
  }

  private init(jsValue: JSValue, bridge: JavaScriptBridge) {
    self.jsValue = jsValue
    self.bridge = bridge
  }

  // MARK: Methods
  func getType(named typeName: String) async throws -> (GraphQLNamedType)? {
    try await invokeMethod("getType", with: typeName)
  }
  
  func getPossibleTypes(_ abstractType: GraphQLAbstractType) async throws -> [GraphQLObjectType] {
    return try await invokeMethod("getPossibleTypes", with: abstractType)
  }
  
  func getImplementations(
    interfaceType: GraphQLInterfaceType
  ) async throws -> InterfaceImplementations {
    return try await invokeMethod("getImplementations", with: interfaceType)
  }
  
  struct InterfaceImplementations: JavaScriptObjectDecodable {
    let objects: [GraphQLObjectType]
    let interfaces: [GraphQLInterfaceType]

    static func fromJSValue(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) -> Self {
      self.init(
        objects: .fromJSValue(jsValue["objects"], bridge: bridge),
        interfaces: .fromJSValue(jsValue["interfaces"], bridge: bridge)
      )
    }
  }
    
  func isSubType(
    abstractType: GraphQLAbstractType,
    maybeSubType: GraphQLNamedType
  ) async throws -> Bool {
    return try await invokeMethod("isSubType", with: abstractType, maybeSubType)
  }
}

protocol GraphQLSchemaType: JavaScriptReferencedObject {

}

public class GraphQLNamedType: 
  JavaScriptReferencedObject, @unchecked Sendable, Hashable, CustomDebugStringConvertible {
  public let name: String

  public let documentation: String?

  required init(
    _ jsValue: JSValue,
    bridge: isolated JavaScriptBridge
  ) {
    self.name = jsValue["name"]
    self.documentation = jsValue["description"]
  }

  static func initializeNewObject(
    _ jsValue: JSValue,
    bridge: isolated JavaScriptBridge
  ) -> Self {
    return self.init(jsValue, bridge: bridge)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
  }

  public static func ==(lhs: GraphQLNamedType, rhs: GraphQLNamedType) -> Bool {
    return lhs.name == rhs.name
  }

  public var debugDescription: String {
    name
  }
}

public final class GraphQLScalarType: GraphQLNamedType {

  public let specifiedByURL: String?

  public var isCustomScalar: Bool {
    guard self.specifiedByURL == nil else { return true }

    switch name {
    case "String", "Int", "Float", "Boolean", "ID":
      return false
    default:
      return true
    }
  }

  required init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    self.specifiedByURL = jsValue["specifiedByUrl"]
    super.init(jsValue, bridge: bridge)
  }

}

public final class GraphQLEnumType: GraphQLNamedType {
  public let values: [GraphQLEnumValue]

  required init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    self.values = try! bridge.invokeMethod("getValues", on: jsValue)
    super.init(jsValue, bridge: bridge)
  }
}

public struct GraphQLEnumValue: JavaScriptObjectDecodable {

  public struct Name {
    public let value: String

    public init(value: String) {
      self.value = value
    }
  }

  public let name: Name

  public let documentation: String?

  public let deprecationReason: String?

  public var isDeprecated: Bool { deprecationReason != nil }

  static func fromJSValue(
    _ jsValue: JSValue,
    bridge: isolated JavaScriptBridge
  ) -> GraphQLEnumValue {
    self.init(
      name: .init(value: jsValue["name"]),
      documentation: jsValue["description"],
      deprecationReason: jsValue["deprecationReason"]
    )
  }
}

public typealias GraphQLInputFieldDictionary = OrderedDictionary<String, GraphQLInputField>

public final class GraphQLInputObjectType: GraphQLNamedType {
  public let fields: GraphQLInputFieldDictionary

  required init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    self.fields = try! bridge.invokeMethod("getFields", on: jsValue)
    super.init(jsValue, bridge: bridge)
  }
}

public struct GraphQLInputField: JavaScriptObjectDecodable {
  public let name: String

  public let type: GraphQLType

  public let documentation: String?

  public let deprecationReason: String?

  public let defaultValue: GraphQLValue?

  static func fromJSValue(
    _ jsValue: JSValue,
    bridge: isolated JavaScriptBridge
  ) -> GraphQLInputField {
    self.init(
      name: jsValue["name"],
      type: GraphQLType.fromJSValue(jsValue["type"], bridge: bridge),
      documentation: jsValue["description"],
      deprecationReason: jsValue["deprecationReason"],
      defaultValue: (jsValue["astNode"] as JSValue?)?["defaultValue"]
    )
  }
}

public class GraphQLCompositeType: GraphQLNamedType {
  public override var debugDescription: String {
    "Type - \(name)"
  }
}

public protocol GraphQLInterfaceImplementingType: GraphQLCompositeType {
  var interfaces: [GraphQLInterfaceType] { get }
}

public extension GraphQLInterfaceImplementingType {
  func implements(_ interface: GraphQLInterfaceType) -> Bool {
    interfaces.contains(interface)
  }
}

public final class GraphQLObjectType: GraphQLCompositeType, GraphQLInterfaceImplementingType {
  public let fields: [String: GraphQLField]

  public let interfaces: [GraphQLInterfaceType]

  required init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    self.fields = try! bridge.invokeMethod("getFields", on: jsValue)
    self.interfaces = try! bridge.invokeMethod("getInterfaces", on: jsValue)
    super.init(jsValue, bridge: bridge)
  }

  public override var debugDescription: String {
    "Object - \(name)"
  }
}

public class GraphQLAbstractType: GraphQLCompositeType {
}

public final class GraphQLInterfaceType: GraphQLAbstractType, GraphQLInterfaceImplementingType {
  public let deprecationReason: String?

  public let fields: [String: GraphQLField]

  public let interfaces: [GraphQLInterfaceType]

  required init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    self.deprecationReason = jsValue["deprecationReason"]
    self.fields = try! bridge.invokeMethod("getFields", on: jsValue)
    self.interfaces = try! bridge.invokeMethod("getInterfaces", on: jsValue)
    super.init(jsValue, bridge: bridge)
  }

  public override var debugDescription: String {
    "Interface - \(name)"
  }
}

public final class GraphQLUnionType: GraphQLAbstractType {
  public let types: [GraphQLObjectType]

  required init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    self.types = try! bridge.invokeMethod("getTypes", on: jsValue)
    super.init(jsValue, bridge: bridge)
  }

  public override var debugDescription: String {
    "Union - \(name)"
  }
}

public final class GraphQLField:
  JavaScriptObjectDecodable, Sendable, Hashable, CustomDebugStringConvertible {

  public let name: String

  public let type: GraphQLType

  public let arguments: [GraphQLFieldArgument]

  public let documentation: String?

  public let deprecationReason: String?

  init(
    name: String,
    type: GraphQLType,
    arguments: [GraphQLFieldArgument],
    documentation: String?,
    deprecationReason: String?
  ) {
    self.name = name
    self.type = type
    self.arguments = arguments
    self.documentation = documentation
    self.deprecationReason = deprecationReason
  }

  static func fromJSValue(
    _ jsValue: JSValue,
    bridge: isolated JavaScriptBridge
  ) -> GraphQLField {
    self.init(
      name: jsValue["name"],
      type: .fromJSValue(jsValue["type"], bridge: bridge),
      arguments: .fromJSValue(jsValue["args"], bridge: bridge),
      documentation: jsValue["description"],
      deprecationReason: jsValue["deprecationReason"]
    )
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
    hasher.combine(type)
    hasher.combine(arguments)
  }

  public static func == (lhs: GraphQLField, rhs: GraphQLField) -> Bool {
    lhs.name == rhs.name &&
    lhs.type == rhs.type &&
    lhs.arguments == rhs.arguments
  }

  public var debugDescription: String {
    "\(name): \(type.debugDescription)"
  }
}

public struct GraphQLFieldArgument: JavaScriptObjectDecodable, Sendable, Hashable {

  public let name: String

  public let type: GraphQLType

  public let documentation: String?

  public let deprecationReason: String?

  init(
    name: String,
    type: GraphQLType,
    documentation: String?,
    deprecationReason: String?
  ) {
    self.name = name
    self.type = type
    self.documentation = documentation
    self.deprecationReason = deprecationReason
  }

  static func fromJSValue(
    _ jsValue: JSValue,
    bridge: isolated JavaScriptBridge
  ) -> GraphQLFieldArgument {
    self.init(
      name: jsValue["name"],
      type: .fromJSValue(jsValue["type"], bridge: bridge),
      documentation: jsValue["description"],
      deprecationReason: jsValue["deprecationReason"]
    )
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
    hasher.combine(type)
  }

  public static func == (lhs: GraphQLFieldArgument, rhs: GraphQLFieldArgument) -> Bool {
    lhs.name == rhs.name &&
    lhs.type == rhs.type
  }
  
}
