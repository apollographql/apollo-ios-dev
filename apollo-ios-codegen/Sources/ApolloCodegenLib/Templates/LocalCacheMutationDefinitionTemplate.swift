import IR
import OrderedCollections
import TemplateString

struct LocalCacheMutationDefinitionTemplate: OperationTemplateRenderer {
  /// IR representation of source [GraphQL Operation](https://spec.graphql.org/draft/#sec-Language.Operations).
  let operation: IR.Operation

  let config: ApolloCodegen.ConfigurationContext

  var target: TemplateTarget {
    .operationFile(moduleImports: operation.definition.moduleImports)
  }

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    let memberAccessControl = accessControlModifier(for: .member)

    return TemplateString(
    """
    \(accessControlModifier(for: .parent))\
    struct \(operation.generatedDefinitionName): LocalCacheMutation {
      \(memberAccessControl)static let operationType: GraphQLOperationType = .\(operation.definition.operationType.rawValue)

      \(section: VariableProperties(operation.definition.variables))

      \(Initializer(operation.definition.variables))

      \(section: VariableAccessors(operation.definition.variables, graphQLOperation: false))

      \(memberAccessControl)struct Data: \(operation.renderedSelectionSetType(config)) {
        \(SelectionSetTemplate(
            definition: operation,
            generateInitializers: config.config.shouldGenerateSelectionSetInitializers(for: operation),
            config: config,
            nonFatalErrorRecorder: nonFatalErrorRecorder,
            renderAccessControl: { accessControlModifier(for: .member) }()
        ).renderBody())
      }
    }
    
    """)
  }

}
