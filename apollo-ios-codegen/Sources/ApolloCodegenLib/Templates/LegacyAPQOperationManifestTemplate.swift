import Foundation
import TemplateString

/// Provides the format to output an operation manifest file used for APQ registration.
struct LegacyAPQOperationManifestTemplate: OperationManifestTemplate {

  func render(operations: [OperationManifestItem]) -> String {
    template(operations).description
  }

  private func template(_ operations: [OperationManifestItem]) -> TemplateString {
    return TemplateString(
    """
    {
      \(forEachIn: operations, {
          return """
            "\($0.identifier)" : {
              "name": "\($0.operation.name)",
              "source": "\($0.operation.sourceTextFormattedForManifestJSONBody)"
            }
            """
        })
    }
    """
    )
  }

}
