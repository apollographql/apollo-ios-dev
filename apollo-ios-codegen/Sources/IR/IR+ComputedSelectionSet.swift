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
  public let merged: IR.MergedSelections

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
    let typeInfo: SelectionSet.TypeInfo
    private let directSelections: DirectSelections.ReadOnly?
    private let entityStorage: DefinitionEntityStorage

    public fileprivate(set) var mergedSources: OrderedSet<MergedSelections.MergedSource> = []
    public fileprivate(set) var fields: OrderedDictionary<String, Field> = [:]
    public fileprivate(set) var inlineFragments: OrderedDictionary<ScopeCondition, InlineFragmentSpread> = [:]
    public fileprivate(set) var namedFragments: OrderedDictionary<String, NamedFragmentSpread> = [:]

    public init(
      directSelections: DirectSelections.ReadOnly?,
      typeInfo: SelectionSet.TypeInfo,
      entityStorage: DefinitionEntityStorage
    ) {
      precondition(
        typeInfo.entity.location.source == entityStorage.sourceDefinition,
        "typeInfo and entityStorage must originate from the same definition."
      )
      self.directSelections = directSelections
      self.typeInfo = typeInfo
      self.entityStorage = entityStorage
    }

    public convenience init(
      _ selectionSet: IR.SelectionSet,
      entityStorage: DefinitionEntityStorage
    ) {
      self.init(
        directSelections: selectionSet.selections?.readOnlyView,
        typeInfo: selectionSet.typeInfo,
        entityStorage: entityStorage
      )
    }

    // MARK: Build

    public func build() -> ComputedSelectionSet {
      typeInfo.entity.selectionTree.addMergedSelections(into: self)
      return finalize()
    }

    func mergeIn(_ selections: EntityTreeScopeSelections, from source: MergedSelections.MergedSource) {
      @IsEverTrue var didMergeAnySelections: Bool

      selections.fields.values.forEach { didMergeAnySelections = self.mergeIn($0) }
      selections.namedFragments.values.forEach { didMergeAnySelections = self.mergeIn($0) }

      if didMergeAnySelections {
        mergedSources.append(source)
      }
    }

    private func mergeIn(_ field: Field) -> Bool {
      let keyInScope = field.hashForSelectionSetScope
      if let directSelections = directSelections,
         directSelections.fields.keys.contains(keyInScope) {
        return false
      }

      let fieldToMerge: Field
      if let entityField = field as? EntityField {
        fieldToMerge = createShallowlyMergedNestedEntityField(from: entityField)

      } else {
        fieldToMerge = field
      }

      fields[keyInScope] = fieldToMerge
      return true
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

    private func mergeIn(_ fragment: NamedFragmentSpread) -> Bool {
      let keyInScope = fragment.hashForSelectionSetScope
      if let directSelections = directSelections,
         directSelections.namedFragments.keys.contains(keyInScope) {
        return false
      }

      namedFragments[keyInScope] = fragment

      return true
    }

    func addMergedInlineFragment(with condition: ScopeCondition) {
      guard typeInfo.isEntityRoot else { return }

      createShallowlyMergedInlineFragmentIfNeeded(with: condition)
    }

    private func createShallowlyMergedInlineFragmentIfNeeded(
      with condition: ScopeCondition
    ) {
      if let directSelections = directSelections,
         directSelections.inlineFragments.keys.contains(condition) {
        return
      }

      guard !inlineFragments.keys.contains(condition) else { return }

      let typeInfo = SelectionSet.TypeInfo(
        entity: self.typeInfo.entity,
        scopePath: self.typeInfo.scopePath.mutatingLast { $0.appending(condition) },
        isUserDefined: false
      )

      let selectionSet = SelectionSet(
        typeInfo: typeInfo,
        selections: nil
      )

      let inlineFragment = InlineFragmentSpread(
        selectionSet: selectionSet
      )

      inlineFragments[condition] = inlineFragment
    }

    fileprivate func finalize() -> ComputedSelectionSet {
      let merged = MergedSelections(
        mergedSources: mergedSources,
        mergingStrategy: .all,
        fields: fields,
        inlineFragments: inlineFragments,
        namedFragments: namedFragments
      )
      return ComputedSelectionSet(
        direct: directSelections,
        merged: merged,
        typeInfo: typeInfo
      )
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
