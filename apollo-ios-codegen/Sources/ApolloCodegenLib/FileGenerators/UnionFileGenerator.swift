import Foundation
import IR

/// Generates a file containing the Swift representation of a [GraphQL Union](https://spec.graphql.org/draft/#sec-Unions).
struct UnionFileGenerator: FileGenerator {
  /// Source GraphQL union.
  let irUnion: IR.UnionType
  /// Shared codegen configuration.
  let config: ApolloCodegen.ConfigurationContext

  var template: TemplateRenderer { UnionTemplate(
    irUnion: irUnion,
    config: config
  ) }
  var target: FileTarget { .union }
  var fileName: String { irUnion.render(as: .filename, config: config) }
}
