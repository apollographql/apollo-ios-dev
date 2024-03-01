import Foundation
import IR

/// Generates a file containing the Swift representation of a
/// [GraphQL Input Object](https://spec.graphql.org/draft/#sec-Input-Objects).
struct InputObjectFileGenerator: FileGenerator {
  /// Source GraphQL input object.
  let irInputObject: IR.InputObjectType
  /// Shared codegen configuration.
  let config: ApolloCodegen.ConfigurationContext

  var template: TemplateRenderer {
    InputObjectTemplate(irInputObject: irInputObject, config: config)
  }
  var target: FileTarget { .inputObject }
  var fileName: String { irInputObject.render(as: .filename, config: config) }
}
