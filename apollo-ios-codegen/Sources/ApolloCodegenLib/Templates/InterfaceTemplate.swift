import Foundation
import IR
import TemplateString

/// Provides the format to convert a [GraphQL Interface](https://spec.graphql.org/draft/#sec-Interfaces)
/// into Swift code.
struct InterfaceTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Interface](https://spec.graphql.org/draft/#sec-Interfaces).
  let irInterface: IR.InterfaceType

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .interface)

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    """
    \(documentation: irInterface.documentation, config: config)
    static let \(irInterface.render(as: .typename, config: config)) = Interface(name: "\(irInterface.name.schemaName)")
    """
  }
}
