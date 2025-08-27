import Foundation
import OrderedCollections
import TemplateString

/// Generates a file containing schema metadata used by the GraphQL executor at runtime.
struct SchemaConfigurationFileGenerator: FileGenerator {
  /// Shared codegen configuration
  let config: ApolloCodegen.ConfigurationContext

  var template: any TemplateRenderer { SchemaConfigurationTemplate(config: config) }
  var overwrite: Bool { false }
  var target: FileTarget { .schema }
  var fileName: String { "SchemaConfiguration" }
  
}
