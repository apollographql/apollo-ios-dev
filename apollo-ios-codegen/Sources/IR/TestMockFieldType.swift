import GraphQLCompiler

/// The type of a test mock field, joined from the types of every schema field selected with the
/// field's response key.
public indirect enum TestMockFieldType: Sendable, Hashable {
  /// A named schema type, without list or non-null wrappers.
  case named(GraphQLType)
  /// Any object, interface, or union type.
  case anyEntity
  /// Any field value.
  case anyValue
  case nonNull(TestMockFieldType)
  case list(TestMockFieldType)

  public init(_ type: GraphQLType) {
    switch type {
    case let .nonNull(ofType):
      self = .nonNull(TestMockFieldType(ofType))
    case let .list(ofType):
      self = .list(TestMockFieldType(ofType))
    case .entity, .scalar, .enum, .inputObject:
      self = .named(type)
    }
  }

  /// The equivalent schema type, or `nil` if the type includes `anyEntity` or `anyValue`.
  public var graphQLType: GraphQLType? {
    switch self {
    case let .named(type):
      return type
    case .anyEntity, .anyValue:
      return nil
    case let .nonNull(ofType):
      return ofType.graphQLType.map { .nonNull($0) }
    case let .list(ofType):
      return ofType.graphQLType.map { .list($0) }
    }
  }

  public var isNullable: Bool {
    if case .nonNull = self { return false }
    return true
  }

  /// A type that accepts every value valid for either type.
  ///
  /// The result is nullable wherever either type is nullable. Lists are joined element by element.
  /// Different composite types join to `anyEntity`. All other differences, including list depth,
  /// join to `anyValue`, except that `ID` and `String` join to `String`.
  public func joined(with other: TestMockFieldType) -> TestMockFieldType {
    switch (self, other) {
    case let (.nonNull(lhs), .nonNull(rhs)):
      return .nonNull(lhs.joined(with: rhs))

    case let (.nonNull(lhs), rhs), let (lhs, .nonNull(rhs)):
      return lhs.joined(with: rhs)

    case let (.list(lhs), .list(rhs)):
      return .list(lhs.joined(with: rhs))

    case (.anyValue, _), (_, .anyValue), (.list, _), (_, .list):
      return .anyValue

    case (.anyEntity, .anyEntity):
      return .anyEntity

    case let (.anyEntity, .named(type)), let (.named(type), .anyEntity):
      return type.isEntity ? .anyEntity : .anyValue

    case let (.named(lhs), .named(rhs)):
      return Self.join(lhs, rhs)
    }
  }

  private static func join(_ lhs: GraphQLType, _ rhs: GraphQLType) -> TestMockFieldType {
    switch (lhs, rhs) {
    case _ where lhs == rhs:
      return .named(lhs)

    case (.entity, .entity):
      return .anyEntity

    case let (.scalar(lhsScalar), .scalar(rhsScalar))
      where lhsScalar.isIDOrString && rhsScalar.isIDOrString:
      return .named(lhsScalar.name.schemaName == "String" ? lhs : rhs)

    default:
      return .anyValue
    }
  }
}

fileprivate extension GraphQLType {
  var isEntity: Bool {
    if case .entity = self { return true }
    return false
  }
}

fileprivate extension GraphQLScalarType {
  var isIDOrString: Bool {
    specifiedByURL == nil && (name.schemaName == "ID" || name.schemaName == "String")
  }
}
