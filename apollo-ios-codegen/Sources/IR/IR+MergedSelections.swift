import Foundation
import OrderedCollections
import Utilities

#warning("TODO: Update this documentation")
/// The selections that are available to be accessed by a selection set.
///
/// Includes the direct `selections`, along with all selections from other related
/// `SelectionSet`s on the same entity that match the selection set's type scope.
///
/// Selections in the `mergedSelections` are guaranteed to be selected if this `SelectionSet`'s
/// `selections` are selected. This means they can be merged into the generated object
/// representing this `SelectionSet` as field accessors.
///
/// - Precondition: The `directSelections` for all `SelectionSet`s in the operation must be
/// completed prior to first access of `mergedSelections`. Otherwise, the merged selections
/// will be incomplete.
public struct MergedSelections: Equatable {
  public let mergedSources: OrderedSet<MergedSource>
  public let fields: OrderedDictionary<String, Field>
  public let inlineFragments: OrderedDictionary<ScopeCondition, InlineFragmentSpread>
  public let namedFragments: OrderedDictionary<String, NamedFragmentSpread>

  var isEmpty: Bool {
    fields.isEmpty && inlineFragments.isEmpty && namedFragments.isEmpty
  }

  public static func == (lhs: MergedSelections, rhs: MergedSelections) -> Bool {
    lhs.mergedSources == rhs.mergedSources &&
    lhs.fields == rhs.fields &&
    lhs.inlineFragments == rhs.inlineFragments &&
    lhs.namedFragments == rhs.namedFragments
  }
}

// MARK: - MergedSource
extension MergedSelections {
  public struct MergedSource: Hashable {
    /// The `TypeInfo` of the `SelectionSet` that is the source of the merged selections.
    public let typeInfo: SelectionSet.TypeInfo

    /// The `NamedFragment` that the merged `SelectionSet` was contained in.
    ///
    /// - Note: If `fragment` is present, the `typeInfo` is relative to the fragment,
    /// instead of the operation directly.
    public unowned let fragment: NamedFragment?
  }
}

// MARK: - MergedSelections Builder

extension MergedSelections {
  public class Builder {
    let typeInfo: SelectionSet.TypeInfo
    private let directSelections: DirectSelections.ReadOnly?
    private let entityStorage: RootFieldEntityStorage

    public fileprivate(set) var mergedSources: OrderedSet<MergedSource> = []
    public fileprivate(set) var fields: OrderedDictionary<String, Field> = [:]
    public fileprivate(set) var inlineFragments: OrderedDictionary<ScopeCondition, InlineFragmentSpread> = [:]
    public fileprivate(set) var namedFragments: OrderedDictionary<String, NamedFragmentSpread> = [:]

    init(
      directSelections: DirectSelections.ReadOnly?,
      typeInfo: SelectionSet.TypeInfo,
      entityStorage: RootFieldEntityStorage
    ) {
      precondition(
        typeInfo.entity.location.source == entityStorage.sourceDefinition,
        "typeInfo and entityStorage much originate from the same definition."
      )
      self.directSelections = directSelections
      self.typeInfo = typeInfo
      self.entityStorage = entityStorage
    }

    func build() -> MergedSelections {
      typeInfo.entity.selectionTree.addMergedSelections(into: self)
      return finalize()
    }

    func mergeIn(_ selections: EntityTreeScopeSelections, from source: MergedSource) {
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
        scopePath: self.typeInfo.scopePath.mutatingLast { $0.appending(condition) }
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

    fileprivate func finalize() -> MergedSelections {
      MergedSelections(
        mergedSources: mergedSources,
        fields: fields,
        inlineFragments: inlineFragments,
        namedFragments: namedFragments
      )
    }
  }
}

// MARK: - CustomDebugStringConvertible

extension MergedSelections: CustomDebugStringConvertible {
  public var debugDescription: String {
      """
      Merged Sources: \(mergedSources)
      Fields: \(fields.values.elements)
      InlineFragments: \(inlineFragments.values.elements.map(\.debugDescription))
      NamedFragments: \(namedFragments.values.elements.map(\.debugDescription))
      """
  }
}

extension MergedSelections.MergedSource: CustomDebugStringConvertible {
  public var debugDescription: String {
    typeInfo.debugDescription + ", fragment: \(fragment?.debugDescription ?? "nil")"
  }
}

extension MergedSelections.Builder: CustomDebugStringConvertible {
  public var debugDescription: String { finalize().debugDescription }
}
