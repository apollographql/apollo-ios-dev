import Foundation
import OrderedCollections
import GraphQLCompiler
import TemplateString

public enum Field: Equatable, Sendable {
  case scalar(ScalarField)
  case entity(EntityField)
}

public struct FieldInfo: Equatable, Sendable, CustomDebugStringConvertible {
  public let underlyingField: CompilationResult.Field
  public let inclusionConditions: AnyOf<InclusionConditions>?

  public var name: String { underlyingField.name }
  public var alias: String? { underlyingField.alias }
  public var responseKey: String { underlyingField.responseKey }
  public var type: GraphQLType { underlyingField.type }
  public var arguments: [CompilationResult.Argument]? { underlyingField.arguments }

  fileprivate init(
    _ field: CompilationResult.Field,
    inclusionConditions: AnyOf<InclusionConditions>? = nil
  ) {
    self.underlyingField = field
    self.inclusionConditions = inclusionConditions
  }

  public static func ==(lhs: FieldInfo, rhs: FieldInfo) -> Bool {
    lhs.underlyingField == rhs.underlyingField &&
    lhs.inclusionConditions == rhs.inclusionConditions
  }

  public var debugDescription: String {
    TemplateString("""
      \(name): \(type.debugDescription)\(ifLet: inclusionConditions, {
      " \($0.debugDescription)"
        })
      """).description
  }
}

@dynamicMemberLookup
public struct ScalarField: Sendable, Equatable {

  let fieldInfo: FieldInfo

  init(
    _ field: CompilationResult.Field,
    inclusionConditions: AnyOf<InclusionConditions>? = nil
  ) {
    fieldInfo = .init(field, inclusionConditions: inclusionConditions)
  }

  public subscript<T>(dynamicMember keyPath: KeyPath<FieldInfo, T>) -> T {
    fieldInfo[keyPath: keyPath]
  }
}

@dynamicMemberLookup
public struct EntityField: Sendable {

  public let selectionSet: SelectionSet
  public var entity: Entity { selectionSet.typeInfo.entity }
  let fieldInfo: FieldInfo

  init(
    _ field: CompilationResult.Field,
    inclusionConditions: AnyOf<InclusionConditions>? = nil,
    selectionSet: SelectionSet
  ) {
    self.selectionSet = selectionSet
    fieldInfo = .init(field, inclusionConditions: inclusionConditions)
  }

  public subscript<T>(dynamicMember keyPath: KeyPath<FieldInfo, T>) -> T {
    fieldInfo[keyPath: keyPath]
  }

  public static func ==(lhs: EntityField, rhs: EntityField) -> Bool {
    lhs.fieldInfo == rhs.fieldInfo &&
    lhs.selectionSet == rhs.selectionSet
  }
}
