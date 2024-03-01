import Foundation
import OrderedCollections
import GraphQLCompiler
import Utilities

// TODO: Write tests that two inline fragments with same type and inclusion conditions,
// but different defer conditions don't  merge together.
// To be done in issue #3141
public struct ScopeCondition: Hashable, CustomDebugStringConvertible {
  public let type: CompositeType?
  public let conditions: InclusionConditions?
  public let deferCondition: CompilationResult.DeferCondition?

  init(
    type: CompositeType? = nil,
    conditions: InclusionConditions? = nil,
    deferCondition: CompilationResult.DeferCondition? = nil
  ) {
    self.type = type
    self.conditions = conditions
    self.deferCondition = deferCondition
  }

  public var debugDescription: String {
    [type?.debugDescription, conditions?.debugDescription, deferCondition?.debugDescription]
      .compactMap { $0 }
      .joined(separator: " ")
  }

  var isEmpty: Bool {
    type == nil && (conditions?.isEmpty ?? true) && deferCondition == nil
  }

  public var isDeferred: Bool { deferCondition != nil }
}

public typealias TypeScope = OrderedSet<CompositeType>

/// Defines the scope for an `IR.SelectionSet`. The "scope" indicates where in the entity the
/// selection set is located, what types the `SelectionSet` implements, and what inclusion
/// conditions it requires.
public struct ScopeDescriptor: Hashable, CustomDebugStringConvertible {

  /// The parentType of the `SelectionSet`.
  ///
  /// Should always be equivalent to the last "type" value of the `scopePath`.
  public let type: CompositeType

  /// A list of the parent types/conditions for the selection set and it's parents
  /// on the same entity.
  ///
  /// For example, given the set of nested selections sets:
  /// ```
  /// object { // object field is of type "Object"
  ///  ... on A {
  ///   ... on B {
  ///     ... on C {
  ///       fieldOnABC
  ///     }
  ///   }
  /// }
  /// ```
  /// The scopePath for the `SelectionSet` that includes field `fieldOnABC` would be:
  /// `[Object, A, B, C]`.
  public let scopePath: LinkedList<ScopeCondition>

  /// All of the types that the `SelectionSet` implements. That is, all of the types in the
  /// `typePath`, all of those types implemented interfaces, and all unions that include
  /// those types.
  let matchingTypes: TypeScope

  /// All of the inclusion conditions on the entity that must be included for the `SelectionSet`
  /// to be included.
  let matchingConditions: InclusionConditions?

  public let allTypesInSchema: Schema.ReferencedTypes

  public var isDeferred: Bool { scopePath.last.value.isDeferred }

  private init(
    typePath: LinkedList<ScopeCondition>,
    type: CompositeType,
    matchingTypes: TypeScope,
    matchingConditions: InclusionConditions?,
    allTypesInSchema: Schema.ReferencedTypes
  ) {
    self.scopePath = typePath
    self.type = type
    self.matchingTypes = matchingTypes
    self.matchingConditions = matchingConditions
    self.allTypesInSchema = allTypesInSchema
  }

  /// Creates a `ScopeDescriptor` for a root `SelectionSet`.
  ///
  /// This should only be used to create a `ScopeDescriptor` for a root `SelectionSet`.
  /// Nested type cases should be created by calling `appending(_:)` on the
  /// parent `SelectionSet`'s `typeScope`.
  ///
  /// - Parameters:
  ///   - forType: The parentType for the entity.
  ///   - inclusionConditions: The `InclusionConditions` for the `SelectionSet` to be included.
  ///   - givenAllTypesInSchema: The `ReferencedTypes` object that provides information on all of
  ///                            the types in the schema.
  static func descriptor(
    forType type: CompositeType,
    inclusionConditions: InclusionConditions?,
    givenAllTypesInSchema allTypes: Schema.ReferencedTypes
  ) -> ScopeDescriptor {
    let scope = Self.typeScope(addingType: type, to: nil, givenAllTypes: allTypes)
    return ScopeDescriptor(
      typePath: LinkedList(.init(
        type: type,
        conditions: inclusionConditions
      )),
      type: type,
      matchingTypes: scope,
      matchingConditions: inclusionConditions,
      allTypesInSchema: allTypes
    )
  }

  private static func typeScope(
    addingType newType: CompositeType,
    to scope: TypeScope?,
    givenAllTypes allTypes: Schema.ReferencedTypes
  ) -> TypeScope {
    if let scope = scope, scope.contains(newType) { return scope }

    var newScope = scope ?? []
    newScope.append(newType)

    if let newType = newType as? InterfaceImplementingType {
      newScope.formUnion(newType.interfaces)
    }

    if let newType = newType as? ObjectType {
      newScope.formUnion(allTypes.unions(including: newType))
    }

    return newScope
  }

  /// Returns a new `ScopeDescriptor` appending the new `ScopeCondition` to the `scopePath`.
  /// Any new types are added to the `matchingTypes`, and any new conditions are added to the
  /// `matchingConditions`.
  ///
  /// This should be used to create a `ScopeDescriptor` for a conditional `SelectionSet` inside
  /// of an entity, by appending the conditions to the parent `SelectionSet`'s `ScopeDescriptor`.
  func appending(
    _ scopeCondition: ScopeCondition
  ) -> ScopeDescriptor {
    let matchingTypes: TypeScope
    if let newType = scopeCondition.type {
      matchingTypes = Self.typeScope(
        addingType: newType,
        to: self.matchingTypes,
        givenAllTypes: self.allTypesInSchema
      )
    } else {
      matchingTypes = self.matchingTypes
    }

    var matchingConditions = self.matchingConditions
    if let newConditions = scopeCondition.conditions {
      matchingConditions = matchingConditions?.appending(newConditions) ?? newConditions
    }

    return ScopeDescriptor(
      typePath: scopePath.appending(scopeCondition),
      type: scopeCondition.type ?? self.type,
      matchingTypes: matchingTypes,
      matchingConditions: matchingConditions,
      allTypesInSchema: self.allTypesInSchema
    )
  }

  /// Returns a new `ScopeDescriptor` appending the new type to the `scopePath` and
  /// `matchingConditions`.
  ///
  /// This should be used to create a `ScopeDescriptor` for a conditional `SelectionSet` inside
  /// of an entity, by appending the conditions to the parent `SelectionSet`'s `ScopeDescriptor`.
  func appending(_ newType: CompositeType) -> ScopeDescriptor {
    self.appending(.init(type: newType))
  }

  /// Returns a new `ScopeDescriptor` appending the new conditions to the `scopePath` and
  /// `matchingTypes`.
  ///
  /// This should be used to create a `ScopeDescriptor` for a conditional `SelectionSet` inside
  /// of an entity, by appending the conditions to the parent `SelectionSet`'s `ScopeDescriptor`.
  func appending(_ conditions: InclusionConditions) -> ScopeDescriptor {
    self.appending(.init(conditions: conditions))
  }

  /// Indicates if the receiver is all of the types in the given `TypeScope`.
  /// If the receiver matches a `TypeScope`, then selections for a `SelectionSet` of that
  /// type scope can be merged in to the receiver's `SelectionSet`.
  public func matches(_ otherScope: TypeScope) -> Bool {
    otherScope.isSubset(of: self.matchingTypes)
  }

  public func matches(_ otherType: CompositeType) -> Bool {
    self.matchingTypes.contains(otherType)
  }

  public func matches(_ otherConditions: InclusionConditions) -> Bool {
    otherConditions.isSubset(of: self.matchingConditions)
  }

  public func matches(_ otherConditions: AnyOf<InclusionConditions>) -> Bool {
    for conditionGroup in otherConditions.elements {
      if conditionGroup.isSubset(of: self.matchingConditions) { return true }
    }
    return false
  }

  public func matches(_ otherDeferCondition: CompilationResult.DeferCondition) -> Bool {
    otherDeferCondition == self.scopePath.last.value.deferCondition
  }

  /// Indicates if the receiver is of the given type. If the receiver matches a given type,
  /// then selections for a `SelectionSet` of that type can be merged in to the receiver's
  /// `SelectionSet`.
  public func matches(_ condition: ScopeCondition) -> Bool {
    if let type = condition.type, !self.matches(type) {
      return false
    }

    if let inclusionConditions = condition.conditions, !self.matches(inclusionConditions) {
      return false
    }

    if let deferConditions = condition.deferCondition, !self.matches(deferConditions) {
      return false
    }

    return true
  }

  public static func == (lhs: ScopeDescriptor, rhs: ScopeDescriptor) -> Bool {
    lhs.scopePath == rhs.scopePath &&
    lhs.matchingTypes == rhs.matchingTypes
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(scopePath)
    hasher.combine(matchingTypes)
  }

  public var debugDescription: String {
    scopePath.debugDescription
  }
}
