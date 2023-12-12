import Foundation
import TemplateString

/// Provides the format to define a namespace that is used to wrap other templates to prevent
/// naming collisions in Swift code.
struct SchemaModuleNamespaceTemplate: TemplateRenderer {

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .moduleFile

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString("""
    \(accessControlModifier(for: .namespace))\
    enum \(config.schemaNamespace.firstUppercased) { }

    """)
  }
}
