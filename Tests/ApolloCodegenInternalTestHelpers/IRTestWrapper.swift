@testable import ApolloCodegenLib
@testable import IR
import GraphQLCompiler

/// A wrapper for IR types that allows for unit tests to easily compute, access, and verify built
/// selection sets.
///
///  This wrapper provides the subscripts for accessing child selections by automatically computing and storing the `ComputedSelectionSet` results as they are accessed in unit tests.
///
///  `IRTestWrapper` types should never be initialized directly. They should be created using an
///  `IRBuilderTestWrapper`.
@dynamicMemberLookup
public class IRTestWrapper<T: CustomDebugStringConvertible>: CustomDebugStringConvertible {
  public let irObject: T
  let computedSelectionSetCache: ComputedSelectionSetCache

  init(
    irObject: T,
    computedSelectionSetCache: ComputedSelectionSetCache
  ) {
    self.irObject = irObject
    self.computedSelectionSetCache = computedSelectionSetCache
  }

  convenience init?(
    irObject: T?,
    computedSelectionSetCache: ComputedSelectionSetCache
  ) {
    guard let irObject else { return nil }
    self.init(
      irObject: irObject,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }

  public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> V {
    irObject[keyPath: keyPath]
  }

  fileprivate func childSelectionSet(
    with conditions: IR.ScopeCondition
  ) -> SelectionSetTestWrapper? {
    guard let irObject = irObject as? (any ScopedChildSelectionSetAccessible) else {
      return nil
    }

    return irObject.childSelectionSet(
      with: conditions,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }

  public var debugDescription: String { irObject.debugDescription }

}

/// A subclass of `IRTestWrapper` to be used when wrapping a `SelectionSet`. This wrapper
/// computes and stores the `ComputedSelectionSet`.
@dynamicMemberLookup
public class SelectionSetTestWrapper: IRTestWrapper<IR.SelectionSet> {
  public let computed: ComputedSelectionSet

  override init(
    irObject selectionSet: SelectionSet,
    computedSelectionSetCache: ComputedSelectionSetCache
  ) {
    self.computed = computedSelectionSetCache.computed(for: selectionSet)

    super.init(
      irObject: selectionSet,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }

  override func childSelectionSet(
    with conditions: ScopeCondition
  ) -> SelectionSetTestWrapper? {
    self.computed.childSelectionSet(
      with: conditions,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }

  public override var debugDescription: String { computed.debugDescription }
}

// MARK: -
extension IRTestWrapper {

  public subscript(as typeCase: String) -> SelectionSetTestWrapper? {
    guard let scope = self.scopeCondition(type: typeCase, conditions: nil) else {
      return nil
    }

    return childSelectionSet(with: scope)
  }

  public subscript(
    as typeCase: String? = nil,
    if condition: IR.InclusionCondition? = nil
  ) -> SelectionSetTestWrapper? {
    let conditions: IR.InclusionConditions.Result?
    if let condition = condition {
      conditions = .conditional(.init(condition))
    } else {
      conditions = nil
    }

    guard let scope = self.scopeCondition(type: typeCase, conditions: conditions) else {
      return nil
    }
    return childSelectionSet(with: scope)
  }

  public subscript(
    as typeCase: String? = nil,
    if conditions: IR.InclusionConditions.Result? = nil
  ) -> SelectionSetTestWrapper? {
    guard let scope = self.scopeCondition(type: typeCase, conditions: conditions) else {
      return nil
    }

    return childSelectionSet(with: scope)
  }

  public subscript(
    deferred deferCondition: CompilationResult.DeferCondition? = nil
  ) -> SelectionSetTestWrapper? {
    guard let scope = self.scopeCondition(
      type: nil,
      conditions: nil,
      deferCondition: deferCondition
    ) else {
      return nil
    }

    return childSelectionSet(with: scope)
  }

  private func scopeCondition(
    type typeCase: String?,
    conditions conditionsResult: IR.InclusionConditions.Result?,
    deferCondition: CompilationResult.DeferCondition? = nil
  ) -> IR.ScopeCondition? {
    let type: GraphQLCompositeType?
    if let typeCase = typeCase {
      type = GraphQLCompositeType.mock(typeCase)
    } else {
      type = nil
    }

    let conditions: IR.InclusionConditions?

    if let conditionsResult = conditionsResult {
      guard conditionsResult != .skipped else {
        return nil
      }

      conditions = conditionsResult.conditions

    } else {
      conditions = nil
    }

    return IR.ScopeCondition(type: type, conditions: conditions, deferCondition: deferCondition)
  }
}

// MARK: - Test Wrapper Subscripts

extension IRTestWrapper<IR.Field> {
  public subscript(field field: String) -> IRTestWrapper<IR.Field>? {
    self.selectionSet?[field: field]
  }

  public subscript(fragment fragment: String) -> IRTestWrapper<IR.NamedFragmentSpread>? {
    self.selectionSet?[fragment: fragment]
  }

  public var selectionSet: SelectionSetTestWrapper? {
    guard let entityField = self.irObject as? IR.EntityField else { return nil }
    return SelectionSetTestWrapper(
      irObject: entityField.selectionSet,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }
}

extension IRTestWrapper<IR.NamedFragmentSpread> {
  public subscript(field field: String) -> IRTestWrapper<IR.Field>? {
    rootField[field: field]
  }

  public subscript(fragment fragment: String) -> IRTestWrapper<IR.NamedFragmentSpread>? {
    rootField[fragment: fragment]
  }

  public var rootField: IRTestWrapper<IR.Field> {
    return IRTestWrapper<IR.Field>(
      irObject:  irObject.fragment.rootField,
      computedSelectionSetCache: .init(entityStorage: irObject.fragment.entityStorage)
    )
  }

}

extension IRTestWrapper<IR.Operation> {
  public subscript(field field: String) -> IRTestWrapper<IR.Field>? {
    guard irObject.rootField.underlyingField.name == field else { return nil }

    return rootField
  }

  public subscript(fragment fragment: String) -> IRTestWrapper<IR.NamedFragmentSpread>? {
    rootField[fragment: fragment]
  }

  public var rootField: IRTestWrapper<IR.Field> {
    return IRTestWrapper<IR.Field>(
      irObject: irObject.rootField,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }
}

extension IRTestWrapper<IR.NamedFragment> {
  public subscript(field field: String) -> IRTestWrapper<IR.Field>? {
    if irObject.rootField.underlyingField.name == field { return rootField }

    return rootField[field: field]
  }

  public subscript(fragment fragment: String) -> IRTestWrapper<IR.NamedFragmentSpread>? {
    rootField[fragment: fragment]
  }

  public var rootField: IRTestWrapper<IR.Field> {
    return IRTestWrapper<IR.Field>(
      irObject: irObject.rootField,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }
}

extension SelectionSetTestWrapper {
  public subscript(field field: String) -> IRTestWrapper<IR.Field>? {
    IRTestWrapper<IR.Field>(
      irObject:
        computed.direct?.fields[field] ?? computed.merged.fields[field],
      computedSelectionSetCache: computedSelectionSetCache
    )
  }

  public subscript(fragment fragment: String) -> IRTestWrapper<IR.NamedFragmentSpread>? {
    IRTestWrapper<IR.NamedFragmentSpread>(
      irObject:
        computed.direct?.namedFragments[fragment] ?? computed.merged.namedFragments[fragment],
      computedSelectionSetCache: computedSelectionSetCache
    )
  }
}

// MARK: - ComputedSelectionSetCache

class ComputedSelectionSetCache {
  private var selectionSets: [SelectionSet.TypeInfo: ComputedSelectionSet] = [:]
  public let entityStorage: DefinitionEntityStorage

  init(entityStorage: DefinitionEntityStorage) {
    self.entityStorage = entityStorage
  }

  func computed(for selectionSet: SelectionSet) -> ComputedSelectionSet{
    if let selectionSet = selectionSets[selectionSet.typeInfo] {
      return selectionSet
    }

    let selectionSet = ComputedSelectionSet.Builder(
      directSelections: selectionSet.selections?.readOnlyView,
      typeInfo: selectionSet.typeInfo,
      entityStorage: entityStorage
    ).build()

    selectionSets[selectionSet.typeInfo] = selectionSet
    return selectionSet
  }
}
