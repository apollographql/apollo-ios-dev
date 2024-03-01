import Foundation
import IR
import OrderedCollections

/// Generates a file providing the ability to mock the GraphQLUnionTypes in a schema
/// for testing purposes.
struct MockUnionsFileGenerator: FileGenerator {

  let irUnions: OrderedSet<IR.UnionType>

  let config: ApolloCodegen.ConfigurationContext

  init?(ir: IRBuilder, config: ApolloCodegen.ConfigurationContext) {
    let unions = ir.schema.referencedTypes.unions
    guard !unions.isEmpty else { return nil }
    self.irUnions = unions
    self.config = config
  }

  var template: TemplateRenderer {
    MockUnionsTemplate(
      irUnions: irUnions,
      config: config
    )
  }

  var target: FileTarget { .testMock }
  var fileName: String { "MockObject+Unions" }
}
