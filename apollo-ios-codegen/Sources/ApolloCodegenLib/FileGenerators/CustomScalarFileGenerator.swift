import Foundation
import IR

/// Generates a file containing the Swift representation of a [GraphQL Custom Scalar](https://spec.graphql.org/draft/#sec-Scalars.Custom-Scalars).
struct CustomScalarFileGenerator: FileGenerator {
  /// Source GraphQL Custom Scalar..
  let irScalar: IR.ScalarType
  /// Shared codegen configuration.
  let config: ApolloCodegen.ConfigurationContext

  var template: TemplateRenderer {
    CustomScalarTemplate(irScalar: irScalar, config: config)
  }

  var target: FileTarget { .customScalar }
  var fileName: String { irScalar.render(as: .filename, config: config) }
  var overwrite: Bool { false }
}
