import Foundation
import OrderedCollections

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
