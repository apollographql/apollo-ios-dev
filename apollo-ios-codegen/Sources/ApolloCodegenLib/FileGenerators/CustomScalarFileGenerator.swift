import Foundation
import GraphQLCompiler

/// Generates a file containing the Swift representation of a [GraphQL Custom Scalar](https://spec.graphql.org/draft/#sec-Scalars.Custom-Scalars).
struct CustomScalarFileGenerator: FileGenerator {
  /// Source GraphQL Custom Scalar..
  let graphqlScalar: GraphQLScalarType
  /// Shared codegen configuration.
  let config: ApolloCodegen.ConfigurationContext

  var template: any TemplateRenderer {
    CustomScalarTemplate(graphqlScalar: graphqlScalar, config: config)
  }

  var target: FileTarget { .customScalar }
  var fileName: String { graphqlScalar.render(as: .filename) }
  var overwrite: Bool { false }
}
