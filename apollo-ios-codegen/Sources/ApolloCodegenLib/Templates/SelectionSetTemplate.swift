import GraphQLCompiler
import IR
import InflectorKit
import OrderedCollections
import TemplateString
import Utilities

struct SelectionSetTemplate {

  let definition: any IR.Definition
  let generateInitializers: Bool
  let config: ApolloCodegen.ConfigurationContext
  let nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  let renderAccessControl: () -> String

  private let nameCache: SelectionSetNameCache

  var isMutable: Bool { definition.isMutable }

  init(
    definition: any IR.Definition,
    generateInitializers: Bool,
    config: ApolloCodegen.ConfigurationContext,
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder,
    renderAccessControl: @autoclosure @escaping () -> String
  ) {
    self.definition = definition
    self.generateInitializers = generateInitializers
    self.config = config
    self.nonFatalErrorRecorder = nonFatalErrorRecorder
    self.renderAccessControl = renderAccessControl

    self.nameCache = SelectionSetNameCache(config: config)
  }

  // MARK: - SelectionSetContext

  struct SelectionSetContext {
    let selectionSet: IR.ComputedSelectionSet
    let validationContext: SelectionSetValidationContext
  }

  private func createSelectionSetContext(
    for selectionSet: IR.SelectionSet,
    inParent context: SelectionSetContext?
  ) -> SelectionSetContext {
    let computedSelectionSet = ComputedSelectionSet.Builder(
      selectionSet,
      mergingStrategy: self.config.experimentalFeatures.fieldMerging.options,
      entityStorage: definition.entityStorage
    ).build()

    var validationContext = context?.validationContext ??
    SelectionSetValidationContext(config: config)

    validationContext.runTypeValidationFor(
      computedSelectionSet,
      recordingErrorsTo: nonFatalErrorRecorder
    )

    return SelectionSetContext(
      selectionSet: computedSelectionSet,
      validationContext: validationContext
    )
  }

  /// MARK: - Render Body

  /// Renders the body of the SelectionSet template for the entire `definition` including all
  /// nested child selection sets.
  ///
  /// Errors that occur during rendering will be recorded to the `nonFatalErrorRecorder`
  /// If any `NonFatalErrors` are recorded, the generated file will likely
  /// not compile correctly. Code generation execution can continue, but these errors should be
  /// surfaced to the user.
  ///
  /// - Returns: The `TemplateString` for the body of the `SelectionSetTemplate`.
  func renderBody() -> TemplateString {
    let selectionSetContext = createSelectionSetContext(
      for: definition.rootField.selectionSet,
      inParent: nil
    )

    let body = BodyTemplate(selectionSetContext)

    return body
  }

  // MARK: - Child Entity
  func render(childEntity context: SelectionSetContext) -> String? {
    let selectionSet = context.selectionSet

    let fieldSelectionSetName = nameCache.selectionSetName(for: selectionSet.typeInfo)

    if let referencedSelectionSetName = selectionSet.nameForReferencedSelectionSet(config: config) {
      guard referencedSelectionSetName != fieldSelectionSetName else { return nil }
      return
        "\(renderAccessControl())typealias \(fieldSelectionSetName) = \(referencedSelectionSetName)"
    }

    return TemplateString(
      """
      \(SelectionSetNameDocumentation(selectionSet))
      \(renderAccessControl())\
      struct \(fieldSelectionSetName): \(SelectionSetType())\
      \(if: selectionSet.isIdentifiable, ", Identifiable")\
       {
        \(BodyTemplate(context))
      }
      """
    ).description
  }

  // MARK: - Inline Fragment
  func render(inlineFragment context: SelectionSetContext) -> String {
    let inlineFragment = context.selectionSet
    return TemplateString(
      """
      \(SelectionSetNameDocumentation(inlineFragment))
      \(renderAccessControl())\
      struct \(inlineFragment.renderedTypeName): \(SelectionSetType(asInlineFragment: true))\
      \(if: inlineFragment.isCompositeInlineFragment, ", \(TemplateConstants.ApolloAPITargetName).CompositeInlineFragment")\
      \(if: inlineFragment.isIdentifiable, ", Identifiable")\
       {
        \(BodyTemplate(context))
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
      /// Parent Type: `\(selectionSet.typeInfo.parentType.render(as: .typename))`
      """)
    """
  }

  // MARK: - Body
  func BodyTemplate(_ context: SelectionSetContext) -> TemplateString {
    lazy var computedChildSelectionSets: [SelectionSetContext] = {
      IteratorSequence(context.selectionSet.makeInlineFragmentIterator()).map {
        createSelectionSetContext(for: $0.selectionSet, inParent: context)
      }
    }()
    let selectionSet = context.selectionSet

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

      \(section: ChildEntityFieldSelectionSets(context))

      \(section: ChildTypeCaseSelectionSets(computedChildSelectionSets))
      """
  }

  private func DesignatedInitializerTemplate(
    _ propertiesTemplate: @autoclosure () -> TemplateString? = { nil }()
  ) -> String {
    let dataInitStatement = TemplateString("__data = _dataDict")

    return TemplateString(
      """
      \(renderAccessControl())init(_dataDict: DataDict) {\
      \(ifLet: propertiesTemplate(), where: { !$0.isEmpty }, {
        """

          \(dataInitStatement)
          \($0)

        """
      },
        else: " \(dataInitStatement) "
      )}
      """
    ).description
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
    static var __parentType: any \(TemplateConstants.ApolloAPITargetName).ParentType { \
    \(GeneratedSchemaTypeReference(type)) }
    """
  }

  private func MergedSourcesTemplate(
    _ mergedSources: OrderedSet<IR.MergedSelections.MergedSource>
  ) -> TemplateString {
    return """
      public static var __mergedSources: [any \(TemplateConstants.ApolloAPITargetName).SelectionSet.Type] { [
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
    "\(config.schemaNamespace.firstUppercased).\(type.schemaTypesNamespace).\(type.render(as: .typename))"
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

    let shouldIncludeTypenameSelection = shouldIncludeTypenameSelection(for: scope)
    let selectionsTemplate: TemplateString

    if !groupedSelections.isEmpty || shouldIncludeTypenameSelection {
      selectionsTemplate = TemplateString("""
        \(renderAccessControl())\
        static var __selections: [\(TemplateConstants.ApolloAPITargetName).Selection] { [
          \(if: shouldIncludeTypenameSelection, ".field(\"__typename\", String.self),")
          \(renderedSelections(groupedSelections.unconditionalSelections, &deprecatedArguments), terminator: ",")
          \(groupedSelections.inclusionConditionGroups.map {
          renderedConditionalSelectionGroup($0, $1, in: scope, &deprecatedArguments)
        }, terminator: ",")
        ] }
        """
      )
    } else {
      selectionsTemplate = ""
    }

    return """
      \(if: deprecatedArguments != nil && !deprecatedArguments.unsafelyUnwrapped.isEmpty, """
      \(deprecatedArguments.unsafelyUnwrapped.map { """
        \(field: $0.field, argument: $0.arg, warningReason: $0.reason)
        """}, separator: "\n")
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
      selections.fields.values.map { FieldSelectionTemplate($0, &deprecatedArguments) }
        + selections.inlineFragments.values.map { InlineFragmentSelectionTemplate($0.selectionSet) }
        + selections.namedFragments.values.map { FragmentSelectionTemplate($0) }
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

  private func InlineFragmentSelectionTemplate(_ inlineFragment: IR.SelectionSet) -> TemplateString
  {
    if let deferCondition = inlineFragment.deferCondition {
      return DeferredInlineFragmentSelectionTemplate(deferCondition)

    } else {
      return """
        .inlineFragment(\(inlineFragment.renderedTypeName).self)
        """
    }
  }

  private func FragmentSelectionTemplate(_ fragment: IR.NamedFragmentSpread) -> TemplateString {
    if let deferCondition = fragment.typeInfo.deferCondition {
      return DeferredNamedFragmentSelectionTemplate(
        deferCondition: deferCondition,
        fragment: fragment
      )

    } else {
      return """
      .fragment(\(fragment.definition.name.asFragmentName).self)
      """
    }
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

  private func DeferredNamedFragmentSelectionTemplate(
    deferCondition: CompilationResult.DeferCondition,
    fragment: IR.NamedFragmentSpread
  ) -> TemplateString {
    """
    .deferred(\
    \(ifLet: deferCondition.variable, { "if: \"\($0)\", " })\
    \(fragment.definition.name.asFragmentName).self, label: "\(deferCondition.label)")
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
    _ inlineFragments: [SelectionSetContext]
  ) -> TemplateString {
    "\(inlineFragments.map{ InlineFragmentAccessorTemplate($0.selectionSet) }, separator: "\n")"
  }

  private func InlineFragmentAccessorTemplate(
    _ inlineFragment: IR.ComputedSelectionSet
  ) -> TemplateString {
    guard !inlineFragment.typeInfo.scope.isDeferred else { return "" }

    let typeName = inlineFragment.renderedTypeName
    return """
      \(renderAccessControl())var \(typeName.firstLowercased): \(typeName)? { _asInlineFragment() }
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
        \(
          forEachIn: selectionSet.direct?.inlineFragments.values.elements ?? [],
          separator: "\n", {
            """
            \(ifLet: $0.typeInfo.deferCondition, {
              DeferredFragmentAccessorTemplate(propertyName: $0.label, typeName: $0.renderedTypeName)
            })
            """
          }
        )
      }
      """
  }

  private func FragmentInitializerTemplate(
    _ selectionSet: ComputedSelectionSet
  ) -> String {
    if let directSelections = selectionSet.direct,
      (directSelections.inlineFragments.containsDeferredFragment
      || directSelections.namedFragments.containsDeferredFragment)
    {
      return DesignatedInitializerTemplate(
        """
        \(forEachIn: directSelections.inlineFragments.values, separator: "\n", {
          if let deferCondition = $0.typeInfo.deferCondition {
            return DeferredPropertyInitializationStatement(deferCondition.label)
          }

          return ""
        })
        \(forEachIn: directSelections.namedFragments.values, separator: "\n", {
          if let _ = $0.typeInfo.deferCondition {
            return DeferredPropertyInitializationStatement($0.definition.name.firstLowercased)
          }

          return ""
        })
        """
      )

    } else {
      return DesignatedInitializerTemplate()
    }
  }

  private func DeferredPropertyInitializationStatement(_ propertyName: String) -> TemplateString {
    "_\(propertyName) = Deferred(_dataDict: _dataDict)"
  }

  private func NamedFragmentAccessorTemplate(
    _ fragment: IR.NamedFragmentSpread,
    in scope: IR.ScopeDescriptor
  ) -> TemplateString {
    let name = fragment.definition.name
    let propertyName = name.firstLowercased
    let typeName = name.asFragmentName
    let isOptional =
      fragment.inclusionConditions != nil
      && !scope.matches(fragment.inclusionConditions.unsafelyUnwrapped)
    let isDeferred = fragment.typeInfo.deferCondition != nil

    return """
      \(if: isDeferred,
          DeferredFragmentAccessorTemplate(
            propertyName: fragment.definition.name.firstLowercased,
            typeName: fragment.definition.name.asFragmentName
          )
      , else:
          """
          \(renderAccessControl())var \(propertyName): \(typeName)\(if: isOptional, "?") {\
          \(if: !isMutable && !isDeferred, " _toFragment() }")
          """
      )
      \(if: isMutable,
      """
        get { _toFragment() }
        _modify { var f = \(propertyName); yield &f; \(
          if: isOptional,
            "if let newData = f?.__data { __data = newData }",
          else: "__data = f.__data"
        ) }
      }
      """)
      """
  }

  private func DeferredFragmentAccessorTemplate(
    propertyName: String,
    typeName: String
  ) -> TemplateString {
    "@Deferred public var \(propertyName): \(typeName)?"
  }

  // MARK: - SelectionSet Initializer

  private func InitializerTemplate(
    _ selectionSet: ComputedSelectionSet
  ) -> TemplateString {
    let containsDeferredFragment = (selectionSet.direct?.inlineFragments.containsDeferredFragment ?? false) ||
      (selectionSet.direct?.namedFragments.containsDeferredFragment ?? false)

    return """
      \(renderAccessControl())init(
        \(InitializerSelectionParametersTemplate(selectionSet))
      ) {
        self.init(_dataDict: DataDict(
          data: [
            \(InitializerDataDictTemplate(selectionSet))
          ],
          fulfilledFragments: [
            \(InitializerFulfilledFragments(selectionSet))
          ]\(if: containsDeferredFragment, """
          ,
          deferredFragments: [
            \(InitializerDeferredFragments(selectionSet))
          ]
          """)
        ))
      }
      """
  }

  private func InitializerSelectionParametersTemplate(
    _ selectionSet: ComputedSelectionSet
  ) -> TemplateString {
    let isConcreteType = selectionSet.typeInfo.parentType is GraphQLObjectType
    let allFields = selectionSet.makeFieldIterator()

    return TemplateString(
      """
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
      \(field.responseKey.renderAsInitializerParameterName(config: config.config)): \
      \(typeName(for: field, forceOptional: isOptional))\
      \(if: isOptional, " = nil")
      """
  }

  private func InitializerDataDictTemplate(
    _ selectionSet: ComputedSelectionSet
  ) -> TemplateString {
    let isConcreteType = selectionSet.typeInfo.parentType is GraphQLObjectType
    let allFields = selectionSet.makeFieldIterator()

    return TemplateString(
      """
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
      "\(field.responseKey)": \(field.responseKey.renderAsInitializerParameterAccessorName(config: config.config))\
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
        .append(
          contentsOf: source.generatedSelectionSetNamesOfFullfilledFragments(
            pluralizer: config.pluralizer
          )
        )
    }

    return """
      \(fulfilledFragments.map { "ObjectIdentifier(\($0).self)" })
      """
  }

  private func InitializerDeferredFragments(
    _ selectionSet: ComputedSelectionSet
  ) -> TemplateString? {
    guard let directSelections = selectionSet.direct else { return nil }

    var deferredFragments: OrderedSet<String> = []

    for inlineFragmentSpread in directSelections.inlineFragments.values.elements {
      if inlineFragmentSpread.typeInfo.isDeferred {
        let selectionSetName = SelectionSetNameGenerator.generatedSelectionSetName(
          for: inlineFragmentSpread.typeInfo,
          format: .fullyQualified,
          pluralizer: config.pluralizer
        )
        deferredFragments.append(selectionSetName)
      }
    }

    for namedFragment in directSelections.namedFragments.values.elements {
      if namedFragment.typeInfo.isDeferred {
        deferredFragments.append(namedFragment.fragment.generatedDefinitionName)
      }
    }

    return """
      \(deferredFragments.map { "ObjectIdentifier(\($0).self)" })
      """
  }

  // MARK: - Nested Selection Sets

  private func ChildEntityFieldSelectionSets(
    _ context: SelectionSetContext
  ) -> TemplateString {
    let selectionSet = context.selectionSet
    let allFields = selectionSet.makeFieldIterator { field in
      field is IR.EntityField
    }

    return """
      \(IteratorSequence(allFields).compactMap { field in
        let field = unsafeDowncast(field, to: IR.EntityField.self)
        let childContext = createSelectionSetContext(for: field.selectionSet, inParent: context)
        return render(childEntity: childContext)
      }, separator: "\n\n")
      """
  }

  private func ChildTypeCaseSelectionSets(
    _ inlineFragments: [SelectionSetContext]
  ) -> TemplateString {
    return """
      \(inlineFragments.map(render(inlineFragment:)), separator: "\n\n")
      """
  }

}

// MARK: - SelectionSet Name Computation

private class SelectionSetNameCache {
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
      .formattedSelectionSetName(with: config.pluralizer)
      ?? location.source.formattedSelectionSetName()
  }

}

// MARK: - Helper Extensions

extension IR.ComputedSelectionSet {

  fileprivate var isCompositeInlineFragment: Bool {
    return !self.isEntityRoot && !self.isUserDefined && (direct?.isEmpty ?? true)
  }

  /// If the SelectionSet is a reference to another rendered SelectionSet, returns the qualified
  /// name of the referenced SelectionSet.
  ///
  /// If `nil` the SelectionSet should be rendered by the template engine.
  ///
  /// If a value is returned, references to the selection set can point to another rendered
  /// selection set with the returned name.
  fileprivate func nameForReferencedSelectionSet(
    config: ApolloCodegen.ConfigurationContext
  ) -> String? {
    guard direct == nil && self.typeInfo.derivedFromMergedSources.count == 1 else {
      return nil
    }

    return self.typeInfo.derivedFromMergedSources
      .first.unsafelyUnwrapped
      .generatedSelectionSetNamePath(
        from: typeInfo,
        pluralizer: config.pluralizer
      )
  }

}

extension IR.SelectionSet.TypeInfo {

  fileprivate var renderedTypeName: String {
    self.scope.scopePath.last.value.selectionSetNameComponent
  }

}

extension IR.MergedSelections.MergedSource {

  fileprivate func generatedSelectionSetNamePath(
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

    while representsSameScope(
      target: targetTypePathCurrentNode.value,
      source: sourceTypePathCurrentNode.value
    ) {
      guard let previousFieldNode = targetTypePathCurrentNode.previous,
        let previousSourceNode = sourceTypePathCurrentNode.previous
      else {
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
        for: self,
        format: .fullyQualified,
        pluralizer: pluralizer
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

  /// Checks whether the target and source scope descriptors represent the same scope.
  ///
  /// There is the obvious comparison when the two scope descriptors are equal but there
  /// is also a more nuanced edge case that must be considered too.
  ///
  /// This edge case occurs when the target merged source has an inclusion condition that
  /// gets broken out into the next node due to the same field existing without an inclusion
  /// condition at the target scope. In this case the comparison considers two contiguous
  /// nodes with a type condition and an inclusion condition at the root of the entity to 
  /// match a single node with a matching type condition and inclusion condition.
  ///
  /// See the test named `test__render_nestedSelectionSet__givenEntityFieldMerged_fromTypeCase_withInclusionCondition_rendersSelectionSetAsTypeAlias_withFullyQualifiedName`
  /// for a specific test related to this behaviour.
  fileprivate func representsSameScope(target: ScopeDescriptor, source: ScopeDescriptor) -> Bool {
    guard target != source else { return true }

    if target.scopePath.head.value.type == source.scopePath.head.value.type {
      guard 
        let sourceConditions = source.scopePath.head.value.conditions,
        target.scopePath[1].type == nil,
        let targetNextNodeConditions = target.scopePath[1].conditions
      else {
        return false
      }

      return sourceConditions == targetNextNodeConditions
    }

    return false
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

  fileprivate func generatedSelectionSetNamesOfFullfilledFragments(
    pluralizer: Pluralizer
  ) -> [String] {
    let entityRootNameInFragment =
      SelectionSetNameGenerator
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

struct SelectionSetNameGenerator {

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
        .formattedSelectionSetName(with: pluralizer)
      {
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

extension IR.ScopeCondition {

  fileprivate var selectionSetNameComponent: String {
    if let deferCondition {
      return deferCondition.renderedTypeName

    } else {
      return TemplateString(
        """
        \(ifLet: type, { "As\($0.render(as: .typename))" })\
        \(ifLet: conditions, { "If\($0.typeNameComponents)"})
        """
      ).description
    }
  }

}

extension AnyOf where T == IR.InclusionConditions {
  fileprivate var conditionVariableExpression: TemplateString {
    """
    \(elements.map {
      $0.conditionVariableExpression(wrapInParenthesisIfMultiple: elements.count > 1)
    }, separator: " || ")
    """
  }
}

extension IR.InclusionConditions {
  fileprivate func conditionVariableExpression(
    wrapInParenthesisIfMultiple: Bool = false
  ) -> TemplateString {
    let shouldWrap = wrapInParenthesisIfMultiple && count > 1
    return """
      \(if: shouldWrap, "(")\(map(\.conditionVariableExpression), separator: " && ")\(if: shouldWrap, ")")
      """
  }

  fileprivate var typeNameComponents: TemplateString {
    """
    \(map(\.typeNameComponent), separator: "And")
    """
  }
}

extension IR.InclusionCondition {
  fileprivate var conditionVariableExpression: TemplateString {
    """
    \(if: isInverted, "!")"\(variable)"
    """
  }

  fileprivate var typeNameComponent: TemplateString {
    """
    \(if: isInverted, "Not")\(variable.firstUppercased)
    """
  }
}

extension IR.Field {
  fileprivate var isCustomScalar: Bool {
    guard let scalar = self.type.namedType as? GraphQLScalarType else { return false }

    return scalar.isCustomScalar
  }

  fileprivate func isConditionallyIncluded(in scope: IR.ScopeDescriptor) -> Bool {
    guard let conditions = self.inclusionConditions else { return false }
    return !scope.matches(conditions)
  }
}

extension CompilationResult.DeferCondition {
  fileprivate var renderedTypeName: String {
    self.label.convertToCamelCase().firstUppercased.asSelectionSetName
  }
}

extension OrderedDictionary<ScopeCondition, InlineFragmentSpread> {
  fileprivate var containsDeferredFragment: Bool {
    keys.contains(where: { $0.isDeferred })
  }
}

extension OrderedDictionary<String, NamedFragmentSpread> {
  fileprivate var containsDeferredFragment: Bool {
    values.contains(where: { $0.typeInfo.deferCondition != nil })
  }
}
