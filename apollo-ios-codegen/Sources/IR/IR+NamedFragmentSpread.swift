import GraphQLCompiler

/// Represents a Named Fragment that has been "spread into" another SelectionSet using the
/// spread operator (`...`).
///
/// While a `NamedFragment` can be shared between operations, a `NamedFragmentSpread` represents a
/// `NamedFragment` included in a specific operation.
public class NamedFragmentSpread: Hashable, CustomDebugStringConvertible {

  /// The `NamedFragment` that this fragment refers to.
  ///
  /// This is a fragment that has already been built. To "spread" the fragment in, it's entity
  /// selection trees are merged into the entity selection trees of the operation/fragment it is
  /// being spread into. This allows merged field calculations to include the fields merged in
  /// from the fragment.
  public let fragment: NamedFragment

  /// Indicates the location where the fragment has been "spread into" its enclosing
  /// operation/fragment. It's `scopePath` and `entity` reference are scoped to the operation it
  /// belongs to.
  let typeInfo: SelectionSet.TypeInfo

  public internal(set) var inclusionConditions: AnyOf<InclusionConditions>?

  public var definition: CompilationResult.FragmentDefinition { fragment.definition }

  init(
    fragment: NamedFragment,
    typeInfo: SelectionSet.TypeInfo,
    inclusionConditions: AnyOf<InclusionConditions>?
  ) {
    self.fragment = fragment
    self.typeInfo = typeInfo
    self.inclusionConditions = inclusionConditions
  }

  public static func == (lhs: NamedFragmentSpread, rhs: NamedFragmentSpread) -> Bool {
    lhs.fragment === rhs.fragment &&
    lhs.typeInfo == rhs.typeInfo &&
    lhs.inclusionConditions == rhs.inclusionConditions
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(fragment))
    hasher.combine(typeInfo)
    hasher.combine(inclusionConditions)
  }

  public var debugDescription: String {
    var description = fragment.debugDescription
    if let inclusionConditions = inclusionConditions {
      description += " \(inclusionConditions.debugDescription)"
    }

    return description
  }
}
