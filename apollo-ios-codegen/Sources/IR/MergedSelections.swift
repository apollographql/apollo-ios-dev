import Foundation
import OrderedCollections

/// Represents the selections that are merged into a selection set from other selection sets,
/// using the given ``MergingStrategy``. See ``MergingStrategy`` for more information on what is
/// included in the ``MergedSelections`` for a given strategy.
///
/// Selections in the `MergedSelections` are guaranteed to be selected if this `SelectionSet`'s
/// `selections` are selected. This means they can be merged into the generated object
/// representing this `SelectionSet` as field accessors.
///
/// To get the ``MergedSelections`` for a ``SelectionSet`` use a ``ComputedSelectionSet/Builder``.
public struct MergedSelections: Equatable {
  public let mergedSources: OrderedSet<MergedSource>
  public let mergingStrategy: MergingStrategy
  public let fields: OrderedDictionary<String, Field>
  public let inlineFragments: OrderedDictionary<ScopeCondition, InlineFragmentSpread>
  public let namedFragments: OrderedDictionary<String, NamedFragmentSpread>

  var isEmpty: Bool {
    fields.isEmpty && inlineFragments.isEmpty && namedFragments.isEmpty
  }

  public static func == (lhs: MergedSelections, rhs: MergedSelections) -> Bool {
    lhs.mergedSources == rhs.mergedSources &&
    lhs.mergingStrategy == rhs.mergingStrategy &&
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

// MARK: - MergingStrategy

extension MergedSelections {
  /// The ``MergingStrategy`` is used to determine what merged fields and named fragment
  /// accessors are merged into the ``MergedSelections``.
  ///
  /// ``MergedSelections`` can compute which selections from a selection set's parents, sibling
  /// inline fragments, and named fragment spreads will also be included on the response object,
  /// given the selection set's ``SelectionSet/TypeInfo``.
  public struct MergingStrategy: OptionSet, Hashable, Sendable, CustomStringConvertible {
    /// Merges fields and fragment accessors from the selection set's direct ancestors.
    public static let ancestors          = MergingStrategy(rawValue: 1 << 0)

    /// Merges fields and fragment accessors from sibling inline fragments that match the selection
    /// set's scope.
    public static let siblings           = MergingStrategy(rawValue: 1 << 1)

    /// Merges fields and fragment accessors from named fragments that have been spread into the
    /// selection set.
    public static let namedFragments     = MergingStrategy(rawValue: 1 << 2)

    /// Merges all possible fields and fragment accessors from all sources.
    ///
    /// This includes all selections from other related `SelectionSet`s on the same entity that match
    /// the selection set's type scope.
    ///
    /// When using this strategy, combining the ``MergedSelections`` with the ``DirectSelections`` 
    /// for a ``SelectionSet`` provides all selections that are available to be accessed by the
    /// selection set.
    public static let all: MergingStrategy  = [.ancestors, .siblings, .namedFragments]

    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    public var description: String {
      if self == .all { return ".all" }

      var values: [String] = []

      if self.contains(.ancestors) {
        values.append(".ancestors")
      }
      if self.contains(.siblings) {
        values.append(".siblings")
      }
      if self.contains(.namedFragments) {
        values.append(".namedFragments")
      }

      return values.description
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
