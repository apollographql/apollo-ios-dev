import Foundation
import TemplateString

/// Renders the Cache Key Resolution extension for a generated schema.
struct SchemaConfigurationTemplate: TemplateRenderer {
  /// Shared codegen configuration
  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .schemaConfiguration)

  func renderHeaderTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString? {
    HeaderCommentTemplate.editableFileHeader(
      fileCanBeEditedTo: """
      provide custom configuration for a generated GraphQL schema.
      """
    )
  }

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    return """
    \(accessControlModifier(for: .parent))enum SchemaConfiguration: \
    \(TemplateConstants.ApolloAPITargetName).SchemaConfiguration {
      \(accessControlModifier(for: .member))\
    static func cacheKeyInfo(for type: \(TemplateConstants.ApolloAPITargetName).Object, object: \(TemplateConstants.ApolloAPITargetName).ObjectData) -> CacheKeyInfo? {
        // Implement this function to configure cache key resolution for your schema types.
        return nil
      }
    }

    """
  }
}
