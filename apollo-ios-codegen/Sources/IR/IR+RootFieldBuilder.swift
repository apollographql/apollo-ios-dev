import Foundation
import OrderedCollections
import GraphQLCompiler
import Utilities

class RootFieldEntityStorage {
  private(set) var entitiesForFields: [Entity.Location: Entity] = [:]

  init(rootEntity: Entity) {
    entitiesForFields[rootEntity.location] = rootEntity
  }

  func entity(
    for field: CompilationResult.Field,
    on enclosingEntity: Entity
  ) -> Entity {
    let location = enclosingEntity
      .location
      .appending(.init(name: field.responseKey, type: field.type))

    var rootTypePath: LinkedList<GraphQLCompositeType> {
      guard let fieldType = field.selectionSet?.parentType else {
        fatalError("Entity cannot be created for non-entity type field \(field).")
      }
      return enclosingEntity.rootTypePath.appending(fieldType)
    }

    return entitiesForFields[location] ??
    createEntity(location: location, rootTypePath: rootTypePath)
  }

  func entity(
    for entityInFragment: Entity,
    inFragmentSpreadAtTypePath fragmentSpreadTypeInfo: SelectionSet.TypeInfo
  ) -> Entity {
    var location = fragmentSpreadTypeInfo.entity.location
    if let pathInFragment = entityInFragment.location.fieldPath {
      location = location.appending(pathInFragment)
    }

    var rootTypePath: LinkedList<GraphQLCompositeType> {
      let otherRootTypePath = entityInFragment.rootTypePath.dropFirst()
      return fragmentSpreadTypeInfo.entity.rootTypePath.appending(otherRootTypePath)
    }

    return entitiesForFields[location] ??
    createEntity(location: location, rootTypePath: rootTypePath)
  }

  private func createEntity(
    location: Entity.Location,
    rootTypePath: LinkedList<GraphQLCompositeType>
  ) -> Entity {
    let entity = Entity(location: location, rootTypePath: rootTypePath)
    entitiesForFields[location] = entity
    return entity
  }

  fileprivate func mergeAllSelectionsIntoEntitySelectionTrees(from fragmentSpread: NamedFragmentSpread) {
    for (_, fragmentEntity) in fragmentSpread.fragment.entities {
      let entity = entity(for: fragmentEntity, inFragmentSpreadAtTypePath: fragmentSpread.typeInfo)
      entity.selectionTree.mergeIn(fragmentEntity.selectionTree, from: fragmentSpread, using: self)
    }
  }
}

class RootFieldBuilder {
  struct Result {
    let rootField: EntityField
    let referencedFragments: ReferencedFragments
    let entities: [Entity.Location: Entity]
    let containsDeferredFragment: Bool
  }

  typealias ReferencedFragments = OrderedSet<NamedFragment>

  static func buildRootEntityField(
    forRootField rootField: CompilationResult.Field,
    onRootEntity rootEntity: Entity,
    inIR ir: IRBuilder
  ) -> Result {
    return RootFieldBuilder(ir: ir, rootEntity: rootEntity)
      .build(rootField: rootField)
  }

  private let ir: IRBuilder
  private let rootEntity: Entity
  private let entityStorage: RootFieldEntityStorage
  private var referencedFragments: ReferencedFragments = []
  @IsEverTrue private var containsDeferredFragment: Bool

  private var schema: Schema { ir.schema }

  private init(ir: IRBuilder, rootEntity: Entity) {
    self.ir = ir
    self.rootEntity = rootEntity
    self.entityStorage = RootFieldEntityStorage(rootEntity: rootEntity)
  }

  private func build(
    rootField: CompilationResult.Field
  ) -> Result {
    guard let rootSelectionSet = rootField.selectionSet else {
      fatalError("Root field must have a selection set.")
    }

    let rootTypePath = ScopeDescriptor.descriptor(
      forType: rootEntity.rootType,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes
    )

    let rootIrSelectionSet = SelectionSet(
      entity: rootEntity,
      scopePath: LinkedList(rootTypePath)
    )

    buildDirectSelections(
      into: rootIrSelectionSet.selections.direct.unsafelyUnwrapped,
      atTypePath: rootIrSelectionSet.typeInfo,
      from: rootSelectionSet
    )

    return Result(
      rootField: EntityField(rootField, selectionSet: rootIrSelectionSet),
      referencedFragments: referencedFragments,
      entities: entityStorage.entitiesForFields,
      containsDeferredFragment: containsDeferredFragment
    )
  }

  private func buildDirectSelections(
    into target: DirectSelections,
    atTypePath typeInfo: SelectionSet.TypeInfo,
    from selectionSet: CompilationResult.SelectionSet
  ) {
    addSelections(from: selectionSet, to: target, atTypePath: typeInfo)

    if typeInfo.deferCondition == nil {
      typeInfo.entity.selectionTree.mergeIn(
        selections: target.readOnlyView,
        with: typeInfo
      )
    }
  }

  private func addSelections(
    from selectionSet: CompilationResult.SelectionSet,
    to target: DirectSelections,
    atTypePath typeInfo: SelectionSet.TypeInfo
  ) {
    for selection in selectionSet.selections {
      add(selection, to: target, atTypePath: typeInfo)
    }

    ir.fieldCollector.collectFields(from: selectionSet)
  }

  private func add(
    _ selection: CompilationResult.Selection,
    to target: DirectSelections,
    atTypePath typeInfo: SelectionSet.TypeInfo
  ) {
    switch selection {
    case let .field(field):
      if let irField = buildField(from: field, atTypePath: typeInfo) {
        target.mergeIn(irField)
      }

    case let .inlineFragment(inlineFragment):
      add(inlineFragment, from: selection, to: target, atTypePath: typeInfo)

    case let .fragmentSpread(fragmentSpread):
      add(fragmentSpread, from: selection, to: target, atTypePath: typeInfo)
    }
  }

  private func add(
    _ inlineFragment: CompilationResult.InlineFragment,
    from selection: CompilationResult.Selection,
    to target: DirectSelections,
    atTypePath typeInfo: SelectionSet.TypeInfo
  ) {
    guard let scope = scopeCondition(
      for: inlineFragment,
      in: typeInfo,
      isDeferred: (inlineFragment.deferCondition != nil)
    ) else {
      return
    }

    let inlineSelectionSet = inlineFragment.selectionSet
    let matchesScope = typeInfo.scope.matches(scope)

    switch (matchesScope, inlineFragment.deferCondition) {
    case (true, .some), (false, nil):
      var deferCondition: CompilationResult.DeferCondition? {
        guard let condition = inlineFragment.deferCondition else { return nil }

        return condition
      }

      let irTypeCase = buildInlineFragmentSpread(
        from: inlineSelectionSet,
        with: scope,
        inParentTypePath: typeInfo,
        deferCondition: deferCondition
      )
      target.mergeIn(irTypeCase)

    case (true, nil):
      addSelections(from: inlineSelectionSet, to: target, atTypePath: typeInfo)

    case (false, .some):
      let irTypeCase = buildInlineFragmentSpread(
        toWrap: selection,
        with: scope,
        inParentTypePath: typeInfo
      )
      target.mergeIn(irTypeCase)
    }
  }

  private func add(
    _ fragmentSpread: CompilationResult.FragmentSpread,
    from selection: CompilationResult.Selection,
    to target: DirectSelections,
    atTypePath typeInfo: SelectionSet.TypeInfo
  ) {
    guard let scope = scopeCondition(
      for: fragmentSpread,
      in: typeInfo,
      isDeferred: (fragmentSpread.deferCondition != nil)
    ) else {
      return
    }

    let selectionSetScope = typeInfo.scope
    let matchesScope = selectionSetScope.matches(scope)

    switch (matchesScope, fragmentSpread.deferCondition) {
    case (true, .some), (true, nil):
      var deferCondition: CompilationResult.DeferCondition? {
        guard let condition = fragmentSpread.deferCondition else { return nil }

        return condition
      }

      let irFragmentSpread = buildNamedFragmentSpread(
        fromFragment: fragmentSpread,
        with: scope,
        spreadIntoParentWithTypePath: typeInfo,
        deferCondition: deferCondition
      )
      target.mergeIn(irFragmentSpread)

    case (false, .some):
      let irTypeCase = buildInlineFragmentSpread(
        toWrap: selection,
        with: scope,
        inParentTypePath: typeInfo
      )
      target.mergeIn(irTypeCase)

    case (false, nil):
      let irTypeCaseEnclosingFragment = buildInlineFragmentSpread(
        from: CompilationResult.SelectionSet(
          parentType: fragmentSpread.parentType,
          selections: [selection]
        ),
        with: scope,
        inParentTypePath: typeInfo
      )

      target.mergeIn(irTypeCaseEnclosingFragment)

      var matchesType: Bool {
        guard let typeCondition = scope.type else { return true }
        return selectionSetScope.matches(typeCondition)
      }

      if matchesType {
        typeInfo.entity.selectionTree.mergeIn(
          selections: irTypeCaseEnclosingFragment.selectionSet.selections.direct.unsafelyUnwrapped.readOnlyView,
          with: typeInfo
        )
      }
    }
  }

  private func scopeCondition(
    for conditionalSelectionSet: ConditionallyIncludable,
    in parentTypePath: SelectionSet.TypeInfo,
    isDeferred: Bool = false
  ) -> ScopeCondition? {
    let inclusionResult = inclusionResult(for: conditionalSelectionSet.inclusionConditions)
    guard inclusionResult != .skipped else {
      return nil
    }

    let type = (
      // We must specify the type whenever there is a defer condition because even when the type
      // case matches that of the parent it must be evaluted as an entirely separate scope because
      // deferred fragments are treated as isolated selections and must not be merged into any
      // other selection.
      parentTypePath.parentType == conditionalSelectionSet.parentType
      && !isDeferred
    )
    ? nil
    : conditionalSelectionSet.parentType

    return ScopeCondition(type: type, conditions: inclusionResult.conditions)
  }

  private func inclusionResult(
    for conditions: [CompilationResult.InclusionCondition]?
  ) -> InclusionConditions.Result {
    guard let conditions = conditions else {
      return .included
    }

    return InclusionConditions.allOf(conditions)
  }

  private func buildField(
    from field: CompilationResult.Field,
    atTypePath enclosingTypeInfo: SelectionSet.TypeInfo
  ) -> Field? {
    let inclusionResult = inclusionResult(for: field.inclusionConditions)
    guard inclusionResult != .skipped else {
      return nil
    }

    let inclusionConditions = inclusionResult.conditions

    if field.type.namedType is GraphQLCompositeType {
      let irSelectionSet = buildSelectionSet(
        forField: field,
        with: inclusionConditions,
        atTypePath: enclosingTypeInfo
      )

      return EntityField(
        field,
        inclusionConditions: AnyOf(inclusionConditions),
        selectionSet: irSelectionSet
      )

    } else {
      return ScalarField(field, inclusionConditions: AnyOf(inclusionConditions))
    }
  }

  private func buildSelectionSet(
    forField field: CompilationResult.Field,
    with inclusionConditions: InclusionConditions?,
    atTypePath enclosingTypeInfo: SelectionSet.TypeInfo
  ) -> SelectionSet {
    guard let fieldSelectionSet = field.selectionSet else {
      preconditionFailure("SelectionSet cannot be created for non-entity type field \(field).")
    }

    let entity = entityStorage.entity(for: field, on: enclosingTypeInfo.entity)

    let typeScope = ScopeDescriptor.descriptor(
      forType: fieldSelectionSet.parentType,
      inclusionConditions: inclusionConditions,
      givenAllTypesInSchema: schema.referencedTypes
    )
    let typePath = enclosingTypeInfo.scopePath.appending(typeScope)

    let irSelectionSet = SelectionSet(
      entity: entity,
      scopePath: typePath
    )
    buildDirectSelections(
      into: irSelectionSet.selections.direct.unsafelyUnwrapped,
      atTypePath: irSelectionSet.typeInfo,
      from: fieldSelectionSet
    )
    return irSelectionSet
  }

  private func buildInlineFragmentSpread(
    from selectionSet: CompilationResult.SelectionSet?,
    with scopeCondition: ScopeCondition,
    inParentTypePath enclosingTypeInfo: SelectionSet.TypeInfo,
    deferCondition: CompilationResult.DeferCondition? = nil
  ) -> InlineFragmentSpread {
    let scope = ScopeCondition(
      type: scopeCondition.type,
      conditions: (deferCondition == nil ? scopeCondition.conditions : nil),
      deferCondition: deferCondition
    )

    self.containsDeferredFragment = (scope.deferCondition != nil)

    let typePath = enclosingTypeInfo.scopePath.mutatingLast {
      $0.appending(scope)
    }

    let irSelectionSet = SelectionSet(
      entity: enclosingTypeInfo.entity,
      scopePath: typePath
    )

    if let selectionSet = selectionSet {
      buildDirectSelections(
        into: irSelectionSet.selections.direct.unsafelyUnwrapped,
        atTypePath: irSelectionSet.typeInfo,
        from: selectionSet
      )
    }

    return InlineFragmentSpread(selectionSet: irSelectionSet)
  }

  private func buildInlineFragmentSpread(
    toWrap selection: CompilationResult.Selection,
    with scopeCondition: ScopeCondition,
    inParentTypePath enclosingTypeInfo: SelectionSet.TypeInfo
  ) -> InlineFragmentSpread {
    let typePath = enclosingTypeInfo.scopePath.mutatingLast {
      $0.appending(scopeCondition)
    }

    let irSelectionSet = SelectionSet(
      entity: enclosingTypeInfo.entity,
      scopePath: typePath
    )

    add(
      selection,
      to: irSelectionSet.selections.direct.unsafelyUnwrapped,
      atTypePath: irSelectionSet.typeInfo
    )

    return InlineFragmentSpread(selectionSet: irSelectionSet)
  }

  private func buildNamedFragmentSpread(
    fromFragment fragmentSpread: CompilationResult.FragmentSpread,
    with scopeCondition: ScopeCondition,
    spreadIntoParentWithTypePath parentTypeInfo: SelectionSet.TypeInfo,
    deferCondition: CompilationResult.DeferCondition? = nil
  ) -> NamedFragmentSpread {
    let fragment = ir.build(fragment: fragmentSpread.fragment)
    referencedFragments.append(fragment)
    referencedFragments.append(contentsOf: fragment.referencedFragments)

    let scope = ScopeCondition(
      type: scopeCondition.type,
      conditions: (deferCondition == nil ? scopeCondition.conditions : nil),
      deferCondition: deferCondition
    )

    self.containsDeferredFragment = fragment.containsDeferredFragment || scope.deferCondition != nil

    let scopePath = scope.isEmpty 
      ? parentTypeInfo.scopePath
      : parentTypeInfo.scopePath.mutatingLast { $0.appending(scope) }

    let typeInfo = SelectionSet.TypeInfo(
      entity: parentTypeInfo.entity,
      scopePath: scopePath
    )

    let fragmentSpread = NamedFragmentSpread(
      fragment: fragment,
      typeInfo: typeInfo,
      inclusionConditions: AnyOf(scope.conditions)
    )

    if fragmentSpread.typeInfo.deferCondition == nil {
      entityStorage.mergeAllSelectionsIntoEntitySelectionTrees(from: fragmentSpread)
    }

    return fragmentSpread
  }

}

// MARK: - Helpers

fileprivate protocol ConditionallyIncludable {
  var parentType: GraphQLCompositeType { get }
  var inclusionConditions: [CompilationResult.InclusionCondition]? { get }
}

extension CompilationResult.InlineFragment: ConditionallyIncludable {
  var parentType: GraphQLCompositeType { selectionSet.parentType }
}
extension CompilationResult.FragmentSpread: ConditionallyIncludable {}
