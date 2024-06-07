import Foundation
import IR
import OrderedCollections
import GraphQLCompiler

/// Generates a file providing the ability to mock the GraphQLInterfaceTypes in a schema
/// for testing purposes.
struct MockInterfacesFileGenerator: FileGenerator {

  let graphqlInterfaces: OrderedSet<GraphQLInterfaceType>

  let config: ApolloCodegen.ConfigurationContext

  init?(ir: IRBuilder, config: ApolloCodegen.ConfigurationContext) {
    let interfaces = ir.schema.referencedTypes.interfaces
    guard !interfaces.isEmpty else { return nil }
    self.graphqlInterfaces = interfaces
    self.config = config
  }

  var template: any TemplateRenderer {
    MockInterfacesTemplate(
      graphqlInterfaces: graphqlInterfaces,
      config: config
    )
  }

  var target: FileTarget { .testMock }
  var fileName: String { "MockObject+Interfaces" }
}
