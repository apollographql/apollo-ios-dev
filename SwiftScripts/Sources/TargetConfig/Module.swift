import Foundation
import ApolloCodegenLib

public struct Module {
  public let moduleType: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType

  public init?(module: String) {
    switch module.lowercased() {
    case "none": self.moduleType = .embeddedInTarget(name: "")
    case "swiftpackagemanager", "spm": self.moduleType = .swiftPackage(apolloSDKDependency: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType.ApolloSDKDependency(
      sdkVersion: .local(path: "../../../apollo-ios")
    ))
    case "other": self.moduleType = .other
    default: return nil
    }
  }
}
