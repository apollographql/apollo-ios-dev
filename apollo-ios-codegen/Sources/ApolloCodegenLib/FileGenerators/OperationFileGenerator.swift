import Foundation
import IR

/// Generates a file containing the Swift representation of a [GraphQL Operation](https://spec.graphql.org/draft/#sec-Language.Operations).
struct OperationFileGenerator: FileGenerator {
  /// Source IR operation.
  let irOperation: IR.Operation
  /// The persisted query identifier for the ``operation``.
  let operationIdentifier: String?
  /// The pattern matched options for this particular operation source file.
  let patternMatchedOutputOptions: ApolloCodegenConfiguration.OutputOptions.PatternMatchedOutputOptions?
  /// Shared codegen configuration
  let config: ApolloCodegen.ConfigurationContext
  
  var template: TemplateRenderer {
    irOperation.definition.isLocalCacheMutation ?
    LocalCacheMutationDefinitionTemplate(
      operation: irOperation,
      patternMatchedOutputOptions: patternMatchedOutputOptions,
      config: config
    ) :
    OperationDefinitionTemplate(
      operation: irOperation,
      operationIdentifier: operationIdentifier,
      patternMatchedOutputOptions: patternMatchedOutputOptions,
      config: config
    )
  }

  var target: FileTarget { .operation(irOperation.definition) }
  var fileName: String { irOperation.definition.generatedDefinitionName }
}
