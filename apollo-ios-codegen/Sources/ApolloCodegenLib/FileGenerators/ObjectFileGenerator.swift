import Foundation
import IR
import TemplateString

/// Generates a file containing the Swift representation of a [GraphQL Object](https://spec.graphql.org/draft/#sec-Objects).
struct ObjectFileGenerator: FileGenerator {
  /// Source GraphQL object.
  let irObject: IR.ObjectType
  /// Shared codegen configuration.
  let config: ApolloCodegen.ConfigurationContext
  
  var template: TemplateRenderer {
    ObjectTemplate(irObject: irObject, config: config)
  }

  var target: FileTarget { .object }
  var fileName: String { irObject.render(as: .filename, config: config) }
}
