import OrderedCollections
import GraphQLCompiler
import TemplateString
import Utilities

/// Represents the selections for an entity at different nested type scopes in a tree.
///
/// This data structure is used to memoize the selections for an `Entity` to quickly compute
/// the `mergedSelections` for `SelectionSet`s.
///
/// During the creation of `SelectionSet`s, their `selections` are added to their entities
/// mergedSelectionTree at the appropriate type scope. After all `SelectionSet`s have been added
/// to the `EntitySelectionTree`, the tree can be quickly traversed to collect the selections
/// that will be selected for a given `SelectionSet`'s type scope.
class EntitySelectionTree {
  let rootTypePath: LinkedList<GraphQLCompositeType>
  let rootNode: EntityNode

  init(rootTypePath: LinkedList<GraphQLCompositeType>) {
    self.rootTypePath = rootTypePath
    self.rootNode = EntityNode(rootTypePath: rootTypePath)
  }

  // MARK: - Merge Selection Sets Into Tree

  func mergeIn(
    selections: DirectSelections.ReadOnly,
    with typeInfo: SelectionSet.TypeInfo
  ) {
    let source = MergedSelections.MergedSource(
      typeInfo: typeInfo,
      fragment: nil
    )
    mergeIn(selections: selections, from: source)
  }

  private func mergeIn(selections: DirectSelections.ReadOnly, from source: MergedSelections.MergedSource) {
    guard (!selections.fields.isEmpty || !selections.namedFragments.isEmpty) else {
      return
    }

    let targetNode = Self.findOrCreateNode(
      atEnclosingEntityScope: source.typeInfo.scopePath.head,
      withEntityScopePath: source.typeInfo.scopePath.head.value.scopePath.head,
      from: rootNode,
      withRootTypePath: rootTypePath.head
    )

    targetNode.mergeIn(selections, from: source)
  }

  fileprivate static func findOrCreateNode(
    atEnclosingEntityScope currentEntityScope: LinkedList<ScopeDescriptor>.Node,
    withEntityScopePath currentEntityConditionPath: LinkedList<ScopeCondition>.Node,
    from node: EntityNode,
    withRootTypePath currentRootTypePathNode: LinkedList<GraphQLCompositeType>.Node
  ) -> EntityNode {
    guard let nextEntityTypePath = currentRootTypePathNode.next else {
      // Advance to field node in current entity & type case
      return Self.findOrCreateNode(
        withConditionScopePath: currentEntityScope.value.scopePath.head,
        from: node
      )
    }

    guard let nextConditionPathForCurrentEntity = currentEntityConditionPath.next else {
      // Advance to next entity
      guard let nextEntityScope = currentEntityScope.next else { fatalError() }
      let nextEntityNode = node.childAsEntityNode()

      return findOrCreateNode(
        atEnclosingEntityScope: nextEntityScope,
        withEntityScopePath: nextEntityScope.value.scopePath.head,
        from: nextEntityNode,
        withRootTypePath: nextEntityTypePath
      )
    }

    // Advance to next type case in current entity
    let nextCondition = nextConditionPathForCurrentEntity.value

    let nextNodeForCurrentEntity = node.scope != nextCondition
    ? node.scopeConditionNode(for: nextCondition) : node

    return findOrCreateNode(
      atEnclosingEntityScope: currentEntityScope,
      withEntityScopePath: nextConditionPathForCurrentEntity,
      from: nextNodeForCurrentEntity,
      withRootTypePath: currentRootTypePathNode
    )
  }

  private static func findOrCreateNode(
    withConditionScopePath selectionsScopePath: LinkedList<ScopeCondition>.Node,
    from node: EntityNode
  ) -> EntityNode {
    guard let nextConditionInScopePath = selectionsScopePath.next else {
      // Last condition in field scope path
      let selectionsCondition = selectionsScopePath.value

      return selectionsCondition == node.scope ?
      node : node.scopeConditionNode(for: selectionsCondition)
    }

    let nextCondition = nextConditionInScopePath.value
    let nextConditionNode = node.scopeConditionNode(for: nextCondition)

    return findOrCreateNode(
      withConditionScopePath: nextConditionInScopePath,
      from: nextConditionNode
    )
  }

  // MARK: - Calculate Merged Selections From Tree

  func addMergedSelections(into selections: ComputedSelectionSet.Builder) {
    let rootTypePath = selections.typeInfo.scopePath.head
    rootNode.mergeSelections(
      matchingScopePath: rootTypePath,
      into: selections,
      transformingSelections: nil
    )
  }

  class EntityNode {
    typealias Selections = OrderedDictionary<MergedSelections.MergedSource, EntityTreeScopeSelections>
    enum Child {
      case entity(EntityNode)
      case selections(Selections)
    }

    let rootTypePathNode: LinkedList<GraphQLCompositeType>.Node
    let type: GraphQLCompositeType
    let scope: ScopeCondition
    private(set) var child: Child?
    var scopeConditions: OrderedDictionary<ScopeCondition, EntityNode>?
    var mergedFragmentTrees: OrderedDictionary<NamedFragmentSpread, EntitySelectionTree> = [:]

    fileprivate convenience init(rootTypePath: LinkedList<GraphQLCompositeType>) {
      self.init(typeNode: rootTypePath.head)
    }

    private init(typeNode: LinkedList<GraphQLCompositeType>.Node) {
      self.scope = .init(type: typeNode.value)
      self.type = typeNode.value
      self.rootTypePathNode = typeNode

      if let nextNode = typeNode.next {
        child = .entity(EntityNode(typeNode: nextNode))
      } else {
        child = .selections([:])
      }
    }

    private init(
      scope: ScopeCondition,
      type: GraphQLCompositeType,
      rootTypePathNode: LinkedList<GraphQLCompositeType>.Node
    ) {
      self.scope = scope
      self.type = type
      self.rootTypePathNode = rootTypePathNode
    }

    fileprivate func mergeIn(
      _ selections: DirectSelections.ReadOnly,
      from source: MergedSelections.MergedSource
    ) {
      updateSelections {
        $0.updateValue(forKey: source, default: EntityTreeScopeSelections()) {
          $0.mergeIn(selections)
        }
      }
    }

    fileprivate func mergeIn(
      _ selections: EntityTreeScopeSelections,
      from source: MergedSelections.MergedSource
    ) {
      updateSelections {
        $0.updateValue(forKey: source, default: EntityTreeScopeSelections()) {
          $0.mergeIn(selections)
        }
      }
    }

    private func updateSelections(_ block: (inout Selections) -> Void) {
      var entitySelections: Selections

      switch child {
      case .entity:
        fatalError(
          "Selection Merging Error. Please create an issue on Github to report this."
        )

      case let .selections(currentSelections):
        entitySelections = currentSelections

      case .none:
        entitySelections = Selections()
      }

      block(&entitySelections)
      self.child = .selections(entitySelections)
    }

    func mergeSelections(
      matchingScopePath scopePathNode: LinkedList<ScopeDescriptor>.Node,
      into targetSelections: ComputedSelectionSet.Builder,
      transformingSelections: ((Selections) -> Selections)?
    ) {
      switch child {
      case let .entity(entityNode):
        guard let nextScopePathNode = scopePathNode.next else { return }
        entityNode.mergeSelections(
          matchingScopePath: nextScopePathNode,
          into: targetSelections,
          transformingSelections: transformingSelections
        )

      case let .selections(selections):
        let selections = transformingSelections?(selections) ?? selections
        for (source, scopeSelections) in selections {
          targetSelections.mergeIn(scopeSelections, from: source)
        }

        if let conditionalScopes = scopeConditions {
          for (condition, node) in conditionalScopes {
            guard !node.scope.isDeferred else { continue }

            if scopePathNode.value.matches(condition) {
              node.mergeSelections(
                matchingScopePath: scopePathNode,
                into: targetSelections,
                transformingSelections: transformingSelections
              )

            } else {
              targetSelections.addMergedInlineFragment(with: condition)
            }
          }
        }

      case .none: break
      }

      if let scopeConditions = scopeConditions {
        for (condition, node) in scopeConditions {
          guard !node.scope.isDeferred else { continue }

          if scopePathNode.value.matches(condition) {
            node.mergeSelections(
              matchingScopePath: scopePathNode,
              into: targetSelections,
              transformingSelections: transformingSelections
            )
          }
        }
      }

      // Add selections from merged fragments
      for (fragmentSpread, mergedFragmentTree) in mergedFragmentTrees {
        mergedFragmentTree.rootNode.mergeSelections(
          matchingScopePath: scopePathNode,
          into: targetSelections,
          transformingSelections: {
            Self.transform(
              selections: $0,
              fromFragment: fragmentSpread
            )
          }
        )
      }
    }

    private static func transform(
      selections: Selections,
      fromFragment fragment: IR.NamedFragmentSpread
    ) -> Selections {
      var newSelections = Selections()

      for source in selections.keys {
        let newSource = source.fragment != nil ? source :
        IR.MergedSelections.MergedSource(
          typeInfo: source.typeInfo, fragment: fragment.fragment
        )

        newSelections[newSource] = selections[source]
      }

      return newSelections
    }

    /// MARK: Create/Get Child Nodes

    fileprivate func childAsEntityNode() -> EntityNode {
      switch child {
      case let .entity(node):
        return node

      case .selections:
        fatalError(
          "Selection Merging Error. Please create an issue on Github to report this."
        )

      case .none:
        let node = EntityNode(typeNode: self.rootTypePathNode.next!)
        self.child = .entity(node)
        return node
      }
    }

    fileprivate func scopeConditionNode(for condition: ScopeCondition) -> EntityNode {
      let nodeCondition = ScopeCondition(
        type: condition.type == self.type ? nil : condition.type,
        conditions: condition.conditions,
        deferCondition: condition.deferCondition
      )

      func createNode() -> EntityNode {
        // When initializing as a conditional scope node, if the `scope` does not have a
        // type condition, we should inherit the parent node's type.
        let nodeType = nodeCondition.type ?? self.type

        return EntityNode(
          scope: nodeCondition,
          type: nodeType,
          rootTypePathNode: self.rootTypePathNode
        )
      }

      guard var scopeConditions = scopeConditions else {
        let node = createNode()
        self.scopeConditions = [nodeCondition: node]
        return node
      }

      guard let node = scopeConditions[condition] else {
        let node = createNode()
        scopeConditions[nodeCondition] = node
        self.scopeConditions = scopeConditions
        return node
      }

      return node
    }
  }
}

class EntityTreeScopeSelections: Equatable {

  fileprivate(set) var fields: OrderedDictionary<String, Field> = [:]
  fileprivate(set) var namedFragments: OrderedDictionary<String, NamedFragmentSpread> = [:]

  init() {}

  fileprivate init(
    fields: OrderedDictionary<String, Field>,
    namedFragments: OrderedDictionary<String, NamedFragmentSpread>
  ) {
    self.fields = fields
    self.namedFragments = namedFragments
  }

  var isEmpty: Bool {
    fields.isEmpty && namedFragments.isEmpty
  }

  private func mergeIn(_ field: Field) {
    fields[field.hashForSelectionSetScope] = field
  }

  private func mergeIn<T: Sequence>(_ fields: T) where T.Element == Field {
    fields.forEach { mergeIn($0) }
  }

  private func mergeIn(_ fragment: NamedFragmentSpread) {
    namedFragments[fragment.hashForSelectionSetScope] = fragment
  }

  private func mergeIn<T: Sequence>(_ fragments: T) where T.Element == NamedFragmentSpread {
    fragments.forEach { mergeIn($0) }
  }

  func mergeIn(_ selections: DirectSelections.ReadOnly) {
    mergeIn(selections.fields.values)
    mergeIn(selections.namedFragments.values)
  }

  func mergeIn(_ selections: EntityTreeScopeSelections) {
    mergeIn(selections.fields.values)
    mergeIn(selections.namedFragments.values)
  }

  static func == (lhs: EntityTreeScopeSelections, rhs: EntityTreeScopeSelections) -> Bool {
    lhs.fields == rhs.fields &&
    lhs.namedFragments == rhs.namedFragments
  }
}

// MARK: - Merge In Other Entity Trees

extension EntitySelectionTree {

  /// Merges an `EntitySelectionTree` from a matching `Entity` in the given `FragmentSpread`
  /// into the receiver.
  ///
  /// - Precondition: This function assumes that the `EntitySelectionTree` being merged in
  /// represents the same entity in the response. Passing a non-matching entity is a serious
  /// programming error and will result in undefined behavior.
  func mergeIn(
    _ otherTree: EntitySelectionTree,
    from fragmentSpread: IR.NamedFragmentSpread
  ) {
    let otherTreeCount = otherTree.rootTypePath.count
    let diffToRoot = rootTypePath.count - otherTreeCount

    precondition(diffToRoot >= 0, "Cannot merge in tree shallower than current tree.")

    var rootEntityToStartMerge: EntityNode = rootNode

    for _ in 0..<diffToRoot {
      rootEntityToStartMerge = rootEntityToStartMerge.childAsEntityNode()
    }

    rootEntityToStartMerge.mergeIn(
      otherTree,
      from: fragmentSpread
    )
  }

}

extension EntitySelectionTree.EntityNode {

  private func findOrCreate(
    fromFragmentScopeNode fragmentNode: LinkedList<ScopeCondition>.Node,
    from rootNode: EntitySelectionTree.EntityNode
  ) -> EntitySelectionTree.EntityNode {
    guard let nextFragmentNode = fragmentNode.next else {
      return rootNode
    }
    let nextNode = rootNode.scopeConditionNode(for: nextFragmentNode.value)
    return findOrCreate(fromFragmentScopeNode: nextFragmentNode, from: nextNode)
  }

  fileprivate func mergeIn(
    _ fragmentTree: EntitySelectionTree,
    from fragmentSpread: IR.NamedFragmentSpread
  ) {
    let rootNodeToStartMerge = findOrCreate(
      fromFragmentScopeNode: fragmentSpread.typeInfo.scopePath.last.value.scopePath.head,
      from: self
    )

    let fragmentType = fragmentSpread.typeInfo.parentType
    let rootTypesMatch = rootNodeToStartMerge.type == fragmentType

    if let inclusionConditions = fragmentSpread.inclusionConditions {
      for conditionGroup in inclusionConditions.elements {
        let scope = ScopeCondition(
          type: rootTypesMatch ? nil : fragmentType,
          conditions: conditionGroup
        )
        let nodeForMerge = rootNodeToStartMerge.scopeConditionNode(for: scope)

        nodeForMerge.mergedFragmentTrees[fragmentSpread] = fragmentTree
      }

    } else {
      let nodeForMerge = rootTypesMatch ?
      rootNodeToStartMerge :
      rootNodeToStartMerge.scopeConditionNode(
        for: ScopeCondition(type: fragmentType)
      )

      nodeForMerge.mergedFragmentTrees[fragmentSpread] = fragmentTree
    }
  }

}

// MARK: - CustomDebugStringConvertible

extension EntitySelectionTree: CustomDebugStringConvertible {
  var debugDescription: String {
    """
    rootTypePath: \(rootTypePath.debugDescription)
    \(rootNode.debugDescription)
    """
  }
}

extension EntitySelectionTree.EntityNode: CustomDebugStringConvertible {
  var debugDescription: String {
    TemplateString("""
    \(scope.debugDescription) {
      \(child?.debugDescription ?? "child: nil")
      \(ifLet: scopeConditions?.values, where: { !$0.isEmpty },
         "conditionalScopes: [\(list: scopeConditions?.values.elements ?? [])]"
      )
      \(if: !mergedFragmentTrees.isEmpty,
         "mergedFragmentTrees: \(mergedFragmentTrees.debugDescription)"
      )
    }
    """).description
  }
}

extension EntitySelectionTree.EntityNode.Child: CustomDebugStringConvertible {
  var debugDescription: String {
    func debugDescription(for selections: EntitySelectionTree.EntityNode.Selections) -> String {
      TemplateString("""
      [
      \(selections.map {
        TemplateString("""
          Source: \($0.key.debugDescription)
            \($0.value.debugDescription)
        """)
      })
      ]
      """).description
    }

    switch self {
    case let .entity(node):
      return "child: \(node.debugDescription)"

    case let .selections(selections):
      return TemplateString("selections: \(debugDescription(for: selections))").description
    }
  }

}

extension EntityTreeScopeSelections: CustomDebugStringConvertible {
  var debugDescription: String {
    """
    Fields: \(fields.values.elements)
    Fragments: \(namedFragments.values.elements.description)
    """
  }
}
