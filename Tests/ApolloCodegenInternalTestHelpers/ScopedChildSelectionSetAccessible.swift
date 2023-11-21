@testable import ApolloCodegenLib
@testable import IR
import GraphQLCompiler

public protocol ScopedChildSelectionSetAccessible: CustomDebugStringConvertible {

  func childSelectionSet(
    with conditions: IR.ScopeCondition,
    entityStorage: DefinitionEntityStorage
  ) -> SelectionSetTestWrapper?

}

// MARK: - Conformance Extensions

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
    return wrapper.childSelectionSet(with: conditions)
  }

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

extension IR.NamedFragment: ScopedChildSelectionSetAccessible {
  public func childSelectionSet(
    with conditions: IR.ScopeCondition,
    entityStorage: IR.DefinitionEntityStorage
  ) -> SelectionSetTestWrapper? {
    return rootField.childSelectionSet(with: conditions, entityStorage: entityStorage)
  }
}

extension IR.NamedFragmentSpread: ScopedChildSelectionSetAccessible {
  public func childSelectionSet(
    with conditions: IR.ScopeCondition,
    entityStorage: IR.DefinitionEntityStorage
  ) -> SelectionSetTestWrapper? {
    return fragment.rootField.childSelectionSet(with: conditions, entityStorage: entityStorage)
  }
}
