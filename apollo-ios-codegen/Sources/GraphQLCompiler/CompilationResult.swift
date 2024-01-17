import JavaScriptCore
import TemplateString
import OrderedCollections

/// The output of the frontend compiler.
public final class CompilationResult: JavaScriptObjectDecodable {

  /// String constants used to match JavaScriptObject instances.
  fileprivate enum Constants {
    enum DirectiveNames {
      static let Import = "import"
      static let LocalCacheMutation = "apollo_client_ios_localCacheMutation"
      static let Defer = "defer"
    }
  }

  public let schemaRootTypes: RootTypeDefinition

  public let referencedTypes: [GraphQLNamedType]

  public let operations: [OperationDefinition]

  public let fragments: [FragmentDefinition]

  public let schemaDocumentation: String?

  init(
    schemaRootTypes: RootTypeDefinition,
    referencedTypes: [GraphQLNamedType],
    operations: [OperationDefinition],
    fragments: [FragmentDefinition],
    schemaDocumentation: String?
  ) {
    self.schemaRootTypes = schemaRootTypes
    self.referencedTypes = referencedTypes
    self.operations = operations
    self.fragments = fragments
    self.schemaDocumentation = schemaDocumentation
  }

  static func fromJSValue(
    _ jsValue: JSValue,
    bridge: isolated JavaScriptBridge
  ) -> Self {
    self.init(
      schemaRootTypes: .fromJSValue(jsValue["rootTypes"], bridge: bridge),
      referencedTypes: .fromJSValue(jsValue["referencedTypes"], bridge: bridge),
      operations: .fromJSValue(jsValue["operations"], bridge: bridge),
      fragments: .fromJSValue(jsValue["fragments"], bridge: bridge),
      schemaDocumentation: jsValue["schemaDocumentation"]
    )
  }

  public final class RootTypeDefinition: JavaScriptObjectDecodable {
    public let queryType: GraphQLNamedType

    public let mutationType: GraphQLNamedType?

    public let subscriptionType: GraphQLNamedType?

    public let allRootTypes: [GraphQLNamedType]

    init(
      queryType: GraphQLNamedType,
      mutationType: GraphQLNamedType?,
      subscriptionType: GraphQLNamedType?
    ) {
      self.queryType = queryType
      self.mutationType = mutationType
      self.subscriptionType = subscriptionType

      self.allRootTypes = [
        queryType,
        mutationType,
        subscriptionType
      ].compactMap { $0 }
    }

    static func fromJSValue(
      _ jsValue: JSValue,
      bridge: isolated JavaScriptBridge
    ) -> RootTypeDefinition {
      self.init(
        queryType: .fromJSValue(jsValue["queryType"], bridge: bridge),
        mutationType: .fromJSValue(jsValue["mutationType"], bridge: bridge),
        subscriptionType: .fromJSValue(jsValue["subscriptionType"], bridge: bridge)
      )
    }

  }
  
  public final class OperationDefinition: Sendable, JavaScriptObjectDecodable, Hashable {

    public let name: String

    public let operationType: OperationType

    public let variables: [VariableDefinition]

    public let rootType: GraphQLCompositeType

    public let selectionSet: SelectionSet

    public let directives: [Directive]?

    public let referencedFragments: [FragmentDefinition]

    public let source: String

    public let filePath: String

    public let isLocalCacheMutation: Bool
      
    public let moduleImports: OrderedSet<String>

    static func fromJSValue(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) -> Self {
      self.init(
        name: jsValue["name"],
        operationType: jsValue["operationType"],
        variables: .fromJSValue(jsValue["variables"], bridge: bridge),
        rootType: .fromJSValue(jsValue["rootType"], bridge: bridge),
        selectionSet: .fromJSValue(jsValue["selectionSet"], bridge: bridge),
        directives: .fromJSValue(jsValue["directives"], bridge: bridge),
        referencedFragments: .fromJSValue(jsValue["referencedFragments"], bridge: bridge),
        source: jsValue["source"],
        filePath: jsValue["filePath"]
      )
    }

    init(
      name: String,
      operationType: OperationType,
      variables: [VariableDefinition],
      rootType: GraphQLCompositeType,
      selectionSet: SelectionSet,
      directives: [Directive]?,
      referencedFragments: [FragmentDefinition],
      source: String,
      filePath: String
    ) {
      self.name = name
      self.operationType = operationType
      self.variables = variables
      self.rootType = rootType
      self.selectionSet = selectionSet
      self.directives = directives
      self.referencedFragments = referencedFragments
      self.source = source
      self.filePath = filePath
      self.isLocalCacheMutation = directives?
        .contains { $0.name == Constants.DirectiveNames.LocalCacheMutation } ?? false
   
      self.moduleImports = OperationDefinition.getImportModuleNames(directives: directives, 
                                                                    referencedFragments: referencedFragments)
    }

    public var debugDescription: String {
      "\(name) on \(rootType.debugDescription)"
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(name)
    }
    
    public static func ==(lhs: OperationDefinition, rhs: OperationDefinition) -> Bool {
      return lhs.name == rhs.name
    }
      
    private static func getImportModuleNames(directives: [Directive]?, 
                                             referencedFragments: [FragmentDefinition]) -> OrderedSet<String> {
      let referencedImports: [String] = referencedFragments
        .flatMap { $0.moduleImports }
      let directiveImports: [String] = directives?
        .compactMap { ImportDirective(directive: $0)?.moduleName } ?? []
      var ordered = OrderedSet(referencedImports + directiveImports)
      ordered.sort()
      return ordered
    }
  }
  
  public enum OperationType: String, Equatable, Sendable, JavaScriptValueDecodable {
    case query
    case mutation
    case subscription
    
    init(_ jsValue: JSValue) {
      let rawValue = String(jsValue)
      guard let operationType = Self(rawValue: rawValue) else {
        preconditionFailure("Unknown GraphQL operation type: \(rawValue)")
      }
      
      self = operationType
    }
  }
  
  public struct VariableDefinition: JavaScriptObjectDecodable, Sendable {
    public let name: String

    public let type: GraphQLType

    public let defaultValue: GraphQLValue?

    static func fromJSValue(
      _ jsValue: JSValue,
      bridge: isolated JavaScriptBridge
    ) -> CompilationResult.VariableDefinition {
      return self.init(
        name: jsValue["name"],
        type: GraphQLType.fromJSValue(jsValue["type"], bridge: bridge),
        defaultValue: jsValue["defaultValue"]
      )
    }
  }
  
  public final class FragmentDefinition:
    JavaScriptReferencedObject, Sendable, Hashable, CustomDebugStringConvertible {

    public let name: String

    public let type: GraphQLCompositeType

    public let selectionSet: SelectionSet

    public let directives: [Directive]?

    public let referencedFragments: [FragmentDefinition]

    public let source: String

    public let filePath: String

    public var isLocalCacheMutation: Bool {
      directives?.contains { $0.name == Constants.DirectiveNames.LocalCacheMutation } ?? false
    }
      
    public let moduleImports: OrderedSet<String>

    init(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) {
      self.name = jsValue["name"]
      self.directives = .fromJSValue(jsValue["directives"], bridge: bridge)
      self.type = .fromJSValue(jsValue["typeCondition"], bridge: bridge)
      self.selectionSet = .fromJSValue(jsValue["selectionSet"], bridge: bridge)
      self.referencedFragments = .fromJSValue(jsValue["referencedFragments"], bridge: bridge)
      self.source = jsValue["source"]
      self.filePath = jsValue["filePath"]
      self.moduleImports = FragmentDefinition.getImportModuleNames(directives: directives, 
                                                                   referencedFragments: referencedFragments)
    }

    /// Initializer to be used for creating mock objects in tests only.
    init(
      name: String,
      type: GraphQLCompositeType,
      selectionSet: SelectionSet,
      directives: [Directive]?,
      referencedFragments: [FragmentDefinition],
      source: String,
      filePath: String
    ) {
      self.name = name
      self.type = type
      self.selectionSet = selectionSet
      self.directives = directives
      self.referencedFragments = referencedFragments
      self.source = source
      self.filePath = filePath
      self.moduleImports = FragmentDefinition.getImportModuleNames(directives: directives,
                                                                   referencedFragments: referencedFragments)
    }

    public var debugDescription: String {
      "\(name) on \(type.debugDescription)"
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(name)
    }

    public static func ==(lhs: FragmentDefinition, rhs: FragmentDefinition) -> Bool {
      return lhs.name == rhs.name
    }
    
    private static func getImportModuleNames(directives: [Directive]?, 
                                             referencedFragments: [FragmentDefinition]) -> OrderedSet<String> {
      let referencedImports: [String] = referencedFragments
        .flatMap { $0.moduleImports }
      let directiveImports: [String] = directives?
        .compactMap { ImportDirective(directive: $0)?.moduleName } ?? []
            
      var ordered = OrderedSet(referencedImports + directiveImports)
      ordered.sort()
      return ordered
    }
  }
  
  public final class SelectionSet:
    JavaScriptObjectDecodable, Sendable, Hashable, CustomDebugStringConvertible {

    public let parentType: GraphQLCompositeType

    public let selections: [Selection]

    public init(
      parentType: GraphQLCompositeType,
      selections: [Selection] = []
    ) {
      self.parentType = parentType
      self.selections = selections
    }

    static func fromJSValue(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) -> Self {
      self.init(
        parentType: .fromJSValue(jsValue["parentType"], bridge: bridge),
        selections: .fromJSValue(jsValue["selections"], bridge: bridge)
      )
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

  public final class InlineFragment:
    JavaScriptObjectDecodable, Sendable, Hashable, CustomDebugStringConvertible, Deferrable {

    public let selectionSet: SelectionSet

    public let inclusionConditions: [InclusionCondition]?

    public let directives: [Directive]?

    public let deferCondition: DeferCondition?

    static func fromJSValue(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) -> Self {
      self.init(
        selectionSet: .fromJSValue(jsValue["selectionSet"], bridge: bridge),
        inclusionConditions: jsValue["inclusionConditions"],
        directives: .fromJSValue(jsValue["directives"], bridge: bridge)
      )
    }

    init(
      selectionSet: SelectionSet,
      inclusionConditions: [InclusionCondition]?,
      directives: [Directive]?
    ) {
      self.selectionSet = selectionSet
      self.inclusionConditions = inclusionConditions
      self.directives = directives
      self.deferCondition = Self.getDeferCondition(from: directives)
    }

    public var debugDescription: String {
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
  public final class FragmentSpread: JavaScriptObjectDecodable, Sendable, Hashable, CustomDebugStringConvertible, Deferrable {
    public let fragment: FragmentDefinition

    public let inclusionConditions: [InclusionCondition]?

    public let directives: [Directive]?

    public let deferCondition: DeferCondition?

    @inlinable public var parentType: GraphQLCompositeType { fragment.type }

    static func fromJSValue(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) -> Self {
      self.init(
        fragment: .fromJSValue(jsValue["fragment"], bridge: bridge),
        inclusionConditions: jsValue["inclusionConditions"],
        directives: .fromJSValue(jsValue["directives"], bridge: bridge)
      )
    }

    init(
      fragment: FragmentDefinition,
      inclusionConditions: [InclusionCondition]?,
      directives: [Directive]?
    ) {
      self.fragment = fragment
      self.inclusionConditions = inclusionConditions
      self.directives = directives
      self.deferCondition = Self.getDeferCondition(from: directives)
    }

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

    public var debugDescription: String {
      "...\(fragment.name)"
    }
  }
  
  public enum Selection:
    JavaScriptObjectDecodable, Sendable, CustomDebugStringConvertible, Hashable {
    case field(Field)
    case inlineFragment(InlineFragment)
    case fragmentSpread(FragmentSpread)
    
    static func fromJSValue(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) -> Self {
      precondition(jsValue.isObject, "Expected JavaScript object but found: \(jsValue)")

      let kind: String = jsValue["kind"].toString()

      switch kind {
      case "Field":
        return .field(Field.fromJSValue(jsValue, bridge: bridge))
      case "InlineFragment":
        return .inlineFragment(InlineFragment.fromJSValue(jsValue, bridge: bridge))
      case "FragmentSpread":
        return .fragmentSpread(FragmentSpread.fromJSValue(jsValue, bridge: bridge))
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
  
  public final class Field: JavaScriptObjectDecodable, Sendable, Hashable, CustomDebugStringConvertible {
    public let name: String

    public let alias: String?

    public let type: GraphQLType

    public let arguments: [Argument]?

    public let inclusionConditions: [InclusionCondition]?

    public let directives: [Directive]?

    public let selectionSet: SelectionSet?

    public let deprecationReason: String?

    public let documentation: String?

    public var responseKey: String {
      alias ?? name
    }

    public var isDeprecated: Bool {
      return deprecationReason != nil
    }

    public init(
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

    static func fromJSValue(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) -> Self {
      self.init(
        name: jsValue["name"],
        alias: jsValue["alias"],
        arguments: .fromJSValue(jsValue["arguments"], bridge: bridge),
        inclusionConditions: jsValue["inclusionConditions"],
        directives: .fromJSValue(jsValue["directives"], bridge: bridge),
        type: .fromJSValue(jsValue["type"], bridge: bridge),
        selectionSet: .fromJSValue(jsValue["selectionSet"], bridge: bridge),
        deprecationReason: jsValue["deprecationReason"],
        documentation: jsValue["description"]
      )
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
  
  public struct Argument:
    JavaScriptObjectDecodable, Sendable, Hashable {
    public let name: String

    public let type: GraphQLType

    public let value: GraphQLValue

    public let deprecationReason: String?

    static func fromJSValue(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) -> Self {
      self.init(
        name: jsValue["name"],
        type: .fromJSValue(jsValue["type"], bridge: bridge),
        value: jsValue["value"],
        deprecationReason: jsValue["deprecationReason"]
      )
    }

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

  public struct Directive:
    JavaScriptObjectDecodable, Sendable, Hashable, CustomDebugStringConvertible {
    public let name: String

    public let arguments: [Argument]?

    static func fromJSValue(_ jsValue: JSValue, bridge: isolated JavaScriptBridge) -> Self {
      self.init(
        name: jsValue["name"],
        arguments: .fromJSValue(jsValue["arguments"], bridge: bridge)
      )
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(name)
      hasher.combine(arguments)
    }

    public static func == (lhs: Directive, rhs: Directive) -> Bool {
      return lhs.name == rhs.name &&
      lhs.arguments == rhs.arguments
    }

    public var debugDescription: String {
      TemplateString("""
      "@\(name)\(ifLet: arguments, {
        "(\($0.map { "\($0.name): \(String(describing: $0.value))" }, separator: ","))"
        })
      """).description
    }
  }

  public enum InclusionCondition: JavaScriptValueDecodable, Sendable, Hashable {
    case included
    case skipped
    case variable(String, isInverted: Bool)

    init(_ jsValue: JSValue) {
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

  public struct DeferCondition: Hashable, CustomDebugStringConvertible, Sendable {
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
    
    fileprivate struct ImportDirective: Hashable, CustomDebugStringConvertible, Sendable, Equatable {
      /// String constants used to match JavaScriptObject instances.
      enum Constants {
          enum ArgumentNames {
            static let Module = "module"
          }
      }
        
      let moduleName: String
        
      init?(directive: Directive) {
        guard directive.name == CompilationResult.Constants.DirectiveNames.Import else {
          return nil
        }
        guard let moduleArgument = directive.arguments?.first(
            where: { $0.name == Constants.ArgumentNames.Module }),
          case let .string(moduleValue) = moduleArgument.value
        else {
          return nil
        }
        moduleName = moduleValue
      }
    
      var debugDescription: String {
        return "@import(module: \"\(moduleName)\")"
      }
    }
}

fileprivate protocol Deferrable { }

fileprivate extension Deferrable {
  static func getDeferCondition(
    from directives: [CompilationResult.Directive]?
  ) -> CompilationResult.DeferCondition? {
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
