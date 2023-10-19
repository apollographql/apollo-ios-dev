import JavaScriptCore
import TemplateString

/// The output of the frontend compiler.
public class CompilationResult: JavaScriptObject {
  /// String constants used to match JavaScriptObject instances.
  fileprivate enum Constants {
    enum DirectiveNames {
      static let LocalCacheMutation = "apollo_client_ios_localCacheMutation"
      static let Defer = "defer"
    }
  }

  public lazy var rootTypes: RootTypeDefinition = self["rootTypes"]
  
  public lazy var referencedTypes: [GraphQLNamedType] = self["referencedTypes"]

  public lazy var operations: [OperationDefinition] = self["operations"]

  public lazy var fragments: [FragmentDefinition] = self["fragments"]

  public lazy var schemaDocumentation: String? = self["schemaDocumentation"]
  
  public class RootTypeDefinition: JavaScriptObject {
    public lazy var queryType: GraphQLNamedType = self["queryType"]
    
    public lazy var mutationType: GraphQLNamedType? = self["mutationType"]
    
    public lazy var subscriptionType: GraphQLNamedType? = self["subscriptionType"]
  }
  
  public class OperationDefinition: JavaScriptObject, Hashable {
    public lazy var name: String = self["name"]
    
    public lazy var operationType: OperationType = self["operationType"]
    
    public lazy var variables: [VariableDefinition] = self["variables"]
    
    public lazy var rootType: GraphQLCompositeType = self["rootType"]
    
    public lazy var selectionSet: SelectionSet = self["selectionSet"]

    public lazy var directives: [Directive]? = self["directives"]

    public lazy var referencedFragments: [FragmentDefinition] = self["referencedFragments"]

    public lazy var source: String = self["source"]
    
    public lazy var filePath: String = self["filePath"]

    override public var debugDescription: String {
      "\(name) on \(rootType.debugDescription)"
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(name)
    }
    
    public static func ==(lhs: OperationDefinition, rhs: OperationDefinition) -> Bool {
      return lhs.name == rhs.name
    }

    public lazy var isLocalCacheMutation: Bool = {
      directives?.contains { $0.name == Constants.DirectiveNames.LocalCacheMutation } ?? false
    }()
  }
  
  public enum OperationType: String, Equatable, JavaScriptValueDecodable {
    case query
    case mutation
    case subscription
    
    init(_ jsValue: JSValue, bridge: JavaScriptBridge) {
      let rawValue: String = .fromJSValue(jsValue, bridge: bridge)
      guard let operationType = Self(rawValue: rawValue) else {
        preconditionFailure("Unknown GraphQL operation type: \(rawValue)")
      }
      
      self = operationType
    }
  }
  
  public class VariableDefinition: JavaScriptObject {
    public lazy var name: String = self["name"]
    
    public lazy var type: GraphQLType = self["type"]
    
    public lazy var defaultValue: GraphQLValue? = self["defaultValue"]
  }
  
  public class FragmentDefinition: JavaScriptObject, Hashable {
    public lazy var name: String = self["name"]
    
    public lazy var type: GraphQLCompositeType = self["typeCondition"]
    
    public lazy var selectionSet: SelectionSet = self["selectionSet"]
    
    public lazy var source: String = self["source"]
    
    public lazy var filePath: String = self["filePath"]

    public lazy var directives: [Directive]? = self["directives"]

    public lazy var referencedFragments: [FragmentDefinition] = self["referencedFragments"]

    public lazy var isLocalCacheMutation: Bool = {
      directives?.contains { $0.name == Constants.DirectiveNames.LocalCacheMutation } ?? false
    }()

    public override var debugDescription: String {
      "\(name) on \(type.debugDescription)"
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(name)
    }

    public static func ==(lhs: FragmentDefinition, rhs: FragmentDefinition) -> Bool {
      return lhs.name == rhs.name
    }
  }
  
  public class SelectionSet: JavaScriptWrapper, Hashable, CustomDebugStringConvertible {
    public lazy var parentType: GraphQLCompositeType = self["parentType"]
    
    public lazy var selections: [Selection] = self["selections"]

    public required convenience init(
      parentType: GraphQLCompositeType,
      selections: [Selection] = []
    ) {
      self.init(nil)
      self.parentType = parentType
      self.selections = selections
    }

    public var debugDescription: String {
      TemplateString("""
      ... on \(parentType.debugDescription) {
        \(selections.map(\.debugDescription), separator: "\n")
      }
      """).description
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(parentType)
      hasher.combine(selections)
    }

    public static func ==(lhs: SelectionSet, rhs: SelectionSet) -> Bool {
      return lhs.parentType == rhs.parentType &&
      lhs.selections == rhs.selections
    }
  }

  public class InlineFragment: JavaScriptObject, Hashable, Deferrable {
    public lazy var selectionSet: SelectionSet = self["selectionSet"]

    public lazy var inclusionConditions: [InclusionCondition]? = self["inclusionConditions"]

    lazy var directives: [Directive]? = self["directives"]

    public lazy var deferCondition: DeferCondition? = getDeferCondition()

    public override var debugDescription: String {
      selectionSet.debugDescription
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(selectionSet)
      hasher.combine(inclusionConditions)
    }

    public static func ==(lhs: InlineFragment, rhs: InlineFragment) -> Bool {
      return lhs.selectionSet == rhs.selectionSet &&
      lhs.inclusionConditions == rhs.inclusionConditions
    }
  }

  /// Represents an individual selection that includes a named fragment in a selection set.
  /// (ie. `...FragmentName`)
  public class FragmentSpread: JavaScriptObject, Hashable, Deferrable {

    public lazy var fragment: FragmentDefinition = self["fragment"]

    public lazy var inclusionConditions: [InclusionCondition]? = self["inclusionConditions"]

    public lazy var directives: [Directive]? = self["directives"]

    public lazy var deferCondition: DeferCondition? = getDeferCondition()

    @inlinable public var parentType: GraphQLCompositeType { fragment.type }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(fragment)
      hasher.combine(inclusionConditions)
      hasher.combine(directives)
    }

    public static func ==(lhs: FragmentSpread, rhs: FragmentSpread) -> Bool {
      return lhs.fragment == rhs.fragment &&
      lhs.inclusionConditions == rhs.inclusionConditions &&
      lhs.directives == rhs.directives
    }
  }
  
  public enum Selection: JavaScriptValueDecodable, CustomDebugStringConvertible, Hashable {
    case field(Field)
    case inlineFragment(InlineFragment)
    case fragmentSpread(FragmentSpread)
    
    init(_ jsValue: JSValue, bridge: JavaScriptBridge) {
      precondition(jsValue.isObject, "Expected JavaScript object but found: \(jsValue)")

      let kind: String = jsValue["kind"].toString()

      switch kind {
      case "Field":
        self = .field(Field(jsValue, bridge: bridge))
      case "InlineFragment":
        self = .inlineFragment(InlineFragment(jsValue, bridge: bridge))
      case "FragmentSpread":
        self = .fragmentSpread(FragmentSpread(jsValue, bridge: bridge))
      default:
        preconditionFailure("""
          Unknown GraphQL selection of kind "\(kind)"
          """)
      }
    }

    public var selectionSet: SelectionSet? {
      switch self {
      case let .field(field): return field.selectionSet
      case let .inlineFragment(inlineFragment): return inlineFragment.selectionSet
      case let .fragmentSpread(fragmentSpread): return fragmentSpread.fragment.selectionSet
      }
    }

    public var debugDescription: String {
      switch self {
      case let .field(field):
        return "field - " + field.debugDescription
      case let .inlineFragment(fragment):
        return "inlineFragment - " + fragment.debugDescription
      case let .fragmentSpread(fragment):
        return "fragment - " + fragment.debugDescription
      }
    }
  }
  
  public class Field: JavaScriptWrapper, Hashable, CustomDebugStringConvertible {
    public lazy var name: String = self["name"]!
    
    public lazy var alias: String? = self["alias"]
    
    public var responseKey: String {
      alias ?? name
    }
    
    public lazy var type: GraphQLType = self["type"]!

    public lazy var arguments: [Argument]? = self["arguments"]

    public lazy var inclusionConditions: [InclusionCondition]? = self["inclusionConditions"]

    public lazy var directives: [Directive]? = self["directives"]
    
    public lazy var selectionSet: SelectionSet? = self["selectionSet"]
    
    public lazy var deprecationReason: String? = self["deprecationReason"]
    
    public var isDeprecated: Bool {
      return deprecationReason != nil
    }
    
    public lazy var documentation: String? = self["description"]

    public required convenience init(
      name: String,
      alias: String? = nil,
      arguments: [Argument]? = nil,
      inclusionConditions: [InclusionCondition]? = nil,
      directives: [Directive]? = nil,
      type: GraphQLType,
      selectionSet: SelectionSet? = nil,
      deprecationReason: String? = nil,
      documentation: String? = nil
    ) {
      self.init(nil)
      self.name = name
      self.alias = alias
      self.type = type
      self.arguments = arguments
      self.inclusionConditions = inclusionConditions
      self.directives = directives
      self.selectionSet = selectionSet
      self.deprecationReason = deprecationReason
      self.documentation = documentation
    }

    public var debugDescription: String {
      TemplateString("""
      \(name): \(type.debugDescription)\(ifLet: directives, {
          " \($0.map{"\($0.debugDescription)"}, separator: " ")"
        })
      """).description
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(name)
      hasher.combine(alias)
      hasher.combine(type)
      hasher.combine(arguments)
      hasher.combine(directives)
      hasher.combine(selectionSet)
    }

    public static func ==(lhs: Field, rhs: Field) -> Bool {
      return lhs.name == rhs.name &&
      lhs.alias == rhs.alias &&
      lhs.type == rhs.type &&
      lhs.arguments == rhs.arguments &&
      lhs.directives == rhs.directives &&
      lhs.selectionSet == rhs.selectionSet
    }
  }
  
  public class Argument: JavaScriptObject, Hashable {
    public lazy var name: String = self["name"]

    public lazy var type: GraphQLType = self["type"]

    public lazy var value: GraphQLValue = self["value"]

    public lazy var deprecationReason: String? = self["deprecationReason"]

    public func hash(into hasher: inout Hasher) {
      hasher.combine(name)
      hasher.combine(type)
      hasher.combine(value)
    }

    public static func ==(lhs: Argument, rhs: Argument) -> Bool {
      return lhs.name == rhs.name &&
      lhs.type == rhs.type &&
      lhs.value == rhs.value
    }
  }

  public class Directive: JavaScriptObject, Hashable {
    public lazy var name: String = self["name"]

    public lazy var arguments: [Argument]? = self["arguments"]

    public func hash(into hasher: inout Hasher) {
      hasher.combine(name)
      hasher.combine(arguments)
    }

    public static func == (lhs: Directive, rhs: Directive) -> Bool {
      return lhs.name == rhs.name &&
      lhs.arguments == rhs.arguments
    }

    public override var debugDescription: String {
      TemplateString("""
      "@\(name)\(ifLet: arguments, {
        "(\($0.map { "\($0.name): \(String(describing: $0.value))" }, separator: ","))"
        })
      """).description
    }
  }

  public enum InclusionCondition: JavaScriptValueDecodable, Hashable {
    case included
    case skipped
    case variable(String, isInverted: Bool)

    init(_ jsValue: JSValue, bridge: JavaScriptBridge) {
      if jsValue.isString, let value = jsValue.toString() {
        switch value {
        case "INCLUDED":
          self = .included
          return
        case "SKIPPED":
          self = .skipped
          return
        default:
          preconditionFailure("Unrecognized value for include condition. Got \(value)")
        }
      }

      precondition(jsValue.isObject, "Expected JavaScript object but found: \(jsValue)")

      self = .variable(jsValue["variable"].toString(), isInverted: jsValue["isInverted"].toBool())
    }

    public static func include(if variable: String) -> Self {
      .variable(variable, isInverted: false)
    }

    public static func skip(if variable: String) -> Self {
      .variable(variable, isInverted: true)
    }
  }

  public struct DeferCondition: Hashable, CustomDebugStringConvertible {
    /// String constants used to match JavaScriptObject instances.
    fileprivate enum Constants {
      enum ArgumentNames {
        static let Label = "label"
        static let `If` = "if"
      }
    }

    public let label: String
    public let variable: String?

    public init(label: String, variable: String? = nil) {
      self.label = label
      self.variable = variable
    }

    public var debugDescription: String {
      var string = "Defer \"\(label)\""
      if let variable {
        string += " - if \"\(variable)\""
      }

      return string
    }
  }

}

fileprivate protocol Deferrable {
  var directives: [CompilationResult.Directive]? { get }
}

fileprivate extension Deferrable where Self: JavaScriptObject {
  func getDeferCondition() -> CompilationResult.DeferCondition? {
    guard let directive = directives?.first(
      where: { $0.name == CompilationResult.Constants.DirectiveNames.Defer }
    ) else {
      return nil
    }

    guard
      let labelArgument = directive.arguments?.first(
        where: { $0.name == CompilationResult.DeferCondition.Constants.ArgumentNames.Label }),
      case let .string(labelValue) = labelArgument.value
    else {
      preconditionFailure("Incorrect `label` argument. Either missing or value is not a String.")
    }

    guard let variableArgument = directive.arguments?.first(
      where: { $0.name == CompilationResult.DeferCondition.Constants.ArgumentNames.If }
    ) else {
      return .init(label: labelValue)
    }

    switch (variableArgument.value) {
    case let .boolean(value):
      if value {
        return .init(label: labelValue)
      } else {
        return nil
      }

    case let .string(value), let .variable(value):
      return .init(label: labelValue, variable: value)

    default:
      preconditionFailure("""
        Incompatible variable value. Expected Boolean, String or Variable,
        got \(variableArgument.value).
        """)
    }
  }
}
