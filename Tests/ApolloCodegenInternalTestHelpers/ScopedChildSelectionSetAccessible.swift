@testable import ApolloCodegenLib
@testable import IR
import GraphQLCompiler

protocol ScopedChildSelectionSetAccessible: CustomDebugStringConvertible {

  func childSelectionSet(
    with conditions: IR.ScopeCondition,
    computedSelectionSetCache: ComputedSelectionSetCache
  ) -> SelectionSetTestWrapper?

}

// MARK: - Conformance Extensions

extension IR.Field: ScopedChildSelectionSetAccessible {
  func childSelectionSet(
    with conditions: IR.ScopeCondition,
    computedSelectionSetCache: ComputedSelectionSetCache
  ) -> SelectionSetTestWrapper? {
    selectionSet?.childSelectionSet(
      with: conditions,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }

  var selectionSet: IR.SelectionSet? {
    guard let entityField = self as? IR.EntityField else { return nil }
    return entityField.selectionSet as IR.SelectionSet
  }
}

extension IR.SelectionSet: ScopedChildSelectionSetAccessible {

  func childSelectionSet(
    with conditions: IR.ScopeCondition,
    computedSelectionSetCache: ComputedSelectionSetCache
  ) -> SelectionSetTestWrapper? {
    let wrapper = SelectionSetTestWrapper(
      irObject: self,
      computedSelectionSetCache: computedSelectionSetCache
    )
    return wrapper.childSelectionSet(with: conditions)
  }

}

extension ComputedSelectionSet: ScopedChildSelectionSetAccessible {
  func childSelectionSet(
    with conditions: IR.ScopeCondition,
    computedSelectionSetCache: ComputedSelectionSetCache
  ) -> SelectionSetTestWrapper? {
    let selectionSet = 
    direct?
      .inlineFragments[conditions]?
      .selectionSet ??
    merged[computedSelectionSetCache.mergingStrategy]!
      .inlineFragments[conditions]?
      .selectionSet

    return SelectionSetTestWrapper(
      irObject: selectionSet,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }
}

extension IR.Operation: ScopedChildSelectionSetAccessible {
  func childSelectionSet(
    with conditions: IR.ScopeCondition,
    computedSelectionSetCache: ComputedSelectionSetCache
  ) -> SelectionSetTestWrapper? {
    rootField.childSelectionSet(
      with: conditions,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }
}

extension IR.NamedFragment: ScopedChildSelectionSetAccessible {
  func childSelectionSet(
    with conditions: IR.ScopeCondition,
    computedSelectionSetCache: ComputedSelectionSetCache
  ) -> SelectionSetTestWrapper? {
    return rootField.childSelectionSet(
      with: conditions,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }
}

extension IR.NamedFragmentSpread: ScopedChildSelectionSetAccessible {
  func childSelectionSet(
    with conditions: IR.ScopeCondition,
    computedSelectionSetCache: ComputedSelectionSetCache
  ) -> SelectionSetTestWrapper? {
    return fragment.rootField.childSelectionSet(
      with: conditions,
      computedSelectionSetCache: computedSelectionSetCache
    )
  }
}
