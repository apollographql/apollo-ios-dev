import Foundation
import IR
import OrderedCollections

/// Generates a file providing the ability to mock the GraphQLInterfaceTypes in a schema
/// for testing purposes.
struct MockInterfacesFileGenerator: FileGenerator {

  let irInterfaces: OrderedSet<IR.InterfaceType>

  let config: ApolloCodegen.ConfigurationContext

  init?(ir: IRBuilder, config: ApolloCodegen.ConfigurationContext) {
    let interfaces = ir.schema.referencedTypes.interfaces
    guard !interfaces.isEmpty else { return nil }
    self.irInterfaces = interfaces
    self.config = config
  }

  var template: TemplateRenderer {
    MockInterfacesTemplate(
      irInterfaces: irInterfaces,
      config: config
    )
  }

  var target: FileTarget { .testMock }
  var fileName: String { "MockObject+Interfaces" }
}
