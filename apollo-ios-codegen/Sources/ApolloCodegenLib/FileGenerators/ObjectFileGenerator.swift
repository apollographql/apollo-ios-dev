import Foundation
import GraphQLCompiler
import TemplateString

/// Generates a file containing the Swift representation of a [GraphQL Object](https://spec.graphql.org/draft/#sec-Objects).
struct ObjectFileGenerator: FileGenerator {
  /// Source GraphQL object.
  let graphqlObject: GraphQLObjectType
  /// Shared codegen configuration.
  let config: ApolloCodegen.ConfigurationContext
  
  var template: any TemplateRenderer {
    ObjectTemplate(graphqlObject: graphqlObject, config: config)
  }

  var target: FileTarget { .object }
  var fileName: String { graphqlObject.render(as: .filename) }
  var fileSuffix: String? { ".object" }
}
