import IR
import GraphQLCompiler
import TemplateString
import OrderedCollections

/// Provides the format to convert a [GraphQL Operation](https://spec.graphql.org/draft/#sec-Language.Operations)
/// into Swift code.
struct OperationDefinitionTemplate: OperationTemplateRenderer {
  /// IR representation of source [GraphQL Operation](https://spec.graphql.org/draft/#sec-Language.Operations).
  let operation: IR.Operation

  /// The persisted query identifier for the ``operation``.
  let operationIdentifier: String?

  let config: ApolloCodegen.ConfigurationContext

  var target: TemplateTarget {
    .operationFile(moduleImports: operation.definition.moduleImports)
  }

  private var accessControl: (member: AccessControlRenderer, parent: AccessControlRenderer)!

  init(
    operation: IR.Operation,
    operationIdentifier: String?,
    config: ApolloCodegen.ConfigurationContext,
  ) {
    self.operation = operation
    self.operationIdentifier = operationIdentifier
    self.config = config
    self.accessControl = (
      member: accessControlRenderer(for: .member),
      parent: accessControlRenderer(for: .parent)
    )
  }

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    return TemplateString(
    """
    \(OperationDeclaration())
      \(DocumentType())

      \(section: VariableProperties(operation.definition.variables))

      \(Initializer(operation.definition.variables))

      \(section: VariableAccessors(operation.definition.variables))

      \(accessControl.member.render())struct Data: \(operation.renderedSelectionSetType(config)) {
        \(SelectionSetTemplate(
            definition: operation,
            generateInitializers: config.config.shouldGenerateSelectionSetInitializers(for: operation),
            config: config,
            nonFatalErrorRecorder: nonFatalErrorRecorder,
            accessControlRenderer: accessControl.member
        ).renderBody())
      }
    
      \(section: DeferredFragmentsMetadataTemplate(
        operation: operation,
        config: config,
        renderAccessControl: { accessControl.parent.render() }()
      ).render())
    }

    """)
  }
    
  private func OperationDeclaration() -> TemplateString {
    return """
    \(accessControl.parent.render())\
    struct \(operation.generatedDefinitionName): \
    \(operation.definition.operationType.renderedProtocolName) {
      \(accessControl.member.render())\
    static let operationName: String = "\(operation.definition.name)"
    """
  }

  func DocumentType() -> TemplateString {
    let includeFragments = !operation.referencedFragments.isEmpty
    let includeDefinition = config.options.operationDocumentFormat.contains(.definition)

    return TemplateString("""
      \(accessControl.member.render())\
      static let operationDocument: \(TemplateConstants.ApolloAPITargetName).OperationDocument = .init(
      \(if: config.options.operationDocumentFormat.contains(.operationId), {
        precondition(operationIdentifier != nil, "operationIdentifier is missing.")
        return """
          operationIdentifier: \"\(operationIdentifier.unsafelyUnwrapped)\"\(if: includeDefinition, ",")
        """ }()
      )
      \(if: includeDefinition, """
        definition: .init(
          \(operation.definition.source.formattedSource())\(if: includeFragments, ",")
          \(if: includeFragments, """
            fragments: [\(operation.referencedFragments.map {
              "\($0.name.asFragmentName).self"
            }, separator: ", ")]
            """
          )
        ))
      """,
      else: """
      )
      """)
      """
    )
  }
}

fileprivate extension CompilationResult.OperationType {
  var renderedProtocolName: String {
    switch self {
    case .query: return "GraphQLQuery"
    case .mutation: return "GraphQLMutation"
    case .subscription: return "GraphQLSubscription"
    }
  }
}

fileprivate extension String {
  func formattedSource() -> Self {
    return "#\"\(convertedToSingleLine())\"#"
  }
}
