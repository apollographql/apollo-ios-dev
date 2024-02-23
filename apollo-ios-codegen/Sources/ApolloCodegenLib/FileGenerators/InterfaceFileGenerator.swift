import Foundation
import IR

/// Generates a file containing the Swift representation of a [GraphQL Interface](https://spec.graphql.org/draft/#sec-Interfaces).
struct InterfaceFileGenerator: FileGenerator {
  /// Source GraphQL interface.
  let irInterface: IR.InterfaceType
  /// Shared codegen configuration.
  let config: ApolloCodegen.ConfigurationContext

  var template: TemplateRenderer {
    InterfaceTemplate(irInterface: irInterface, config: config)
  }

  var target: FileTarget { .interface }
  var fileName: String { irInterface.render(as: .filename, config: config) }
}
