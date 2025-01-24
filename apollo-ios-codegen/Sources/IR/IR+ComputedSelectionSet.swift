import Foundation
import GraphQLCompiler
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
  
  /// Indicates if the parent type has a single keyField named `id`.
  public var isIdentifiable: Bool {
    guard direct?.fields["id"] != nil || merged.fields["id"] != nil else {
      return false
    }
    if let type = typeInfo.parentType as? GraphQLObjectType,
       type.keyFields == ["id"] {
      return true
    }
    
    if let type = typeInfo.parentType as? GraphQLInterfaceType,
       type.keyFields == ["id"] {
      return true
    }
    
    return false
  }

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
    public let mergingStrategy: MergedSelections.MergingStrategy

    public fileprivate(set) var mergedSources: OrderedSet<MergedSelections.MergedSource> = []
    public fileprivate(set) var fields: OrderedDictionary<String, Field> = [:]
    public fileprivate(set) var inlineFragments: OrderedDictionary<ScopeCondition, InlineFragmentSpread> = [:]
    public fileprivate(set) var namedFragments: OrderedDictionary<String, NamedFragmentSpread> = [:]

    public init(
      directSelections: DirectSelections.ReadOnly?,
      typeInfo: SelectionSet.TypeInfo,
      mergingStrategy: MergedSelections.MergingStrategy,
      entityStorage: DefinitionEntityStorage
    ) {
      precondition(
        typeInfo.entity.location.source == entityStorage.sourceDefinition,
        "typeInfo and entityStorage must originate from the same definition."
      )
      self.directSelections = directSelections
      self.typeInfo = typeInfo
      self.entityStorage = entityStorage
      self.mergingStrategy = mergingStrategy
    }

    public convenience init(
      _ selectionSet: IR.SelectionSet,
      mergingStrategy: MergedSelections.MergingStrategy,
      entityStorage: DefinitionEntityStorage
    ) {
      self.init(
        directSelections: selectionSet.selections?.readOnlyView,
        typeInfo: selectionSet.typeInfo,
        mergingStrategy: mergingStrategy,
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
      with sourceMergeStrategy: MergedSelections.MergingStrategy
    ) {
      guard shouldMergeIn(source: source, with: sourceMergeStrategy) else {
        return
      }

      @IsEverTrue var didMergeAnySelections: Bool

      selectionsToMerge.fields.values.forEach {
        didMergeAnySelections = self.mergeIn($0, from: source)
      }

      selectionsToMerge.namedFragments.values.forEach { didMergeAnySelections = self.mergeIn($0) }

      if didMergeAnySelections {
        mergedSources.append(source)
      }
    }

    private func shouldMergeIn(
      source: MergedSelections.MergedSource,
      with sourceMergeStrategy: MergedSelections.MergingStrategy
    ) -> Bool {
      return shouldMergeIn(from: [source], with: sourceMergeStrategy)
    }

    private func shouldMergeIn(
      from sources: OrderedSet<MergedSelections.MergedSource>,
      with sourceMergeStrategy: MergedSelections.MergingStrategy
    ) -> Bool {
      if self.mergingStrategy.contains(sourceMergeStrategy) { return true }

      for source in sources {
        if self.typeInfo.derivedFromMergedSources.contains(where: {
          return  $0.typeInfo.scopePath == source.typeInfo.scopePath &&
          $0.fragment == source.fragment
        }) {
          return true
        }
      }
      return false
    }

    private func mergeIn(
      _ field: Field,
      from mergedSource: MergedSelections.MergedSource
    ) -> Bool {
      let keyInScope = field.hashForSelectionSetScope
      if let directSelections = directSelections,
         directSelections.fields.keys.contains(keyInScope) {
        return false
      }

      let fieldToMerge: Field = {
        guard let entityField = field as? EntityField else {
          return field
        }

        let newEntityField = createOrFindShallowlyMergedNestedEntityField(from: entityField)
        let fieldMergedSource = MergedSelections.MergedSource(
          typeInfo: entityField.selectionSet.typeInfo,
          fragment: mergedSource.fragment
        )
        newEntityField.selectionSet.typeInfo.derivedFromMergedSources.insert(fieldMergedSource)
        return newEntityField
      }()

      fields[keyInScope] = fieldToMerge
      return true
    }

    private func createOrFindShallowlyMergedNestedEntityField(from field: EntityField) -> EntityField {
      if let existingMergedField = self.fields[field.hashForSelectionSetScope] as? EntityField {
        return existingMergedField
      }

      let typeInfo = SelectionSet.TypeInfo(
        entity: entityStorage.entity(for: field.underlyingField, on: typeInfo.entity),
        scopePath: self.typeInfo.scopePath.appending(field.selectionSet.typeInfo.scope)
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

    func addMergedInlineFragment(
      with condition: ScopeCondition,
      from mergedSources: OrderedSet<MergedSelections.MergedSource>,
      mergeStrategy: MergedSelections.MergingStrategy
    ) {
      guard typeInfo.isEntityRoot &&
              self.shouldMergeIn(from: mergedSources, with: mergeStrategy) else {
        return
      }

      if let directSelections = directSelections,
         directSelections.inlineFragments.keys.contains(condition) {
        return
      }

      let inlineFragmentToMerge = createOrFindShallowlyMergedCompositeInlineFragment(
        with: condition
      )
      inlineFragmentToMerge.selectionSet.typeInfo.derivedFromMergedSources.formUnion(mergedSources)

      inlineFragments[condition] = inlineFragmentToMerge
    }

    private func createOrFindShallowlyMergedCompositeInlineFragment(
      with condition: ScopeCondition
    ) -> InlineFragmentSpread {
      if let inlineFragment = self.inlineFragments[condition] { return inlineFragment }

      let typeInfo = SelectionSet.TypeInfo(
        entity: self.typeInfo.entity,
        scopePath: self.typeInfo.scopePath.mutatingLast { $0.appending(condition) }
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
      let mergedSelections = MergedSelections(
        mergedSources: mergedSources,
        mergingStrategy: mergingStrategy,
        fields: fields,
        inlineFragments: inlineFragments,
        namedFragments: namedFragments
      )

      return ComputedSelectionSet(
        direct: directSelections,
        merged: mergedSelections,
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
