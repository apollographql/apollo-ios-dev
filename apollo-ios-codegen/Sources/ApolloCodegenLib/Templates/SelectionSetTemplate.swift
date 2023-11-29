import InflectorKit
import OrderedCollections
import IR
import GraphQLCompiler
import TemplateString
import Utilities

struct SelectionSetTemplate {

  let definition: IR.Definition
  let generateInitializers: Bool
  let config: ApolloCodegen.ConfigurationContext
  let renderAccessControl: () -> String

  private let nameCache: SelectionSetNameCache

  var isMutable: Bool { definition.isMutable }

  init(
    definition: IR.Definition,
    generateInitializers: Bool,
    config: ApolloCodegen.ConfigurationContext,
    renderAccessControl: @autoclosure @escaping () -> String
  ) {
    self.definition = definition
    self.generateInitializers = generateInitializers
    self.config = config
    self.renderAccessControl = renderAccessControl

    self.nameCache = SelectionSetNameCache(config: config)
  }

  func renderBody() -> TemplateString {
    let computedRootSelectionSet = IR.ComputedSelectionSet.Builder(
      definition.rootField.selectionSet,
      entityStorage: definition.entityStorage
    ).build()
    return BodyTemplate(computedRootSelectionSet)
  }

  // MARK: - Child Entity
  func render(childEntity selectionSet: IR.ComputedSelectionSet) -> String {
    let fieldSelectionSetName = nameCache.selectionSetName(for: selectionSet.typeInfo)

    if let referencedSelectionSetName = selectionSet.nameForReferencedSelectionSet(config: config) {
      #warning("TODO: Test and implement `renderAccessControl()`")
      return "public typealias \(fieldSelectionSetName) = \(referencedSelectionSetName)"
    }

    return TemplateString(
    """
    \(SelectionSetNameDocumentation(selectionSet))
    \(renderAccessControl())\
    struct \(fieldSelectionSetName): \(SelectionSetType()) {
      \(BodyTemplate(selectionSet))
    }
    """
    ).description
  }

  // MARK: - Inline Fragment
  func render(inlineFragment: IR.ComputedSelectionSet) -> String {
    TemplateString(
    """
    \(SelectionSetNameDocumentation(inlineFragment))
    \(renderAccessControl())\
    struct \(inlineFragment.renderedTypeName): \(SelectionSetType(asInlineFragment: true))\
    \(if: inlineFragment.isCompositeSelectionSet, ", \(config.ApolloAPITargetName).CompositeInlineFragment")\
    \(if: inlineFragment.isDeferred, ", \(config.ApolloAPITargetName).Deferrable")\
     {
      \(BodyTemplate(inlineFragment))
    }
    """
    ).description
  }

  // MARK: - Selection Set Type
  private func SelectionSetType(asInlineFragment: Bool = false) -> TemplateString {
    let selectionSetTypeName: String
    switch (isMutable, asInlineFragment) {
    case (false, false):
      selectionSetTypeName = "SelectionSet"
    case (false, true):
      selectionSetTypeName = "InlineFragment"
    case (true, false):
      selectionSetTypeName = "MutableSelectionSet"
    case (true, true):
      selectionSetTypeName = "MutableInlineFragment"
    }

    return "\(config.schemaNamespace.firstUppercased).\(selectionSetTypeName)"
  }

  // MARK: - Selection Set Name Documentation
  func SelectionSetNameDocumentation(_ selectionSet: IR.ComputedSelectionSet) -> TemplateString {
    """
    /// \(SelectionSetNameGenerator.generatedSelectionSetName(
          for: selectionSet.typeInfo,
          format: .omittingRoot,
          pluralizer: config.pluralizer))
    \(if: config.options.schemaDocumentation == .include, """
      ///
      /// Parent Type: `\(selectionSet.typeInfo.parentType.formattedName)`
      """)
    """
  }

  // MARK: - Body
  func BodyTemplate(_ selectionSet: IR.ComputedSelectionSet) -> TemplateString {
    lazy var computedChildSelectionSets: [IR.ComputedSelectionSet] = {
      IteratorSequence(selectionSet.makeInlineFragmentIterator()).map {
        ComputedSelectionSet.Builder(
          $0.selectionSet,
          entityStorage: definition.entityStorage
        ).build()
      }
    }()
    return """
    \(DataPropertyTemplate())
    \(DesignatedInitializerTemplate())

    \(RootEntityTypealias(selectionSet))
    \(ParentTypeTemplate(selectionSet.parentType))
    \(ifLet: selectionSet.direct, { DirectSelectionsMetadataTemplate($0, scope: selectionSet.scope) })
    \(if: selectionSet.isCompositeInlineFragment, MergedSourcesTemplate(selectionSet.merged.mergedSources))

    \(section: FieldAccessorsTemplate(selectionSet))

    \(section: InlineFragmentAccessorsTemplate(computedChildSelectionSets))

    \(section: FragmentAccessorsTemplate(selectionSet))

    \(section: "\(if: generateInitializers, InitializerTemplate(selectionSet))")

    \(section: ChildEntityFieldSelectionSets(selectionSet))

    \(section: ChildTypeCaseSelectionSets(computedChildSelectionSets))
    """
  }

  private func DesignatedInitializerTemplate(
    _ propertiesTemplate: @autoclosure () -> TemplateString? = { nil }()
  ) -> String {
    let dataInitStatement = TemplateString("__data = _dataDict")

    return TemplateString("""
    \(renderAccessControl())init(_dataDict: DataDict) {\
    \(ifLet: propertiesTemplate(), where: { !$0.isEmpty }, {
      """

        \(dataInitStatement)
        \($0)

      """
    },
    else: " \(dataInitStatement) "
    )}
    """).description
  }

  private func DataPropertyTemplate() -> TemplateString {
    "\(renderAccessControl())\(isMutable ? "var" : "let") __data: DataDict"
  }

  private func RootEntityTypealias(_ selectionSet: IR.ComputedSelectionSet) -> TemplateString {
    guard !selectionSet.isEntityRoot else { return "" }
    let rootEntityName = SelectionSetNameGenerator.generatedSelectionSetName(
      for: selectionSet.typeInfo,
      to: selectionSet.scopePath.last.value.scopePath.head,
      format: .fullyQualified,
      pluralizer: config.pluralizer
    )

    return """
    \(renderAccessControl())typealias RootEntityType = \(rootEntityName)
    """
  }

  private func ParentTypeTemplate(_ type: GraphQLCompositeType) -> String {
    """
    \(renderAccessControl())\
    static var __parentType: \(config.ApolloAPITargetName).ParentType { \
    \(GeneratedSchemaTypeReference(type)) }
    """
  }

  private func MergedSourcesTemplate(
    _ mergedSources: OrderedSet<IR.MergedSelections.MergedSource>
  ) -> TemplateString {
    return """
    public static var __mergedSources: [any \(config.ApolloAPITargetName).SelectionSet.Type] { [
      \(mergedSources.map {
        let selectionSetName = SelectionSetNameGenerator.generatedSelectionSetName(
          for: $0,
          format: .fullyQualified,
          pluralizer: config.pluralizer
        )
        return "\(selectionSetName).self"
      })
    ] }
    """
  }

  private func GeneratedSchemaTypeReference(_ type: GraphQLCompositeType) -> TemplateString {
    "\(config.schemaNamespace.firstUppercased).\(type.schemaTypesNamespace).\(type.formattedName)"
  }

  // MARK: - Selections
  typealias DeprecatedArgument = (field: String, arg: String, reason: String)

  private func DirectSelectionsMetadataTemplate(
    _ selections: IR.DirectSelections.ReadOnly,
    scope: ScopeDescriptor
  ) -> TemplateString {
    let groupedSelections = selections.groupedByInclusionCondition

    var deprecatedArguments: [DeprecatedArgument]? =
    config.options.warningsOnDeprecatedUsage == .include ? [] : nil

    let selectionsTemplate = TemplateString("""
    \(renderAccessControl())\
    static var __selections: [\(config.ApolloAPITargetName).Selection] { [
      \(if: shouldIncludeTypenameSelection(for: scope), ".field(\"__typename\", String.self),")
      \(renderedSelections(groupedSelections.unconditionalSelections, &deprecatedArguments), terminator: ",")
      \(groupedSelections.inclusionConditionGroups.map {
        renderedConditionalSelectionGroup($0, $1, in: scope, &deprecatedArguments)
      }, terminator: ",")
    ] }
    """)
    return """
    \(if: deprecatedArguments != nil && !deprecatedArguments.unsafelyUnwrapped.isEmpty, """
      \(deprecatedArguments.unsafelyUnwrapped.map { """
        \(field: $0.field, argument: $0.arg, warningReason: $0.reason)
        """})
      """)
    \(selectionsTemplate)
    """

    func shouldIncludeTypenameSelection(for scope: IR.ScopeDescriptor) -> Bool {
      var isRootType: Bool {
        scope.allTypesInSchema.schemaRootTypes.allRootTypes.contains(scope.type)
      }
      return scope.scopePath.count == 1 && !isRootType
    }

    func renderedSelections(
      _ selections: IR.DirectSelections.ReadOnly,
      _ deprecatedArguments: inout [DeprecatedArgument]?
    ) -> [TemplateString] {
      selections.fields.values.map { FieldSelectionTemplate($0, &deprecatedArguments) } +
      selections.inlineFragments.values.map { InlineFragmentSelectionTemplate($0.selectionSet) } +
      selections.namedFragments.values.map { FragmentSelectionTemplate($0) }
    }

    func renderedConditionalSelectionGroup(
      _ conditions: AnyOf<IR.InclusionConditions>,
      _ selections: IR.DirectSelections.ReadOnly,
      in scope: IR.ScopeDescriptor,
      _ deprecatedArguments: inout [DeprecatedArgument]?
    ) -> TemplateString {
      let renderedSelections = renderedSelections(selections, &deprecatedArguments)
      guard !scope.matches(conditions) else {
        return "\(renderedSelections)"
      }

      let isSelectionGroup = renderedSelections.count > 1
      return """
    .include(if: \(conditions.conditionVariableExpression), \(if: isSelectionGroup, "[")\(list: renderedSelections, terminator: isSelectionGroup ? "," : nil)\(if: isSelectionGroup, "]"))
    """
    }
  }

  private func FieldSelectionTemplate(
    _ field: IR.Field,
    _ deprecatedArguments: inout [DeprecatedArgument]?
  ) -> TemplateString {
    """
    .field("\(field.name)"\
    \(ifLet: field.alias, {", alias: \"\($0)\""})\
    , \(typeName(for: field)).self\
    \(ifLet: field.arguments,
      where: { !$0.isEmpty }, { args in
        ", arguments: " + renderValue(for: args, onFieldNamed: field.name, &deprecatedArguments)
    })\
    )
    """
  }

  private func typeName(for field: IR.Field, forceOptional: Bool = false) -> String {
    let fieldName: String
    switch field {
    case let scalarField as IR.ScalarField:
      fieldName = scalarField.type.rendered(as: .selectionSetField(), config: config.config)

    case let entityField as IR.EntityField:
      fieldName = self.nameCache.selectionSetType(for: entityField)

    default:
      fatalError()
    }

    if case .nonNull = field.type, forceOptional {
      return "\(fieldName)?"
    } else {
      return fieldName
    }

  }

  private func renderValue(
    for arguments: [CompilationResult.Argument],
    onFieldNamed fieldName: String,
    _ deprecatedArguments: inout [DeprecatedArgument]?
  ) -> TemplateString {
    """
    [\(list: arguments.map { arg -> TemplateString in
      if let deprecationReason = arg.deprecationReason {
        deprecatedArguments?.append((field: fieldName, arg: arg.name, reason: deprecationReason))
      }
      return "\"\(arg.name)\": " + arg.value.renderInputValueLiteral()
    })]
    """
  }

  private func InlineFragmentSelectionTemplate(_ inlineFragment: IR.SelectionSet) -> TemplateString {
    if let deferCondition = inlineFragment.deferCondition {
      return DeferredInlineFragmentSelectionTemplate(deferCondition)

    } else {
      return """
      .inlineFragment(\(inlineFragment.renderedTypeName).self)
      """
    }
  }

  private func FragmentSelectionTemplate(_ fragment: IR.NamedFragmentSpread) -> TemplateString {
    """
    .fragment(\(fragment.definition.name.asFragmentName).self)
    """
  }

  private func DeferredInlineFragmentSelectionTemplate(
    _ deferCondition: CompilationResult.DeferCondition
  ) -> TemplateString {
    """
    .deferred(\
    \(ifLet: deferCondition.variable, { "if: \"\($0)\", " })\
    \(deferCondition.renderedTypeName).self, label: "\(deferCondition.label)")
    """
  }

  // MARK: - Accessors
  private func FieldAccessorsTemplate(
    _ selectionSet: ComputedSelectionSet
  ) -> TemplateString {
    let scope = selectionSet.typeInfo.scope
    return """
    \(ifLet: selectionSet.direct?.fields.values, {
      "\($0.map { FieldAccessorTemplate($0, in: scope) }, separator: "\n")"
      })
    \(selectionSet.merged.fields.values.map { FieldAccessorTemplate($0, in: scope) }, separator: "\n")
    """
  }

  private func FieldAccessorTemplate(
    _ field: IR.Field,
    in scope: IR.ScopeDescriptor
  ) -> TemplateString {
    return """
    \(documentation: field.underlyingField.documentation, config: config)
    \(deprecationReason: field.underlyingField.deprecationReason, config: config)
    \(renderAccessControl())var \(field.responseKey.renderAsFieldPropertyName(config: config.config)): \
    \(typeName(for: field, forceOptional: field.isConditionallyIncluded(in: scope))) {\
    \(if: isMutable,
      """

        get { __data["\(field.responseKey)"] }
        set { __data["\(field.responseKey)"] = newValue }
      }
      """, else:
      """
       __data["\(field.responseKey)"] }
      """)
    """
  }

  private func InlineFragmentAccessorsTemplate(
    _ inlineFragments: [ComputedSelectionSet]
  ) -> TemplateString {
    "\(inlineFragments.map(InlineFragmentAccessorTemplate(_:)), separator: "\n")"
  }

  private func InlineFragmentAccessorTemplate(_ inlineFragment: IR.ComputedSelectionSet) -> TemplateString {
    guard !inlineFragment.typeInfo.scope.isDeferred else { return "" }

    let typeName = inlineFragment.renderedTypeName
    return """
    \(renderAccessControl())var \(typeName.firstLowercased): \(typeName)? {\
    \(if: isMutable,
      """

        get { _asInlineFragment() }
        set { if let newData = newValue?.__data._data { __data._data = newData }}
      }
      """,
      else: " _asInlineFragment() }"
    )
    """
  }

  private func FragmentAccessorsTemplate(
    _ selectionSet: ComputedSelectionSet
  ) -> TemplateString {
    guard
      !(selectionSet.direct?.namedFragments.isEmpty ?? true)
      || !selectionSet.merged.namedFragments.isEmpty
      || (selectionSet.direct?.inlineFragments.containsDeferredFragment ?? false)
    else {
      return ""
    }

    let scope = selectionSet.typeInfo.scope

    return """
    \(renderAccessControl())struct Fragments: FragmentContainer {
      \(DataPropertyTemplate())
      \(FragmentInitializerTemplate(selectionSet))

      \(ifLet: selectionSet.direct?.namedFragments.values, {
        "\($0.map { NamedFragmentAccessorTemplate($0, in: scope) }, separator: "\n")"
      })
      \(selectionSet.merged.namedFragments.values.map {
        NamedFragmentAccessorTemplate($0, in: scope)
      }, separator: "\n")
      \(forEachIn: selectionSet.direct?.inlineFragments.values.elements ?? [], {
        "\(ifLet: $0.typeInfo.deferCondition, DeferredFragmentAccessorTemplate)"
      })
    }
    """
  }

  private func FragmentInitializerTemplate(
    _ selectionSet: ComputedSelectionSet
  ) -> String {
    if let inlineFragments = selectionSet.direct?.inlineFragments,
       inlineFragments.containsDeferredFragment {
      return DesignatedInitializerTemplate("""
      \(forEachIn: inlineFragments.values, {
        guard let deferCondition = $0.typeInfo.deferCondition else {
          return nil
        }
        return DeferredPropertyInitializationStatement(deferCondition)
      })
      """)

    } else {
      return DesignatedInitializerTemplate()
    }
  }

  private func DeferredPropertyInitializationStatement(
    _ deferCondition: CompilationResult.DeferCondition
  ) -> TemplateString {
    "_\(deferCondition.label) = Deferred(_dataDict: _dataDict)"
  }

  private func NamedFragmentAccessorTemplate(
    _ fragment: IR.NamedFragmentSpread,
    in scope: IR.ScopeDescriptor
  ) -> TemplateString {
    let name = fragment.definition.name
    let propertyName = name.firstLowercased
    let typeName = name.asFragmentName
    let isOptional = fragment.inclusionConditions != nil &&
    !scope.matches(fragment.inclusionConditions.unsafelyUnwrapped)

    return """
    \(renderAccessControl())var \(propertyName): \(typeName)\
    \(if: isOptional, "?") {\
    \(if: isMutable,
      """

        get { _toFragment() }
        _modify { var f = \(propertyName); yield &f; \(
          if: isOptional,
            "if let newData = f?.__data { __data = newData }",
          else: "__data = f.__data"
        ) }
        @available(*, unavailable, message: "mutate properties of the fragment instead.")
        set { preconditionFailure() }
      }
      """,
      else: " _toFragment() }"
    )
    """
  }

  private func DeferredFragmentAccessorTemplate(
    _ deferCondition: CompilationResult.DeferCondition
  ) -> TemplateString {
    "@Deferred public var \(deferCondition.label): \(deferCondition.renderedTypeName)?"
  }

  // MARK: - SelectionSet Initializer

  private func InitializerTemplate(
    _ selectionSet: ComputedSelectionSet
  ) -> TemplateString {
    return """
    \(renderAccessControl())init(
      \(InitializerSelectionParametersTemplate(selectionSet))
    ) {
      self.init(_dataDict: DataDict(
        data: [
          \(InitializerDataDictTemplate(selectionSet))
        ],
        fulfilledFragments: \(InitializerFulfilledFragments(selectionSet))
      ))
    }
    """
  }

  private func InitializerSelectionParametersTemplate(
    _ selectionSet: ComputedSelectionSet
  ) -> TemplateString {
    let isConcreteType = selectionSet.typeInfo.parentType is GraphQLObjectType
    let allFields = selectionSet.makeFieldIterator()

    return TemplateString("""
    \(if: !isConcreteType, "__typename: String\(if: !allFields.isEmpty, ",")")
    \(IteratorSequence(allFields).map({
      InitializerParameterTemplate($0, scope: selectionSet.typeInfo.scope)
    }))
    """
    )
  }

  private func InitializerParameterTemplate(
    _ field: IR.Field,
    scope: IR.ScopeDescriptor
  ) -> TemplateString {
    let isOptional: Bool = field.type.isNullable || field.isConditionallyIncluded(in: scope)
    return """
    \(field.responseKey.renderAsFieldPropertyName(config: config.config)): \(typeName(for: field, forceOptional: isOptional))\
    \(if: isOptional, " = nil")
    """
  }

  private func InitializerDataDictTemplate(
    _ selectionSet: ComputedSelectionSet
  ) -> TemplateString {
    let isConcreteType = selectionSet.typeInfo.parentType is GraphQLObjectType
    let allFields = selectionSet.makeFieldIterator()

    return TemplateString("""
    "__typename": \
    \(if: isConcreteType,
      "\(GeneratedSchemaTypeReference(selectionSet.typeInfo.parentType)).typename,",
      else: "__typename,")
    \(IteratorSequence(allFields).map(InitializerDataDictFieldTemplate(_:)), terminator: ",")
    """
    )
  }

  private func InitializerDataDictFieldTemplate(
    _ field: IR.Field
  ) -> TemplateString {
    let isEntityField: Bool = {
      switch field.type.innerType {
      case .entity: return true
      default: return false
      }
    }()

    return """
    "\(field.responseKey)": \(field.responseKey.renderAsFieldPropertyName(config: config.config))\
    \(if: isEntityField, "._fieldData")
    """
  }

  private func InitializerFulfilledFragments(
    _ selectionSet: ComputedSelectionSet
  ) -> TemplateString {
    var fulfilledFragments: OrderedSet<String> = []

    var currentNode = Optional(selectionSet.typeInfo.scopePath.last.value.scopePath.head)
    while let node = currentNode {
      defer { currentNode = node.next }

      let selectionSetName = SelectionSetNameGenerator.generatedSelectionSetName(
        for: selectionSet,
        to: node,
        format: .fullyQualified,
        pluralizer: config.pluralizer
      )

      fulfilledFragments.append(selectionSetName)
    }

    for source in selectionSet.merged.mergedSources {
      fulfilledFragments
        .append(contentsOf: source.generatedSelectionSetNamesOfFullfilledFragments(
          pluralizer: config.pluralizer
        ))
    }

    return """
    [
      \(fulfilledFragments.map { "ObjectIdentifier(\($0).self)" })
    ]
    """
  }

  // MARK: - Nested Selection Sets
  private func ChildEntityFieldSelectionSets(
    _ selectionSet: ComputedSelectionSet
  ) -> TemplateString {
    let allFields = selectionSet.makeFieldIterator { field in
      field is IR.EntityField
    }

    return """
    \(IteratorSequence(allFields).map { field in
      let field = unsafeDowncast(field, to: IR.EntityField.self)
      let computedSelectionSet = ComputedSelectionSet.Builder(
        field.selectionSet,
        entityStorage: definition.entityStorage
      ).build()
      return render(childEntity: computedSelectionSet)
    }, separator: "\n\n")
    """
  }

  private func ChildTypeCaseSelectionSets(
    _ inlineFragments: [ComputedSelectionSet]
  ) -> TemplateString {
    return """
    \(inlineFragments.map(render(inlineFragment:)), separator: "\n\n")
    """
  }

}

// MARK: - SelectionSet Name Computation

fileprivate class SelectionSetNameCache {
  private var generatedSelectionSetNames: [SelectionSet.TypeInfo: String] = [:]

  let config: ApolloCodegen.ConfigurationContext

  init(config: ApolloCodegen.ConfigurationContext) {
    self.config = config
  }

  func selectionSetName(for typeInfo: IR.SelectionSet.TypeInfo) -> String {
    if let name = generatedSelectionSetNames[typeInfo] { return name }

    let name = computeGeneratedSelectionSetName(for: typeInfo)
    generatedSelectionSetNames[typeInfo] = name
    return name
  }

  // MARK: Entity Field
  func selectionSetType(for field: IR.EntityField) -> String {
    field.type.rendered(
      as: .selectionSetField(),
      replacingNamedTypeWith: selectionSetName(for: field.selectionSet.typeInfo),
      config: config.config
    )
  }

  // MARK: Name Computation
  func computeGeneratedSelectionSetName(for typeInfo: IR.SelectionSet.TypeInfo) -> String {
    let location = typeInfo.entity.location
    return location.fieldPath?.last.value
      .formattedSelectionSetName(with: config.pluralizer) ??
    location.source.formattedSelectionSetName()
  }
  
}

// MARK: - ComputedSelectionSet Iteration

extension IR.ComputedSelectionSet {

  fileprivate typealias FieldIterator =
  SelectionsIterator<OrderedDictionary<String, IR.Field>.Values>

  fileprivate typealias InlineFragmentIterator =
  SelectionsIterator<OrderedDictionary<ScopeCondition, IR.InlineFragmentSpread>.Values>

  fileprivate typealias NamedFragmentIterator =
  SelectionsIterator<OrderedDictionary<String, IR.NamedFragmentSpread>.Values>

  fileprivate func makeFieldIterator(
    filter: ((IR.Field) -> Bool)? = nil
  ) -> FieldIterator {
    SelectionsIterator(
      direct: direct?.fields.values,
      merged: merged.fields.values,
      filter: filter
    )
  }

  fileprivate func makeInlineFragmentIterator(
    filter: ((IR.InlineFragmentSpread) -> Bool)? = nil
  ) -> InlineFragmentIterator {
    SelectionsIterator(
      direct: direct?.inlineFragments.values,
      merged: merged.inlineFragments.values,
      filter: filter
    )
  }

  fileprivate func makeNamedFragmentIterator(
    filter: ((IR.NamedFragmentSpread) -> Bool)? = nil
  ) -> NamedFragmentIterator {
    SelectionsIterator(
      direct: direct?.namedFragments.values,
      merged: merged.namedFragments.values,
      filter: filter
    )
  }

  fileprivate struct SelectionsIterator<SelectionCollection: Collection>: IteratorProtocol {
    typealias SelectionType = SelectionCollection.Element

    private let direct: SelectionCollection?
    private let merged: SelectionCollection
    private var directIterator: SelectionCollection.Iterator?
    private var mergedIterator: SelectionCollection.Iterator
    private let filter: ((SelectionType) -> Bool)?

    fileprivate init(
      direct: SelectionCollection?,
      merged: SelectionCollection,
      filter: ((SelectionType) -> Bool)?
    ) {
      self.direct = direct
      self.merged = merged
      self.directIterator = self.direct?.makeIterator()
      self.mergedIterator = self.merged.makeIterator()
      self.filter = filter
    }

    mutating func next() -> SelectionType? {
      guard let filter else {
        return directIterator?.next() ?? mergedIterator.next()
      }

      while let next = directIterator?.next() {
        if filter(next) { return next }
      }

      while let next = mergedIterator.next() {
        if filter(next) { return next }
      }

      return nil
    }

    var isEmpty: Bool {
      return (direct?.isEmpty ?? true) && merged.isEmpty
    }

  }

}

// MARK: - Helper Extensions

fileprivate extension IR.ComputedSelectionSet {

  var isCompositeSelectionSet: Bool {
    return direct?.isEmpty ?? true
  }

  var isCompositeInlineFragment: Bool {
    return !self.isEntityRoot && isCompositeSelectionSet
  }

  var shouldBeRendered: Bool {
    return direct != nil || merged.mergedSources.count != 1
  }

  /// If the SelectionSet is a reference to another rendered SelectionSet, returns the qualified
  /// name of the referenced SelectionSet.
  ///
  /// If `nil` the SelectionSet should be rendered by the template engine.
  ///
  /// If a value is returned, references to the selection set can point to another rendered
  /// selection set with the returned name.
  func nameForReferencedSelectionSet(config: ApolloCodegen.ConfigurationContext) -> String? {
    guard !shouldBeRendered else {
      return nil
    }

    return merged.mergedSources
      .first.unsafelyUnwrapped
      .generatedSelectionSetNamePath(
        from: typeInfo,
        pluralizer: config.pluralizer
      )
  }

}

fileprivate extension IR.SelectionSet.TypeInfo {

  var renderedTypeName: String {
    self.scope.scopePath.last.value.selectionSetNameComponent
  }

}

fileprivate extension IR.MergedSelections.MergedSource {

  func generatedSelectionSetNamePath(
    from targetTypeInfo: IR.SelectionSet.TypeInfo,
    pluralizer: Pluralizer
  ) -> String {
    if let fragment = fragment {
      return generatedSelectionSetNameForMergedEntity(
        in: fragment,
        pluralizer: pluralizer
      )
    }

    var targetTypePathCurrentNode = targetTypeInfo.scopePath.last
    var sourceTypePathCurrentNode = typeInfo.scopePath.last
    var nodesToSharedRoot = 0

    while targetTypePathCurrentNode.value == sourceTypePathCurrentNode.value {
      guard let previousFieldNode = targetTypePathCurrentNode.previous,
            let previousSourceNode = sourceTypePathCurrentNode.previous else {
              break
            }

      targetTypePathCurrentNode = previousFieldNode
      sourceTypePathCurrentNode = previousSourceNode
      nodesToSharedRoot += 1
    }

    /// If the shared root is the root of the definition, we should just generate the fully
    /// qualified name.
    if sourceTypePathCurrentNode.isHead {
      return SelectionSetNameGenerator.generatedSelectionSetName(
        for: self, format: .fullyQualified, pluralizer: pluralizer
      )
    }

    let sharedRootIndex =
      typeInfo.entity.location.fieldPath!.count - (nodesToSharedRoot + 1)

    /// We should remove the first component if the shared root is the previous scope and that
    /// scope is not the root of the entity.
    ///
    /// This is because the selection set will be a direct sibling of the current selection set.
    ///
    /// Example: The `height` field on `AllAnimals.AsPet` can reference the `AllAnimals.Height`
    /// object as just `Height`.
    let removeFirstComponent = nodesToSharedRoot <= 1

    let fieldPath = typeInfo.entity.location.fieldPath!.node(
      at: max(0, sharedRootIndex)
    )

    let selectionSetName = SelectionSetNameGenerator.generatedSelectionSetName(
      from: sourceTypePathCurrentNode,
      withFieldPath: fieldPath,
      removingFirst: removeFirstComponent,
      pluralizer: pluralizer
    )

    return selectionSetName
  }

  private func generatedSelectionSetNameForMergedEntity(
    in fragment: IR.NamedFragment,
    pluralizer: Pluralizer
  ) -> String {
    var selectionSetNameComponents: [String] = [fragment.generatedDefinitionName]

    let rootEntityScopePath = typeInfo.scopePath.head
    if let rootEntityTypeConditionPath = rootEntityScopePath.value.scopePath.head.next {
      selectionSetNameComponents.append(
        SelectionSetNameGenerator.ConditionPath.path(for: rootEntityTypeConditionPath)
      )
    }

    if let fragmentNestedTypePath = rootEntityScopePath.next {
      let fieldPath = typeInfo.entity.location
        .fieldPath!
        .head      

      selectionSetNameComponents.append(
        SelectionSetNameGenerator.generatedSelectionSetName(
          from: fragmentNestedTypePath,
          withFieldPath: fieldPath,
          pluralizer: pluralizer
        )
      )
    }

    return selectionSetNameComponents.joined(separator: ".")
  }

  func generatedSelectionSetNamesOfFullfilledFragments(
    pluralizer: Pluralizer
  ) -> [String] {
    let entityRootNameInFragment = SelectionSetNameGenerator
      .generatedSelectionSetName(
        for: self,
        to: typeInfo.scopePath.last.value.scopePath.head,
        format: .fullyQualified,
        pluralizer: pluralizer
      )

    var fulfilledFragments: [String] = [entityRootNameInFragment]

    var selectionSetNameComponents: [String] = [entityRootNameInFragment]

    var mergedFragmentEntityConditionPathNode = typeInfo.scopePath.last.value.scopePath.head
    while let node = mergedFragmentEntityConditionPathNode.next {
      defer {
        mergedFragmentEntityConditionPathNode = node
      }
      selectionSetNameComponents.append(
        node.value.selectionSetNameComponent
      )
      fulfilledFragments.append(selectionSetNameComponents.joined(separator: "."))
    }
    return fulfilledFragments
  }

}

fileprivate struct SelectionSetNameGenerator {

  enum Format {
    /// Fully qualifies the name of the selection set including the name of the enclosing
    /// operation or fragment.
    case fullyQualified
    /// Omits the root entity selection set name
    /// (ie. the name of the enclosing operation or fragment).
    case omittingRoot
  }

  static func generatedSelectionSetName(
    for selectionSet: ComputedSelectionSet,
    to toNode: LinkedList<IR.ScopeCondition>.Node? = nil,
    format: Format,
    pluralizer: Pluralizer
  ) -> String {
    generatedSelectionSetName(
      for: selectionSet.typeInfo,
      to: toNode,
      format: format,
      pluralizer: pluralizer
    )
  }

  static func generatedSelectionSetName(
    for mergedSource: IR.MergedSelections.MergedSource,
    to toNode: LinkedList<IR.ScopeCondition>.Node? = nil,
    format: Format,
    pluralizer: Pluralizer
  ) -> String {
    generatedSelectionSetName(
      for: mergedSource.typeInfo,
      to: toNode,
      format: format,
      pluralizer: pluralizer
    )
  }

  static func generatedSelectionSetName(
    for typeInfo: IR.SelectionSet.TypeInfo,
    to toNode: LinkedList<IR.ScopeCondition>.Node? = nil,
    format: Format,
    pluralizer: Pluralizer
  ) -> String {
    var components: [String] = []

    if case .fullyQualified = format {
      // The root entity, which represents the operation or fragment root, will use the fully
      // qualified name of the operation/fragment.
      let sourceName: String = {
        switch typeInfo.entity.location.source {
        case let .operation(operation):
          return "\(operation.generatedDefinitionName).Data"
        case let .namedFragment(fragment):
          return fragment.generatedDefinitionName
        }
      }()
      components.append(sourceName)
    }

    let entityFieldPath = SelectionSetNameGenerator.generatedSelectionSetName(
      from: typeInfo.scopePath.head,
      to: toNode,
      withFieldPath: typeInfo.entity.location.fieldPath?.head,
      pluralizer: pluralizer
    )
    if !entityFieldPath.isEmpty {
      components.append(entityFieldPath)
    }

    // Join all the computed components to get the fully qualified name.
    return components.joined(separator: ".")
  }

  static func generatedSelectionSetName(
    from typePathNode: LinkedList<IR.ScopeDescriptor>.Node,
    to endingNode: LinkedList<IR.ScopeCondition>.Node? = nil,
    withFieldPath fieldPathNode: IR.Entity.Location.FieldPath.Node?,
    removingFirst: Bool = false,
    pluralizer: Pluralizer
  ) -> String {
    // Set up starting nodes
    var currentTypePathNode = Optional(typePathNode)
    var currentConditionNode = Optional(typePathNode.value.scopePath.head)
    // Because the Location's field path starts on the first field (not the location's source),
    // If the typePath is starting from the root entity (ie. is the list's head node, we do not
    // start using the field path until the second entity node.
    var currentFieldPathNode: IR.Entity.Location.FieldPath.Node? =
    typePathNode.isHead ? nil : fieldPathNode

    func advanceToNextEntity() {
      // Set the current nodes to the root node of the next entity.
      currentTypePathNode = currentTypePathNode.unsafelyUnwrapped.next
      currentConditionNode = currentTypePathNode?.value.scopePath.head
      currentFieldPathNode = currentFieldPathNode?.next ?? fieldPathNode
    }

    var components: [String] = []

    iterateEntityScopes: repeat {
      // For the root node of the entity, we use the name of the field in the entity's field path.
      if let fieldName = currentFieldPathNode?.value
        .formattedSelectionSetName(with: pluralizer) {
        components.append(fieldName)
      }

      // If the ending node is the root of this entity, then we are done.
      // (We've already added the root of the entity to the components by using the fieldName)
      guard currentConditionNode !== endingNode else {
        break iterateEntityScopes
      }

      // If the current entity has conditions in it's scope path, we add those.
      currentConditionNode = currentTypePathNode.unsafelyUnwrapped.value.scopePath.head.next
      iterateConditionScopes: while currentConditionNode !== nil {
        let node = currentConditionNode.unsafelyUnwrapped

        components.append(node.value.selectionSetNameComponent)
        guard node !== endingNode else {
          break iterateEntityScopes
        }

        currentConditionNode = node.next
      }

      advanceToNextEntity()
    } while currentTypePathNode !== nil

    if removingFirst && !components.isEmpty { components.removeFirst() }

    return components.joined(separator: ".")
  }

  fileprivate struct ConditionPath {
    static func path(for conditions: LinkedList<IR.ScopeCondition>.Node) -> String {
      conditions.map(\.selectionSetNameComponent).joined(separator: ".")
    }
  }
}

fileprivate extension IR.ScopeCondition {

  var selectionSetNameComponent: String {
    if let deferCondition {
      return deferCondition.renderedTypeName

    } else {
      return TemplateString("""
      \(ifLet: type, { "As\($0.formattedName)" })\
      \(ifLet: conditions, { "If\($0.typeNameComponents)"})
      """).description
    }
  }
  
}

fileprivate extension AnyOf where T == IR.InclusionConditions {
  var conditionVariableExpression: TemplateString {
    """
    \(elements.map {
      $0.conditionVariableExpression(wrapInParenthesisIfMultiple: elements.count > 1)
    }, separator: " || ")
    """
  }
}

fileprivate extension IR.InclusionConditions {
  func conditionVariableExpression(wrapInParenthesisIfMultiple: Bool = false) -> TemplateString {
    let shouldWrap = wrapInParenthesisIfMultiple && count > 1
    return """
    \(if: shouldWrap, "(")\(map(\.conditionVariableExpression), separator: " && ")\(if: shouldWrap, ")")
    """
  }

  var typeNameComponents: TemplateString {
    """
    \(map(\.typeNameComponent), separator: "And")
    """
  }
}

fileprivate extension IR.InclusionCondition {
  var conditionVariableExpression: TemplateString {
    """
    \(if: isInverted, "!")"\(variable)"
    """
  }

  var typeNameComponent: TemplateString {
    """
    \(if: isInverted, "Not")\(variable.firstUppercased)
    """
  }
}

fileprivate extension IR.Field {
  var isCustomScalar: Bool {
    guard let scalar = self.type.namedType as? GraphQLScalarType else { return false }

    return scalar.isCustomScalar
  }

  func isConditionallyIncluded(in scope: IR.ScopeDescriptor) -> Bool {
    guard let conditions = self.inclusionConditions else { return false }
    return !scope.matches(conditions)
  }
}

fileprivate extension CompilationResult.DeferCondition {
  var renderedTypeName: String {
    self.label.convertToCamelCase().firstUppercased.asSelectionSetName
  }
}

fileprivate extension OrderedDictionary<ScopeCondition, InlineFragmentSpread> {
  var containsDeferredFragment: Bool {
    keys.contains(where: { $0.isDeferred })
  }
}
