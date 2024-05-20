import Foundation
import IR
import OrderedCollections
import GraphQLCompiler

/// Generates a file providing the ability to mock the GraphQLUnionTypes in a schema
/// for testing purposes.
struct MockUnionsFileGenerator: FileGenerator {

  let graphqlUnions: OrderedSet<GraphQLUnionType>

  let config: ApolloCodegen.ConfigurationContext

  init?(ir: IRBuilder, config: ApolloCodegen.ConfigurationContext) {
    let unions = ir.schema.referencedTypes.unions
    guard !unions.isEmpty else { return nil }
    self.graphqlUnions = unions
    self.config = config
  }

  var template: TemplateRenderer {
    MockUnionsTemplate(
      graphqlUnions: graphqlUnions,
      config: config
    )
  }

  var target: FileTarget { .testMock }
  var fileName: String { "MockObject+Unions" }
}
