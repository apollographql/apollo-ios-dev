import Foundation
import IR

/// Generates a file containing the Swift representation of a [GraphQL Enum](https://spec.graphql.org/draft/#sec-Enums).
struct EnumFileGenerator: FileGenerator {
  /// Source GraphQL enum.
  let irEnum: IR.EnumType
  /// Shared codegen configuration.
  let config: ApolloCodegen.ConfigurationContext

  var template: TemplateRenderer {
    EnumTemplate(irEnum: irEnum, config: config)
  }

  var target: FileTarget { .enum }
  var fileName: String { irEnum.render(as: .filename, config: config) }
}
