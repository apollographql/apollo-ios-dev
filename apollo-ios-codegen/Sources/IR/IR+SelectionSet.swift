import GraphQLCompiler
import TemplateString
import Utilities

@dynamicMemberLookup
public class SelectionSet: Hashable, CustomDebugStringConvertible {
  public class TypeInfo: Hashable, CustomDebugStringConvertible {
    /// The entity that the `selections` are being selected on.
    ///
    /// Multiple `SelectionSet`s may reference the same `Entity`
    public unowned let entity: Entity

    /// A list of the scopes for the `SelectionSet` and its enclosing entities.
    ///
    /// The selection set's `scope` is the last element in the list.
    public let scopePath: LinkedList<ScopeDescriptor>

    public var isUserDefined: Bool

    // MARK: - Computed Properties

    /// Describes all of the types and inclusion conditions the selection set matches.
    /// Derived from all the selection set's parents.
    public var scope: ScopeDescriptor { scopePath.last.value }

    public var parentType: GraphQLCompositeType { scope.type }

    public var inclusionConditions: InclusionConditions? {
      scope.scopePath.last.value.conditions
    }

    public var deferCondition: CompilationResult.DeferCondition? {
      scope.scopePath.last.value.deferCondition
    }

    public var isDeferred: Bool { deferCondition != nil }

    /// Indicates if the `SelectionSet` represents a root selection set.
    /// If `true`, the `SelectionSet` belongs to a field directly.
    /// If `false`, the `SelectionSet` belongs to a conditional selection set enclosed
    /// in a field's `SelectionSet`.
    public var isEntityRoot: Bool { scope.scopePath.head.next == nil }

    init(
      entity: Entity,
      scopePath: LinkedList<ScopeDescriptor>,
      isUserDefined: Bool
    ) {
      self.entity = entity
      self.scopePath = scopePath
      self.isUserDefined = isUserDefined
    }

    public static func == (lhs: TypeInfo, rhs: TypeInfo) -> Bool {
      lhs.entity === rhs.entity &&
      lhs.scopePath == rhs.scopePath
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(ObjectIdentifier(entity))
      hasher.combine(scopePath)
    }

    public var debugDescription: String {
      scopePath.debugDescription
    }
  }

  // MARK:  - SelectionSet

  public let typeInfo: TypeInfo
  /// The selections that are directly selected by this selection set.
  ///
  /// To get the merged selections, use a `MergedSelections.Builder`.
  public let selections: DirectSelections?

  init(
    typeInfo: TypeInfo,
    selections: DirectSelections?
  ) {
    self.typeInfo = typeInfo
    self.selections = selections
  }

  public var debugDescription: String {
    TemplateString("""
      SelectionSet on \(typeInfo.parentType.debugDescription)\(ifLet: typeInfo.inclusionConditions, { " \($0.debugDescription)"})  {
        \(self.selections.debugDescription)
      }
      """).description
  }

  public static func ==(lhs: SelectionSet, rhs: SelectionSet) -> Bool {
    lhs.typeInfo === rhs.typeInfo &&
    lhs.selections === rhs.selections
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(typeInfo)
    if let selections {
      hasher.combine(ObjectIdentifier(selections))
    }
  }

  public subscript<T>(dynamicMember keyPath: KeyPath<TypeInfo, T>) -> T {
    typeInfo[keyPath: keyPath]
  }

}

extension LinkedList where T == ScopeCondition {
  var containsDeferredFragment: Bool {
    var node: Node? = last

    repeat {
      guard node?.value.deferCondition == nil else {
        return true
      }
      node = node?.previous
    } while node != nil
              
    return false
  }
}
