import Foundation
import IR

/// Generates a file providing the ability to mock a GraphQLObject for testing purposes.
struct MockObjectFileGenerator: FileGenerator {
  /// Source GraphQL object.
  let irObject: IR.ObjectType

  let fields: [(String, GraphQLType, deprecationReason: String?)]

  let ir: IRBuilder

  let config: ApolloCodegen.ConfigurationContext

  var template: TemplateRenderer {
    MockObjectTemplate(
      irObject: irObject,
      fields: fields,
      config: config,
      ir: ir
    )
  }

  var target: FileTarget { .testMock }
  var fileName: String { "\(irObject.render(as: .filename, config: config))+Mock" }
}
