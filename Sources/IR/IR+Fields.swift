import Foundation
import OrderedCollections
import GraphQLCompiler
import TemplateString

public class Field: Equatable, CustomDebugStringConvertible {
  public let underlyingField: CompilationResult.Field
  public internal(set) var inclusionConditions: AnyOf<InclusionConditions>?

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

  public static func ==(lhs: Field, rhs: Field) -> Bool {
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

public final class ScalarField: Field {
  override init(
    _ field: CompilationResult.Field,
    inclusionConditions: AnyOf<InclusionConditions>? = nil
  ) {
    super.init(field, inclusionConditions: inclusionConditions)
  }
}

public final class EntityField: Field {
  public let selectionSet: SelectionSet
  public var entity: Entity { selectionSet.typeInfo.entity }

  init(
    _ field: CompilationResult.Field,
    inclusionConditions: AnyOf<InclusionConditions>? = nil,
    selectionSet: SelectionSet
  ) {
    self.selectionSet = selectionSet
    super.init(field, inclusionConditions: inclusionConditions)
  }

  public static func ==(lhs: EntityField, rhs: EntityField) -> Bool {
    lhs.underlyingField == rhs.underlyingField &&
    lhs.inclusionConditions == rhs.inclusionConditions &&
    lhs.selectionSet == rhs.selectionSet
  }
}
