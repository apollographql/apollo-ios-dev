/// Represents an Inline Fragment that has been "spread into" another SelectionSet using the
/// spread operator (`...`).
public class InlineFragmentSpread: Hashable, CustomDebugStringConvertible {
  /// The `SelectionSet` representing the inline fragment that has been "spread into" its
  /// enclosing operation/fragment.
  public let selectionSet: SelectionSet

  /// Indicates the location where the inline fragment has been "spread into" its enclosing
  /// operation/fragment.
  public var typeInfo: SelectionSet.TypeInfo { selectionSet.typeInfo }

  public var inclusionConditions: InclusionConditions? { selectionSet.inclusionConditions }

  init(selectionSet: SelectionSet) {
    self.selectionSet = selectionSet
  }

  public static func == (lhs: InlineFragmentSpread, rhs: InlineFragmentSpread) -> Bool {
    lhs.selectionSet == rhs.selectionSet
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(selectionSet)
  }

  public var debugDescription: String {
    var string = typeInfo.parentType.debugDescription
    if let conditions = typeInfo.inclusionConditions {
      string += " \(conditions.debugDescription)"
    }
    if let deferCondition = typeInfo.deferCondition {
      string += " \(deferCondition.debugDescription)"
    }

    return string
  }
}
