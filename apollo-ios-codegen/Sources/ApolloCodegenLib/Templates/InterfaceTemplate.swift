import Foundation
import GraphQLCompiler
import TemplateString

/// Provides the format to convert a [GraphQL Interface](https://spec.graphql.org/draft/#sec-Interfaces)
/// into Swift code.
struct InterfaceTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Interface](https://spec.graphql.org/draft/#sec-Interfaces).
  let graphqlInterface: GraphQLInterfaceType

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .interface)

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    """
    \(documentation: graphqlInterface.documentation, config: config)
    \(if: graphqlInterface.name.shouldRenderDocumentation, """
      \(graphqlInterface.name.typeNameDocumentation)
      """
    )
    static let \(graphqlInterface.render(as: .typename)) = \(config.ApolloAPITargetName).Interface(name: "\(graphqlInterface.name.schemaName)")
    """
  }
}
