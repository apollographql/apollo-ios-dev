import Foundation
import TemplateString

/// Provides the format to output an operation manifest file used for persisted queries.
struct PersistedQueriesOperationManifestTemplate: OperationManifestTemplate {

  let config: ApolloCodegen.ConfigurationContext
  let encoder = JSONEncoder()

  func render(operations: [OperationManifestItem]) -> String {
    template(operations).description
  }

  private func template(_ operations: [OperationManifestItem]) -> TemplateString {
    return TemplateString(
      """
      {
        "format": "apollo-persisted-query-manifest",
        "version": 1,
        "operations": [
          \(forEachIn: operations, {
            return """
            {
              "id": "\($0.identifier)",
              "body": "\($0.operation.sourceText(withFormat: .manifestJSONBody))",
              "name": "\($0.operation.name)",
              "type": "\($0.operation.type.rawValue)"
            }
            """
          })
        ]
      }
      """
    )
  }

}
