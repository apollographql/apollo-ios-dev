import JavaScriptCore
import OrderedCollections

// These classes correspond directly to the ones in
// https://github.com/graphql/graphql-js/tree/master/src/type
// and are partially described in https://graphql.org/graphql-js/type/

/// A GraphQL schema.
public final class GraphQLSchema: JavaScriptObject {

  // MARK: Methods
  func getType(named typeName: String) async throws -> (GraphQLNamedType)? {
    try await invokeMethod("getType", with: typeName)
  }
  
}

protocol GraphQLSchemaType: JavaScriptReferencedObject {

}

public class GraphQLNamedType: 
  JavaScriptReferencedObject, @unchecked Sendable, Hashable, CustomDebugStringConvertible, GraphQLNamedItem {
  public let name: GraphQLName

  public let documentation: String?

  required init(
    _ jsValue: JSValue,
    bridge: isolated JavaScriptBridge
  ) {
    self.name = .init(schemaName: jsValue["name"])
    self.documentation = jsValue["description"]
  }

  func finalize(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) { }

  /// Initializer to be used for creating mock objects in tests only.
  init(
    name: GraphQLName,
    documentation: String?
  ) {
    self.name = name
    self.documentation = documentation
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
    name.schemaName
  }
}

public final class GraphQLScalarType: GraphQLNamedType {

  public let specifiedByURL: String?

  public var isCustomScalar: Bool {
    guard self.specifiedByURL == nil else { return true }

    switch name.schemaName {
    case "String", "Int", "Float", "Boolean":
      return false
    default:
      return true
    }
  }

  required init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    self.specifiedByURL = jsValue["specifiedByUrl"]
    super.init(jsValue, bridge: bridge)
  }

  /// Initializer to be used for creating mock objects in tests only.
  init(
    name: GraphQLName,
    documentation: String?,
    specifiedByURL: String?
  ) {
    self.specifiedByURL = specifiedByURL
    super.init(name: name, documentation: documentation)
  }

}

public final class GraphQLEnumType: GraphQLNamedType {
  public private(set) var values: [GraphQLEnumValue]!

  required init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    super.init(jsValue, bridge: bridge)
  }

  override func finalize(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    self.values = try! bridge.invokeMethod("getValues", on: jsValue)
  }

  /// Initializer to be used for creating mock objects in tests only.
  init(
    name: GraphQLName,
    documentation: String?,
    values: [GraphQLEnumValue]
  ) {
    self.values = values
    super.init(name: name, documentation: documentation)
  }
}

public struct GraphQLEnumValue: JavaScriptObjectDecodable, GraphQLNamedItem {

  public let name: GraphQLName

  public let documentation: String?

  public let deprecationReason: String?

  public var isDeprecated: Bool { deprecationReason != nil }

  public init(
    name: GraphQLName,
    documentation: String?,
    deprecationReason: String?
  ) {
    self.name = name
    self.documentation = documentation
    self.deprecationReason = deprecationReason
  }

  static func fromJSValue(
    _ jsValue: JSValue,
    bridge: isolated JavaScriptBridge
  ) -> GraphQLEnumValue {
    self.init(
      name: .init(schemaName: jsValue["name"]),
      documentation: jsValue["description"],
      deprecationReason: jsValue["deprecationReason"]
    )
  }
}

public typealias GraphQLInputFieldDictionary = OrderedDictionary<String, GraphQLInputField>

public final class GraphQLInputObjectType: GraphQLNamedType {
  public private(set) var fields: GraphQLInputFieldDictionary!

  required init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    super.init(jsValue, bridge: bridge)
  }

  override func finalize(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    self.fields = try! bridge.invokeMethod("getFields", on: jsValue)
  }

  /// Initializer to be used for creating mock objects in tests only.
  init(
    name: GraphQLName,
    documentation: String?,
    fields: GraphQLInputFieldDictionary
  ) {
    self.fields = fields
    super.init(name: name, documentation: documentation)
  }
}

public class GraphQLInputField: JavaScriptObjectDecodable, GraphQLNamedItem {
  public let name: GraphQLName

  public let type: GraphQLType

  public let documentation: String?

  public let deprecationReason: String?

  public let defaultValue: GraphQLValue?

  static func fromJSValue(
    _ jsValue: JSValue,
    bridge: isolated JavaScriptBridge
  ) -> Self {
    self.init(
      name: .init(schemaName: jsValue["name"]),
      type: GraphQLType.fromJSValue(jsValue["type"], bridge: bridge),
      documentation: jsValue["description"],
      deprecationReason: jsValue["deprecationReason"],
      defaultValue: (jsValue["astNode"] as JSValue?)?["defaultValue"]
    )
  }

  required init(
    name: GraphQLName,
    type: GraphQLType,
    documentation: String?,
    deprecationReason: String?,
    defaultValue: GraphQLValue?
  ) {
    self.name = name
    self.type = type
    self.documentation = documentation
    self.deprecationReason = deprecationReason
    self.defaultValue = defaultValue
  }
}

public class GraphQLCompositeType: GraphQLNamedType {
  public override var debugDescription: String {
    "Type - \(name)"
  }
}

public protocol GraphQLInterfaceImplementingType: GraphQLCompositeType {
  var interfaces: [GraphQLInterfaceType]! { get }
}

public extension GraphQLInterfaceImplementingType {
  func implements(_ interface: GraphQLInterfaceType) -> Bool {
    interfaces.contains(interface)
  }
}

public final class GraphQLObjectType: GraphQLCompositeType, GraphQLInterfaceImplementingType {

  public private(set) var fields: [String: GraphQLField]!

  public private(set) var interfaces: [GraphQLInterfaceType]!

  /// Initializer to be used for creating mock objects in tests only.
  init(
    name: GraphQLName,
    documentation: String?,
    fields: [String: GraphQLField],
    interfaces: [GraphQLInterfaceType]
  ) {
    self.fields = fields
    self.interfaces = interfaces
    super.init(name: name, documentation: documentation)
  }

  required init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    super.init(jsValue, bridge: bridge)
  }

  override func finalize(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    self.fields = try! bridge.invokeMethod("getFields", on: jsValue)
    self.interfaces = try! bridge.invokeMethod("getInterfaces", on: jsValue)
  }

  public override var debugDescription: String {
    "Object - \(name)"
  }
}

public class GraphQLAbstractType: GraphQLCompositeType {
}

public final class GraphQLInterfaceType: GraphQLAbstractType, GraphQLInterfaceImplementingType {

  public private(set) var fields: [String: GraphQLField]!

  public private(set) var interfaces: [GraphQLInterfaceType]!

  /// Initializer to be used for creating mock objects in tests only.
  init(
    name: GraphQLName,
    documentation: String?,
    fields: [String: GraphQLField],
    interfaces: [GraphQLInterfaceType]
  ) {
    self.fields = fields
    self.interfaces = interfaces
    super.init(name: name, documentation: documentation)
  }

  required init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    super.init(jsValue, bridge: bridge)
  }

  override func finalize(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
    self.fields = try! bridge.invokeMethod("getFields", on: jsValue)
    self.interfaces = try! bridge.invokeMethod("getInterfaces", on: jsValue)
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

  /// Initializer to be used for creating mock objects in tests only.
  init(
    name: GraphQLName,
    documentation: String?,
    types: [GraphQLObjectType]
  ) {
    self.types = types
    super.init(name: name, documentation: documentation)
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
