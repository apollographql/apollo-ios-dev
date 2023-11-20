@testable import ApolloCodegenLib
@testable import IR
import GraphQLCompiler

public protocol ScopedChildSelectionSetAccessible {

  func childSelectionSet(
    with conditions: IR.ScopeCondition,
    entityStorage: DefinitionEntityStorage
  ) -> SelectionSetTestWrapper?

}

// MARK: - Conformance Extensions

//extension IR.DirectSelections: ScopedChildSelectionSetAccessible {
//  public func childSelectionSet(
//    with conditions: IR.ScopeCondition,
//    entityStorage: IR.RootFieldEntityStorage
//  ) -> SelectionSetTestWrapper? {
//    SelectionSetTestWrapper(
//      irObject: inlineFragments[conditions]?.selectionSet,
//      entityStorage: entityStorage
//    )
//  }
//}
//
//extension IR.MergedSelections: ScopedChildSelectionSetAccessible {
//  public func childSelectionSet(
//    with conditions: IR.ScopeCondition,
//    entityStorage: IR.RootFieldEntityStorage
//  ) -> SelectionSetTestWrapper? {
//    SelectionSetTestWrapper(
//      irObject: inlineFragments[conditions]?.selectionSet,
//      entityStorage: entityStorage
//    )
//  }
//}

extension IR.Field: ScopedChildSelectionSetAccessible {
  public func childSelectionSet(
    with conditions: IR.ScopeCondition,
    entityStorage: IR.DefinitionEntityStorage
  ) -> SelectionSetTestWrapper? {
    selectionSet?.childSelectionSet(with: conditions, entityStorage: entityStorage)
  }

  var selectionSet: IR.SelectionSet? {
    guard let entityField = self as? IR.EntityField else { return nil }
    return entityField.selectionSet as IR.SelectionSet
  }
}

extension IR.SelectionSet: ScopedChildSelectionSetAccessible {

  public func childSelectionSet(
    with conditions: IR.ScopeCondition,
    entityStorage: IR.DefinitionEntityStorage
  ) -> SelectionSetTestWrapper? {
#warning("TODO: this re-creates every time. Bad perf")
    let wrapper = SelectionSetTestWrapper(
      irObject: self,
      entityStorage: entityStorage
    )
    return wrapper?.childSelectionSet(with: conditions)
  }

#warning("TODO: do we need this?")
//  fileprivate subscript(
//    deferredAs label: String,
//    withVariable variable: String? = nil
//  ) -> IR.SelectionSet? {
//    let scope = ScopeCondition(
//      type: self.parentType,
//      conditions: self.inclusionConditions,
//      deferCondition: CompilationResult.DeferCondition(label: label, variable: variable)
//    )
//    return selections[scope]
//  }
}

extension ComputedSelectionSet: ScopedChildSelectionSetAccessible {
  public func childSelectionSet(
    with conditions: IR.ScopeCondition,
    entityStorage: IR.DefinitionEntityStorage
  ) -> SelectionSetTestWrapper? {
    let selectionSet = direct?.inlineFragments[conditions]?.selectionSet ??
    merged.inlineFragments[conditions]?.selectionSet

  #warning("TODO: this re-creates every time. Bad perf")
    return SelectionSetTestWrapper(
      irObject: selectionSet,
      entityStorage: entityStorage
    )
  }
}

extension IR.Operation: ScopedChildSelectionSetAccessible {
  public func childSelectionSet(
    with conditions: IR.ScopeCondition,
    entityStorage: IR.DefinitionEntityStorage
  ) -> SelectionSetTestWrapper? {
    rootField.childSelectionSet(with: conditions, entityStorage: entityStorage)
  }
}

//extension IR.NamedFragment: ScopedChildSelectionSetAccessible {
//  fileprivate subscript(field field: String) -> IR.Field? {
//    return rootField.selectionSet[field: field]
//  }
//
//  public func childSelectionSet(with conditions: IR.ScopeCondition) -> IR.SelectionSet? {
//    return rootField.selectionSet.childSelectionSet(with: conditions)
//  }
//
//  fileprivate subscript(fragment fragment: String) -> IR.NamedFragmentSpread? {
//    rootField.selectionSet[fragment: fragment]
//  }
//}

extension IR.NamedFragmentSpread: ScopedChildSelectionSetAccessible {
  public func childSelectionSet(
    with conditions: IR.ScopeCondition,
    entityStorage: IR.DefinitionEntityStorage
  ) -> SelectionSetTestWrapper? {
    return fragment.rootField.childSelectionSet(with: conditions, entityStorage: entityStorage)
  }
}
