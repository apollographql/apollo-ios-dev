import Foundation
import OrderedCollections
import Utilities

/// A data structure representing the computed selections for a `SelectionSet`.
/// This includes both the direct and merged selections.
///
/// Because the computed merged selections are expected to have a large number of duplicated
/// selections, they use a large amount of memory. Storing them on the `IR.SelectionSet` would
/// retain them outside of the scope they are needed. Instead, we use a
/// `ComputedSelectionSet.Builder` to compute them for the scope they are needed in, then release 
/// them when we are done with them.
@dynamicMemberLookup
public struct ComputedSelectionSet {

  public let direct: IR.DirectSelections.ReadOnly?
  public let merged: [IR.MergedSelections.MergingStrategy: IR.MergedSelections]

  /// The `TypeInfo` for the selection set of the computed selections
  public let typeInfo: IR.SelectionSet.TypeInfo

  // MARK: Dynamic Member Subscript

  public subscript<T>(dynamicMember keyPath: KeyPath<SelectionSet.TypeInfo, T>) -> T {
    typeInfo[keyPath: keyPath]
  }
}

// MARK: - ComputedSelectionSet Builder

extension ComputedSelectionSet {
  public class Builder {
    private typealias MergedSelectionGroups = [MergedSelections.MergingStrategy: MergedSelectionCollector]

    let typeInfo: SelectionSet.TypeInfo
    private let directSelections: DirectSelections.ReadOnly?
    private let entityStorage: DefinitionEntityStorage
    private let mergedSelectionGroups: MergedSelectionGroups

    public init(
      directSelections: DirectSelections.ReadOnly?,
      typeInfo: SelectionSet.TypeInfo,
      mergingStrategies: Set<MergedSelections.MergingStrategy>,
      entityStorage: DefinitionEntityStorage
    ) {
      precondition(
        typeInfo.entity.location.source == entityStorage.sourceDefinition,
        "typeInfo and entityStorage must originate from the same definition."
      )
      self.directSelections = directSelections
      self.typeInfo = typeInfo
      self.entityStorage = entityStorage

      var mergedSelectionGroups = MergedSelectionGroups(minimumCapacity: mergingStrategies.count)
      for strategy in mergingStrategies {
        mergedSelectionGroups.updateValue(.init(), forKey: strategy)
      }
      self.mergedSelectionGroups = mergedSelectionGroups
    }

    public convenience init(
      _ selectionSet: IR.SelectionSet,
      mergingStrategies: Set<MergedSelections.MergingStrategy>,
      entityStorage: DefinitionEntityStorage
    ) {
      self.init(
        directSelections: selectionSet.selections?.readOnlyView,
        typeInfo: selectionSet.typeInfo,
        mergingStrategies: mergingStrategies,
        entityStorage: entityStorage
      )
    }

    // MARK: Build

    public func build() -> ComputedSelectionSet {
      typeInfo.entity.selectionTree.addMergedSelections(into: self)
      return finalize()
    }

    func mergeIn(
      _ selectionsToMerge: EntityTreeScopeSelections,
      from source: MergedSelections.MergedSource,
      with mergeStrategy: MergedSelections.MergingStrategy
    ) {
      let fieldsToMerge = self.fieldsToMerge(
        from: selectionsToMerge.fields.values
      )
      let fragmentsToMerge = self.namedFragmentsToMerge(
        from: selectionsToMerge.namedFragments.values
      )
      guard !fieldsToMerge.isEmpty || !fragmentsToMerge.isEmpty else { return }

      for (groupMergeStrategy, selections) in mergedSelectionGroups {
        guard groupMergeStrategy.contains(mergeStrategy) else { continue }

        selections.mergeIn(
          fields: fieldsToMerge,
          namedFragments: fragmentsToMerge,
          from: source
        )
      }
    }    

    private func fieldsToMerge<S: Sequence>(
      from fields: S
    ) -> [Field] where S.Element == Field {
      fields.compactMap { field in
        let keyInScope = field.hashForSelectionSetScope
        if let directSelections = directSelections,
           directSelections.fields.keys.contains(keyInScope) {
          return nil
        }

        if let entityField = field as? EntityField {
          return createShallowlyMergedNestedEntityField(from: entityField)

        } else {
          return field
        }
      }
    }

    private func createShallowlyMergedNestedEntityField(from field: EntityField) -> EntityField {
      let typeInfo = SelectionSet.TypeInfo(
        entity: entityStorage.entity(for: field.underlyingField, on: typeInfo.entity),
        scopePath: self.typeInfo.scopePath.appending(field.selectionSet.typeInfo.scope),
        isUserDefined: false
      )

      let newSelectionSet = SelectionSet(
        typeInfo: typeInfo,
        selections: nil
      )

      return EntityField(
        field.underlyingField,
        inclusionConditions: field.inclusionConditions,
        selectionSet: newSelectionSet
      )
    }

    private func namedFragmentsToMerge<S: Sequence>(
      from fragments: S
    ) -> [NamedFragmentSpread] where S.Element == NamedFragmentSpread {
      fragments.filter { fragment in
        let keyInScope = fragment.hashForSelectionSetScope
        if let directSelections = directSelections,
           directSelections.namedFragments.keys.contains(keyInScope) {
          return false
        }

        return true
      }
    }

    func addMergedInlineFragment(
      with condition: ScopeCondition,
      mergeStrategy: MergedSelections.MergingStrategy
    ) {
      guard typeInfo.isEntityRoot else { return }

      if let directSelections = directSelections,
         directSelections.inlineFragments.keys.contains(condition) {
        return
      }

      lazy var shallowInlineFragment = {
        self.createShallowlyMergedInlineFragment(with: condition)
      }()

      for (groupMergeStrategy, selections) in mergedSelectionGroups {
        guard groupMergeStrategy.contains(mergeStrategy) else { continue }

        selections.inlineFragments[condition] = shallowInlineFragment
      }
    }

    private func createShallowlyMergedInlineFragment(
      with condition: ScopeCondition
    ) -> InlineFragmentSpread {
      let typeInfo = SelectionSet.TypeInfo(
        entity: self.typeInfo.entity,
        scopePath: self.typeInfo.scopePath.mutatingLast { $0.appending(condition) },
        isUserDefined: false
      )

      let selectionSet = SelectionSet(
        typeInfo: typeInfo,
        selections: nil
      )

      return InlineFragmentSpread(
        selectionSet: selectionSet
      )
    }

    fileprivate func finalize() -> ComputedSelectionSet {
      var mergedSelections: [MergedSelections.MergingStrategy: MergedSelections] =
      Dictionary(minimumCapacity: mergedSelectionGroups.count)

      mergedSelectionGroups.forEach { strategy, selections in
        mergedSelections[strategy] =
        MergedSelections(
          mergedSources: selections.mergedSources,
          mergingStrategy: strategy,
          fields: selections.fields,
          inlineFragments: selections.inlineFragments,
          namedFragments: selections.namedFragments
        )
      }

      return ComputedSelectionSet(
        direct: directSelections,
        merged: mergedSelections,
        typeInfo: typeInfo
      )
    }
  }

  /// Collects the merged selections for a specific
  /// ``MergedSelections/MergingStrategy-swift.struct`` to be converted into a
  /// ``MergedSelections`` value during the builder's `finalize()` step.
  private class MergedSelectionCollector {
    fileprivate var mergedSources: OrderedSet<MergedSelections.MergedSource> = []
    fileprivate var fields: OrderedDictionary<String, Field> = [:]
    fileprivate var inlineFragments: OrderedDictionary<ScopeCondition, InlineFragmentSpread> = [:]
    fileprivate var namedFragments: OrderedDictionary<String, NamedFragmentSpread> = [:]

    func mergeIn(
      fields: [Field],
      namedFragments: [NamedFragmentSpread],
      from source: MergedSelections.MergedSource
    ) {
      fields.forEach {
        self.fields[$0.hashForSelectionSetScope] = $0
      }
      namedFragments.forEach {
        self.namedFragments[$0.hashForSelectionSetScope] = $0
      }
      mergedSources.append(source)
    }
  }
}

extension ComputedSelectionSet: CustomDebugStringConvertible {
  public var debugDescription: String {
    """
    Direct: \(direct.debugDescription)
    Merged: \(merged.debugDescription)
    """
  }
}
