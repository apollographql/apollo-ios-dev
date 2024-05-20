import Foundation
import IR
import GraphQLCompiler

/// Generates a file providing the ability to mock a GraphQLObject for testing purposes.
struct MockObjectFileGenerator: FileGenerator {
  /// Source GraphQL object.
  let graphqlObject: GraphQLObjectType

  let fields: [(String, GraphQLType, deprecationReason: String?)]

  let ir: IRBuilder

  let config: ApolloCodegen.ConfigurationContext

  var template: TemplateRenderer {
    MockObjectTemplate(
      graphqlObject: graphqlObject,
      fields: fields,
      config: config,
      ir: ir
    )
  }

  var target: FileTarget { .testMock }
  var fileName: String { "\(graphqlObject.render(as: .filename))+Mock" }
}
