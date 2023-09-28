import JavaScriptCore
import OrderedCollections

// These classes correspond directly to the ones in
// https://github.com/graphql/graphql-js/tree/master/src/type
// and are partially described in https://graphql.org/graphql-js/type/

/// A GraphQL schema.
public class GraphQLSchema: JavaScriptObject {  
  func getType(named typeName: String) throws -> GraphQLNamedType? {
    try invokeMethod("getType", with: typeName)
  }
  
  func getPossibleTypes(_ abstractType: GraphQLAbstractType) throws -> [GraphQLObjectType] {
    return try invokeMethod("getPossibleTypes", with: abstractType)
  }
  
  func getImplementations(interfaceType: GraphQLInterfaceType) throws -> InterfaceImplementations {
    return try invokeMethod("getImplementations", with: interfaceType)
  }
  
  class InterfaceImplementations: JavaScriptObject {
    private(set) lazy var objects: [GraphQLObjectType] = self["objects"]
    private(set) lazy var interfaces: [GraphQLInterfaceType] = self["interfaces"]
  }
    
  func isSubType(abstractType: GraphQLAbstractType, maybeSubType: GraphQLNamedType) throws -> Bool {
    return try invokeMethod("isSubType", with: abstractType, maybeSubType)
  }
}

public class GraphQLNamedType: JavaScriptObject, Hashable {
  public lazy var name: String = self["name"]

  public lazy var documentation: String? = self["description"]

  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
  }

  public static func ==(lhs: GraphQLNamedType, rhs: GraphQLNamedType) -> Bool {
    return lhs.name == rhs.name
  }
}

public class GraphQLScalarType: GraphQLNamedType {
  public lazy var specifiedByURL: String? = self["specifiedByUrl"]

  public var isCustomScalar: Bool {
    guard self.specifiedByURL == nil else { return true }

    switch name {
    case "String", "Int", "Float", "Boolean", "ID":
      return false
    default:
      return true
    }
  }
}

public class GraphQLEnumType: GraphQLNamedType {
  public lazy var values: [GraphQLEnumValue] = try! invokeMethod("getValues")
}

public class GraphQLEnumValue: JavaScriptObject {

  public struct Name {
    public let value: String

    public init(value: String) {
      self.value = value
    }
  }

  public lazy var name: Name = Name(value: self["name"])
  
  public lazy var documentation: String? = self["description"]
    
  public lazy var deprecationReason: String? = self["deprecationReason"]

  public var isDeprecated: Bool { deprecationReason != nil }
}

public typealias GraphQLInputFieldDictionary = OrderedDictionary<String, GraphQLInputField>

public class GraphQLInputObjectType: GraphQLNamedType {
  public lazy var fields: GraphQLInputFieldDictionary = try! invokeMethod("getFields")
}

public class GraphQLInputField: JavaScriptObject {
  public lazy var name: String = self["name"]
  
  public lazy var type: GraphQLType = self["type"]
  
  public lazy var documentation: String? = self["description"]
  
  public lazy var defaultValue: GraphQLValue? = {
    let node: JavaScriptObject? = self["astNode"]
    return node?["defaultValue"]
  }()
    
  public lazy var deprecationReason: String? = self["deprecationReason"]
}

public class GraphQLCompositeType: GraphQLNamedType {
  public override var debugDescription: String {
    "Type - \(name)"
  }

  public var isRootFieldType: Bool = false
  
}

public protocol GraphQLInterfaceImplementingType: GraphQLCompositeType {
  var interfaces: [GraphQLInterfaceType] { get }
}

public extension GraphQLInterfaceImplementingType {
  func implements(_ interface: GraphQLInterfaceType) -> Bool {
    interfaces.contains(interface)
  }
}

public class GraphQLObjectType: GraphQLCompositeType, GraphQLInterfaceImplementingType {
  public lazy var fields: [String: GraphQLField] = try! invokeMethod("getFields")
  
  public lazy var interfaces: [GraphQLInterfaceType] = try! invokeMethod("getInterfaces")

  public override var debugDescription: String {
    "Object - \(name)"
  }
}

public class GraphQLAbstractType: GraphQLCompositeType {
}

public class GraphQLInterfaceType: GraphQLAbstractType, GraphQLInterfaceImplementingType {  
  public lazy var deprecationReason: String? = self["deprecationReason"]
  
  public lazy var fields: [String: GraphQLField] = try! invokeMethod("getFields")
  
  public lazy var interfaces: [GraphQLInterfaceType] = try! invokeMethod("getInterfaces")

  public override var debugDescription: String {
    "Interface - \(name)"
  }
}

public class GraphQLUnionType: GraphQLAbstractType {
  public lazy var types: [GraphQLObjectType] = try! invokeMethod("getTypes")

  public override var debugDescription: String {
    "Union - \(name)"
  }
}

public class GraphQLField: JavaScriptObject, Hashable {

  public lazy var name: String = self["name"]
  
  public lazy var type: GraphQLType = self["type"]

  public lazy var arguments: [GraphQLFieldArgument] = self["args"]
  
  public lazy var documentation: String? = self["description"]
  
  public lazy var deprecationReason: String? = self["deprecationReason"]

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

  public override var debugDescription: String {
    "\(name): \(type.debugDescription)"
  }
}

public class GraphQLFieldArgument: JavaScriptObject, Hashable {

  public lazy var name: String = self["name"]

  public lazy var type: GraphQLType = self["type"]

  public lazy var documentation: String? = self["description"]

  public lazy var deprecationReason: String? = self["deprecationReason"]

  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
    hasher.combine(type)
  }

  public static func == (lhs: GraphQLFieldArgument, rhs: GraphQLFieldArgument) -> Bool {
    lhs.name == rhs.name &&
    lhs.type == rhs.type
  }
  
}
