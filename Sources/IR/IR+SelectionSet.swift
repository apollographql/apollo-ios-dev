import GraphQLCompiler
import TemplateString
import Utilities

@dynamicMemberLookup
public class SelectionSet: Hashable, CustomDebugStringConvertible {
  public class TypeInfo: Hashable, CustomDebugStringConvertible {
    /// The entity that the `selections` are being selected on.
    ///
    /// Multiple `SelectionSet`s may reference the same `Entity`
    public let entity: Entity

    /// A list of the scopes for the `SelectionSet` and its enclosing entities.
    ///
    /// The selection set's `scope` is the last element in the list.
    public let scopePath: LinkedList<ScopeDescriptor>

    /// Describes all of the types and inclusion conditions the selection set matches.
    /// Derived from all the selection set's parents.
    public var scope: ScopeDescriptor { scopePath.last.value }

    public var parentType: GraphQLCompositeType { scope.type }

    public var inclusionConditions: InclusionConditions? { scope.scopePath.last.value.conditions }

    /// Indicates if the `SelectionSet` represents a root selection set.
    /// If `true`, the `SelectionSet` belongs to a field directly.
    /// If `false`, the `SelectionSet` belongs to a conditional selection set enclosed
    /// in a field's `SelectionSet`.
    public var isEntityRoot: Bool { scope.scopePath.head.next == nil }

    init(
      entity: Entity,
      scopePath: LinkedList<ScopeDescriptor>
    ) {
      self.entity = entity
      self.scopePath = scopePath
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

  public class Selections: CustomDebugStringConvertible {
    /// The selections that are directly selected by this selection set.
    public let direct: DirectSelections?

    /// The selections that are available to be accessed by this selection set.
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
    public private(set) lazy var merged: MergedSelections = {
      let mergedSelections = MergedSelections(
        directSelections: self.direct?.readOnlyView,
        typeInfo: self.typeInfo
      )
      typeInfo.entity.selectionTree.addMergedSelections(into: mergedSelections)

      return mergedSelections
    }()

    private let typeInfo: TypeInfo

    fileprivate init(
      typeInfo: TypeInfo,
      directSelections: DirectSelections?
    ) {
      self.typeInfo = typeInfo
      self.direct = directSelections
    }

    public var debugDescription: String {
      TemplateString("""
        direct: {
          \(direct?.debugDescription ?? "nil")
        }
        merged: {
          \(merged.debugDescription)
        }
        """).description
    }
  }

  // MARK:  - SelectionSet

  public let typeInfo: TypeInfo
  public let selections: Selections

  init(
    entity: Entity,
    scopePath: LinkedList<ScopeDescriptor>,
    mergedSelectionsOnly: Bool = false
  ) {
    self.typeInfo = TypeInfo(
      entity: entity,
      scopePath: scopePath
    )
    self.selections = Selections(
      typeInfo: self.typeInfo,
      directSelections: mergedSelectionsOnly ? nil : DirectSelections()
    )
  }

  init(
    entity: Entity,
    scopePath: LinkedList<ScopeDescriptor>,
    selections: DirectSelections
  ) {
    self.typeInfo = TypeInfo(
      entity: entity,
      scopePath: scopePath
    )
    self.selections = Selections(
      typeInfo: self.typeInfo,
      directSelections: selections
    )
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
    lhs.selections.direct === rhs.selections.direct
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(typeInfo)
    if let directSelections = selections.direct {
      hasher.combine(ObjectIdentifier(directSelections))
    }
  }

  public subscript<T>(dynamicMember keyPath: KeyPath<TypeInfo, T>) -> T {
    typeInfo[keyPath: keyPath]
  }

}
