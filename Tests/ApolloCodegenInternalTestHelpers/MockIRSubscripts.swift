@testable import ApolloCodegenLib
@testable import IR
import GraphQLCompiler

// MARK: - IR Test Wrapper
@dynamicMemberLookup
public class IRTestWrapper<T: ScopedChildSelectionSetAccessible> {
  public let irObject: T
  public let entityStorage: RootFieldEntityStorage

  init?(
    irObject: T?,
    entityStorage: RootFieldEntityStorage
  ) {
    guard let irObject else { return nil }
    self.irObject = irObject
    self.entityStorage = entityStorage
  }

  public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> V {
    irObject[keyPath: keyPath]
  }

  fileprivate func childSelectionSet(
    with conditions: IR.ScopeCondition
  ) -> SelectionSetTestWrapper? {
    irObject.childSelectionSet(with: conditions, entityStorage: entityStorage)
  }

}

@dynamicMemberLookup
public class SelectionSetTestWrapper: IRTestWrapper<IR.SelectionSet> {
  public let selections: ComputedSelectionSet

  override init?(
    irObject selectionSet: SelectionSet?,
    entityStorage: RootFieldEntityStorage
  ) {
    guard let selectionSet else { return nil }
    let mergedBuilder = MergedSelections.Builder(
      directSelections: selectionSet.selections?.readOnlyView,
      typeInfo: selectionSet.typeInfo,
      entityStorage: entityStorage
    )
    self.selections = ComputedSelectionSet(
      direct: selectionSet.selections,
      merged: mergedBuilder.build(),
      typeInfo: selectionSet.typeInfo
    )

    super.init(irObject: selectionSet, entityStorage: entityStorage)
  }

  override func childSelectionSet(
    with conditions: ScopeCondition
  ) -> SelectionSetTestWrapper? {
    self.selections.childSelectionSet(with: conditions, entityStorage: entityStorage)
  }
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
    as typeCase: String? = nil,
    deferred deferCondition: CompilationResult.DeferCondition? = nil
  ) -> SelectionSetTestWrapper? {
    guard let scope = self.scopeCondition(
      type: typeCase,
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

//extension IRTestWrapper<IR.DirectSelections>{
//  public subscript(field field: String) -> IRTestWrapper<IR.Field>? {
//    IRTestWrapper<IR.Field>(
//      irObject: irObject.fields[field],
//      entityStorage: entityStorage
//    )
//  }
//
//  public subscript(fragment fragment: String) -> IRTestWrapper<IR.NamedFragmentSpread>? {
//    IRTestWrapper<IR.NamedFragmentSpread>(
//      irObject: irObject.namedFragments[fragment],
//      entityStorage: entityStorage
//    )
//  }
//}
//
//extension IRTestWrapper<IR.MergedSelections> {
//  public subscript(field field: String) -> IRTestWrapper<IR.Field>? {
//    IRTestWrapper<IR.Field>(
//      irObject: irObject.fields[field],
//      entityStorage: entityStorage
//    )
//  }
//
//  public subscript(fragment fragment: String) -> IRTestWrapper<IR.NamedFragmentSpread>? {
//    IRTestWrapper<IR.NamedFragmentSpread>(
//      irObject: irObject.namedFragments[fragment],
//      entityStorage: entityStorage
//    )
//  }
//}

extension IRTestWrapper<IR.Field> {
  public subscript(field field: String) -> IRTestWrapper<IR.Field>? {
    self.selectionSet?[field: field]
  }

  public subscript(fragment fragment: String) -> IRTestWrapper<IR.NamedFragmentSpread>? {
    self.selectionSet?[fragment: fragment]
  }

  fileprivate var selectionSet: SelectionSetTestWrapper? {
    guard let entityField = self.irObject as? IR.EntityField else { return nil }
    #warning("TODO: this re-creates every time. Bad perf")
    return SelectionSetTestWrapper(
      irObject: entityField.selectionSet,
      entityStorage: entityStorage
    )
  }
}

extension IRTestWrapper<IR.NamedFragmentSpread> {
  public subscript(field field: String) -> IRTestWrapper<IR.Field>? {
    rootField?[field: field]    
  }

  public subscript(fragment fragment: String) -> IRTestWrapper<IR.NamedFragmentSpread>? {
    rootField?[fragment: fragment]
  }

  fileprivate var rootField: IRTestWrapper<IR.Field>? {
    return IRTestWrapper<IR.Field>(
      irObject: irObject.fragment.rootField,
      entityStorage: entityStorage
    )
  }
}

extension IRTestWrapper<IR.Operation> {
  public subscript(field field: String) -> IRTestWrapper<IR.Field>? {
    guard irObject.rootField.underlyingField.name == field else { return nil }

    return rootField
  }

  public subscript(fragment fragment: String) -> IRTestWrapper<IR.NamedFragmentSpread>? {
    rootField?[fragment: fragment]
  }

  fileprivate var rootField: IRTestWrapper<IR.Field>? {
    return IRTestWrapper<IR.Field>(
      irObject: irObject.rootField,
      entityStorage: entityStorage
    )
  }
}

extension SelectionSetTestWrapper {
  public subscript(field field: String) -> IRTestWrapper<IR.Field>? {
    IRTestWrapper<IR.Field>(
      irObject: 
        selections.direct?.fields[field] ?? selections.merged.fields[field],
      entityStorage: entityStorage
    )
  }

  public subscript(fragment fragment: String) -> IRTestWrapper<IR.NamedFragmentSpread>? {
    IRTestWrapper<IR.NamedFragmentSpread>(
      irObject: 
        selections.direct?.namedFragments[fragment] ?? selections.merged.namedFragments[fragment],
      entityStorage: entityStorage
    )
  }
}

// MARK: - Other Subscript Accessors

extension IR.Schema {
  public subscript(object name: String) -> GraphQLObjectType? {
    return referencedTypes.objects.first { $0.name == name }
  }

  public subscript(interface name: String) -> GraphQLInterfaceType? {
    return referencedTypes.interfaces.first { $0.name == name }
  }

  public subscript(union name: String) -> GraphQLUnionType? {
    return referencedTypes.unions.first { $0.name == name }
  }

  public subscript(scalar name: String) -> GraphQLScalarType? {
    return referencedTypes.scalars.first { $0.name == name }
  }

  public subscript(enum name: String) -> GraphQLEnumType? {
    return referencedTypes.enums.first { $0.name == name }
  }

  public subscript(inputObject name: String) -> GraphQLInputObjectType? {
    return referencedTypes.inputObjects.first { $0.name == name }
  }
}

extension CompilationResult {

  public subscript(type name: String) -> GraphQLNamedType? {
    return referencedTypes.first { $0.name == name }
  }

  public subscript(operation name: String) -> CompilationResult.OperationDefinition? {
    return operations.first { $0.name == name }
  }

  public subscript(fragment name: String) -> CompilationResult.FragmentDefinition? {
    return fragments.first { $0.name == name }
  }
}

extension IR.EntityTreeScopeSelections {
  public subscript(field field: String) -> IR.Field? {
    fields[field]
  }

  public subscript(fragment fragment: String) -> IR.NamedFragmentSpread? {
    namedFragments[fragment]
  }
}
