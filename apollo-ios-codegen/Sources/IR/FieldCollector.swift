import GraphQLCompiler

public actor FieldCollector {

  typealias CollectedField = (String, GraphQLType, deprecationReason: String?)

  private typealias FieldInfo = (GraphQLType, deprecationReason: String?)

  /// Collected fields keyed by response key, then by the name of the schema field that was
  /// selected with that response key.
  private var collectedFields: [GraphQLCompositeType: [String: [String: FieldInfo]]] = [:]

  func collectFields(from selectionSet: CompilationResult.SelectionSet) {
    guard let type = selectionSet.parentType as? (any GraphQLInterfaceImplementingType) else { return }
    for case let .field(field) in selectionSet.selections {
      add(field: field, to: type)
    }
  }

  func add<T: Sequence>(
    fields: T,
    to type: any GraphQLInterfaceImplementingType
  ) where T.Element == CompilationResult.Field {
    for field in fields {
      add(field: field, to: type)
    }
  }

  func add(
    field: CompilationResult.Field,
    to type: any GraphQLInterfaceImplementingType
  ) {
    collectedFields[type, default: [:]][field.responseKey, default: [:]][field.name] =
      (field.type, deprecationReason: field.deprecationReason)
  }

  public func collectedFields(
    for type: any GraphQLInterfaceImplementingType
  ) -> [(String, GraphQLType, deprecationReason: String?)] {
    var fields: [String: [String: FieldInfo]] = [:]

    for interface in type.interfaces {
      if let interfaceFields = collectedFields[interface] {
        fields.merge(interfaceFields) { existing, inherited in
          existing.merging(inherited) { Self.isOrdered($0, before: $1) ? $0 : $1 }
        }
      }
    }

    if let ownFields = collectedFields[type] {
      fields.merge(ownFields) { inherited, own in
        inherited.merging(own) { _, ownField in ownField }
      }
    }

    return fields.sorted { $0.key < $1.key }.compactMap { key, candidates in
      candidates.values
        .min { Self.isOrdered($0, before: $1) }
        .map { (key, $0.0, deprecationReason: $0.deprecationReason) }
    }
  }

  private static func isOrdered(_ lhs: FieldInfo, before rhs: FieldInfo) -> Bool {
    guard lhs.0 == rhs.0 else { return isOrdered(lhs.0, before: rhs.0) }

    switch (lhs.deprecationReason, rhs.deprecationReason) {
    case let (lhsReason?, rhsReason?):
      return lhsReason.utf8.lexicographicallyPrecedes(rhsReason.utf8)

    case (nil, .some):
      return true

    default:
      return false
    }
  }

  /// Orders nullable types before non-null types, outermost wrapper first, then named types
  /// before lists, then named types by schema name.
  private static func isOrdered(_ lhs: GraphQLType, before rhs: GraphQLType) -> Bool {
    switch (lhs, rhs) {
    case let (.nonNull(lhsType), .nonNull(rhsType)),
         let (.list(lhsType), .list(rhsType)):
      return isOrdered(lhsType, before: rhsType)

    case (_, .nonNull):
      return true

    case (.nonNull, _):
      return false

    case (_, .list):
      return true

    case (.list, _):
      return false

    default:
      return lhs.namedType.name.schemaName < rhs.namedType.name.schemaName
    }
  }
}
