import Foundation
import IR

/// Generates a file containing the Swift representation of a [GraphQL Operation](https://spec.graphql.org/draft/#sec-Language.Operations).
struct OperationFileGenerator: FileGenerator {
  /// Source IR operation.
  let irOperation: IR.Operation
  /// The persisted query identifier for the ``operation``.
  let operationIdentifier: String?
  /// Shared codegen configuration
  let config: ApolloCodegen.ConfigurationContext
  
  var template: TemplateRenderer {
    irOperation.definition.isLocalCacheMutation ?
    LocalCacheMutationDefinitionTemplate(
      operation: irOperation,
      config: config
    ) :
    OperationDefinitionTemplate(
      operation: irOperation,
      operationIdentifier: operationIdentifier,
      config: config
    )
  }

  var target: FileTarget { .operation(irOperation.definition) }
  var fileName: String { irOperation.definition.generatedDefinitionName }
}
