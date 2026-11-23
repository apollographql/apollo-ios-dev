import GraphQLCompiler

public actor FieldCollector {

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

  /// The test mock fields for `type`, sorted by response key.
  ///
  /// Each response key selected on `type` or on any of its interfaces gets one field. Its type is
  /// joined from the types of every schema field selected with that response key, using `type`'s
  /// own definition of each field when the definition's composite type is in `referencedTypes`.
  /// Otherwise, it uses the selected field's named type with the definition's nullability. The
  /// field is deprecated only if every selected field is deprecated, in which case it uses the
  /// deprecation reason of the first selected field by name.
  public func collectedFields(
    for type: any GraphQLInterfaceImplementingType,
    referencedTypes: Schema.ReferencedTypes
  ) -> [(String, TestMockFieldType, deprecationReason: String?)] {
    var selectionsByResponseKey: [String: [(name: String, field: FieldInfo)]] = [:]
    for selectedType in [type as GraphQLCompositeType] + type.interfaces {
      for (responseKey, candidates) in collectedFields[selectedType] ?? [:] {
        selectionsByResponseKey[responseKey, default: []]
          .append(contentsOf: candidates.map { (name: $0.key, field: $0.value) })
      }
    }

    let fieldDefinitions = Self.fieldDefinitions(of: type)

    return selectionsByResponseKey.sorted { $0.key < $1.key }.compactMap { responseKey, selections in
      let selections = selections.sorted(by: Self.isOrdered)
      let types = selections.map {
        Self.mockFieldType(
          selected: $0.field.0,
          definition: fieldDefinitions[$0.name]?.type,
          referencedTypes: referencedTypes
        )
      }
      guard let first = types.first else { return nil }

      let type = types.dropFirst().reduce(first) { $0.joined(with: $1) }
      let isDeprecated = selections.allSatisfy { $0.field.deprecationReason != nil }

      return (
        responseKey,
        type,
        deprecationReason: isDeprecated ? selections.first?.field.deprecationReason : nil
      )
    }
  }

  private static func mockFieldType(
    selected: GraphQLType,
    definition: GraphQLType?,
    referencedTypes: Schema.ReferencedTypes
  ) -> TestMockFieldType {
    guard let definition else { return TestMockFieldType(selected) }

    if case let .entity(namedType) = definition.innerType,
       !referencedTypes.allTypes.contains(namedType) {
      return TestMockFieldType(definition.replacingInnerType(with: selected.innerType))
    }
    return TestMockFieldType(definition)
  }

  private static func isOrdered(
    _ lhs: (name: String, field: FieldInfo),
    before rhs: (name: String, field: FieldInfo)
  ) -> Bool {
    if lhs.name != rhs.name { return lhs.name < rhs.name }

    switch (lhs.field.deprecationReason, rhs.field.deprecationReason) {
    case let (lhsReason?, rhsReason?):
      return lhsReason.utf8.lexicographicallyPrecedes(rhsReason.utf8)
    case (nil, .some):
      return true
    default:
      return false
    }
  }

  private static func fieldDefinitions(
    of type: any GraphQLInterfaceImplementingType
  ) -> [String: GraphQLField] {
    switch type {
    case let object as GraphQLObjectType:
      return object.fields ?? [:]
    case let interface as GraphQLInterfaceType:
      return interface.fields ?? [:]
    default:
      return [:]
    }
  }
}

fileprivate extension GraphQLType {
  func replacingInnerType(with innerType: GraphQLType) -> GraphQLType {
    switch self {
    case let .nonNull(ofType):
      return .nonNull(ofType.replacingInnerType(with: innerType))
    case let .list(ofType):
      return .list(ofType.replacingInnerType(with: innerType))
    case .entity, .scalar, .enum, .inputObject:
      return innerType
    }
  }
}
