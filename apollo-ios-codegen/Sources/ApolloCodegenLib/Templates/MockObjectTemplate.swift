import Foundation
import IR
import GraphQLCompiler
import TemplateString

struct MockObjectTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Object](https://spec.graphql.org/draft/#sec-Objects).
  let graphqlObject: GraphQLObjectType

  let fields: [(String, TestMockFieldType, deprecationReason: String?)]

  let config: ApolloCodegen.ConfigurationContext

  let ir: IRBuilder

  let target: TemplateTarget = .testMockFile

  struct TemplateField {
    let responseKey: String
    let propertyName: String
    let initializerParameterName: String?
    let type: TestMockFieldType
    let mockType: String
    let deprecationReason: String?
    let config: ApolloCodegen.ConfigurationContext

    /// Whether the type joins schema types that differ by more than nullability. These fields are
    /// always optional, with a `nil` default.
    var isJoined: Bool { type.graphQLType == nil }

    var initializerType: String {
      if isJoined {
        return "\(mockType)?"
      } else if config.options.requireNonOptionalMockFields || type.isNullable {
        return mockType
      } else {
        return "\(mockType)?"
      }
    }

    func defaultInitializer(
      config: ApolloCodegen.ConfigurationContext,
      referencedTypes: IR.Schema.ReferencedTypes
    ) -> String? {
      if isJoined || !config.options.requireNonOptionalMockFields || type.isNullable {
        return " = nil"
      }

      guard let defaultValue = type.graphQLType?.defaultMockValue(
        config: config,
        referencedTypes: referencedTypes
      ) else { return nil }

      return " = \(defaultValue)"
    }
  }

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    let objectName = graphqlObject.render(as: .typename())
    let fields: [TemplateField] = fields
      .sorted { $0.0 < $1.0 }
      .map {
         TemplateField(
          responseKey: $0.0,
          propertyName: $0.0.renderAsTestMockFieldPropertyName(config: config),
          initializerParameterName: $0.0.asTestMockInitializerParameterName,
          type: $0.1,
          mockType: mockTypeName(for: $0.1),
          deprecationReason: $0.deprecationReason,
          config: config
         )
      }

    let memberAccessControl = accessControlRenderer(for: .member).render()
    let parentAccessControl = accessControlRenderer(for: .parent).render()

    return """
    \(config.nonisolatedModifier)\(parentAccessControl)final class \(objectName): MockObject {
      \(memberAccessControl)static let objectType: \(TemplateConstants.ApolloAPITargetName).Object = \(config.schemaNamespace.firstUppercased).Objects.\(objectName)
      \(memberAccessControl)static let _mockFields = MockFields()
      \(memberAccessControl)typealias MockValueCollectionType = Array<Mock<\(objectName)>>

      \(memberAccessControl)struct MockFields: Sendable {
        \(fields.map {
          TemplateString("""
          \(deprecationReason: $0.deprecationReason, config: config)
          @Field<\(fieldTypeName(for: $0.type))>("\($0.responseKey)") public var \($0.propertyName)
          """)
        }, separator: "\n")
      }
    }
    \(!fields.isEmpty ?
      TemplateString("""
      
      \(parentAccessControl)\
      extension Mock where O == \(objectName) {
        \(conflictingFieldNameProperties(fields))
        convenience init(
          \(fields.map { """
            \($0.propertyName)\(ifLet: $0.initializerParameterName, {" \($0)"}): \($0.initializerType)\(ifLet: $0.defaultInitializer(config: config, referencedTypes: ir.schema.referencedTypes), { "\($0)" })
            """ }, separator: ",\n")
        ) {
          self.init()
          \(fields.map {
            return "_set\(mockFunctionDescriptor($0.type))(\($0.initializerParameterName ?? $0.propertyName), for: \\.\($0.propertyName))"
          }, separator: "\n")
        }
      }
      """) : TemplateString(stringLiteral: "")
    )
    
    """
  }
  
  private func mockFunctionDescriptor(_ type: TestMockFieldType) -> String {
    if type.containsAnyValue {
      return "AnyValue"
    }

    switch type {
    case .list(let ofType):
      switch ofType {
      case .nonNull(.list(_)),
           .list(_):
        return mockFunctionDescriptor(ofType)
      case .nonNull(.named(.entity(_))),
           .named(.entity(_)),
           .nonNull(.anyEntity),
           .anyEntity:
        return "List"
      default:
        break
      }
      return "ScalarList"
    case .named(.scalar(_)), .named(.enum(_)):
      return "Scalar"
    case .named(.entity(_)), .anyEntity:
      return "Entity"
    case .named(.inputObject(_)):
      preconditionFailure("Input object found when determing mock set function descriptor.")
    case .named(.nonNull(_)), .named(.list(_)):
      preconditionFailure("Wrapped type found as a named test mock field type.")
    case .anyValue:
      return "AnyValue"
    case .nonNull(let ofType):
      return mockFunctionDescriptor(ofType)
    }
  }

  private func conflictingFieldNameProperties(_ fields: [TemplateField]) -> TemplateString {
    """
    \(fields.map { """
      \(if: $0.propertyName.isConflictingTestMockFieldName, """
        var \($0.propertyName): \($0.type.containsAnyValue ? "Swift.AnyHashable" : $0.mockType)? {
          get { _data["\($0.propertyName)"]\(if: !$0.type.containsAnyValue, " as? \($0.mockType)") }
          set { _set\(mockFunctionDescriptor($0.type))(newValue, for: \\.\($0.propertyName)) }
        }
        """)
      """ }, separator: "\n", terminator: "\n")
    """
  }

  private func fieldTypeName(for type: TestMockFieldType) -> String {
    if let graphQLType = type.graphQLType {
      return graphQLType.rendered(as: .testMockField(forceNonNull: true), config: config.config)
    }

    func render(_ type: TestMockFieldType, containedInNonNull: Bool) -> String {
      let typeName: String
      switch type {
      case let .nonNull(ofType):
        return render(ofType, containedInNonNull: true)
      case let .list(ofType):
        typeName = "[\(render(ofType, containedInNonNull: false))]"
      case .anyEntity:
        typeName = "\(TemplateConstants.ApolloAPITargetName).Interface"
      case .anyValue:
        typeName = "ApolloTestSupport.AnyFieldValue"
      case let .named(graphQLType):
        return graphQLType.rendered(
          as: .testMockField(forceNonNull: containedInNonNull),
          config: config.config
        )
      }
      return containedInNonNull ? typeName : "\(typeName)?"
    }

    return render(type, containedInNonNull: true)
  }

  /// The mock type for the field. For joined types, this is non-optional at the top level.
  private func mockTypeName(for type: TestMockFieldType) -> String {
    if let graphQLType = type.graphQLType {
      return mockTypeName(for: graphQLType)
    }

    func nameReplacement(for type: TestMockFieldType, forceNonNull: Bool) -> String {
      switch type {
      case let .nonNull(ofType):
        return nameReplacement(for: ofType, forceNonNull: true)
      case let .list(ofType):
        return TemplateString(
          "[\(nameReplacement(for: ofType, forceNonNull: false))]\(if: !forceNonNull, "?")"
        ).description
      case .anyEntity:
        return TemplateString("(any AnyMock)\(if: !forceNonNull, "?")").description
      case .anyValue:
        return TemplateString("Swift.AnyHashable\(if: !forceNonNull, "?")").description
      case let .named(graphQLType):
        return mockTypeName(for: forceNonNull ? .nonNull(graphQLType) : graphQLType)
      }
    }

    return nameReplacement(for: type, forceNonNull: true)
  }

  private func mockTypeName(for type: GraphQLType) -> String {
    func nameReplacement(for type: GraphQLType, forceNonNull: Bool) -> String {
      switch type {
      case .entity(let graphQLCompositeType):
        let mockType: String
        switch graphQLCompositeType {
        case is GraphQLInterfaceType, is GraphQLUnionType:
          mockType = "(any AnyMock)"
        default:
          mockType = "Mock<\(graphQLCompositeType.render(as: .typename()))>"
        }
        return TemplateString("\(mockType)\(if: !forceNonNull, "?")").description
      case .scalar,
          .enum,
          .inputObject:
        return TemplateString(
          "\(type.rendered(as: .testMockField(forceNonNull: true),config: config.config))\(if: !forceNonNull, "?")"
        ).description
      case .nonNull(let graphQLType):
        return nameReplacement(for: graphQLType, forceNonNull: true)
      case .list(let graphQLType):
        return TemplateString(
          "[\(nameReplacement(for: graphQLType, forceNonNull: false))]\(if: !forceNonNull, "?")"
        ).description
      }
    }

    return nameReplacement(for: type, forceNonNull: false)
  }
}

fileprivate extension TestMockFieldType {
  var containsAnyValue: Bool {
    switch self {
    case .anyValue:
      return true
    case let .nonNull(ofType), let .list(ofType):
      return ofType.containsAnyValue
    case .named, .anyEntity:
      return false
    }
  }
}
