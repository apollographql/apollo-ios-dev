import Foundation
import TemplateString

/// Provides the format to define a Swift Package Manager module in Swift code. The output must
/// conform to the [configuration definition of a Swift package](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html#).
struct SwiftPackageManagerModuleTemplate: TemplateRenderer {

  let testMockConfig: ApolloCodegenConfiguration.TestMockFileOutput

  let target: TemplateTarget = .moduleFile

  let config: ApolloCodegen.ConfigurationContext
  
  let apolloSDKVersion: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType.ApolloSDKVersion
  
  init(
    testMockConfig: ApolloCodegenConfiguration.TestMockFileOutput,
    config: ApolloCodegen.ConfigurationContext
  ) {
    self.testMockConfig = testMockConfig
    self.config = config
    
    switch config.config.output.schemaTypes.moduleType {
    case .swiftPackage(let apolloSDKVersion):
      self.apolloSDKVersion = apolloSDKVersion
    default:
      self.apolloSDKVersion = .default
    }
  }

  func renderHeaderTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString? {
    nil
  }

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    let casedSchemaNamespace = config.schemaNamespace.firstUppercased

    return TemplateString("""
    // swift-tools-version:5.9

    import PackageDescription

    let package = Package(
      name: "\(casedSchemaNamespace)",
      platforms: [
        .iOS(.v12),
        .macOS(.v10_14),
        .tvOS(.v12),
        .watchOS(.v5),
      ],
      products: [
        .library(name: "\(casedSchemaNamespace)", targets: ["\(casedSchemaNamespace)"]),
        \(ifLet: testMockTarget(), { """
        .library(name: "\($0.targetName)", targets: ["\($0.targetName)"]),
        """})
      ],
      dependencies: [
        \(apolloSDKVersion.dependencyString),
      ],
      targets: [
        .target(
          name: "\(casedSchemaNamespace)",
          dependencies: [
            .product(name: "ApolloAPI", package: "apollo-ios"),
          ],
          path: "./Sources"
        ),
        \(ifLet: testMockTarget(), { """
        .target(
          name: "\($0.targetName)",
          dependencies: [
            .product(name: "ApolloTestSupport", package: "apollo-ios"),
            .target(name: "\(casedSchemaNamespace)"),
          ],
          path: "\($0.path)"
        ),
        """})
      ]
    )
    
    """)
  }

  private func testMockTarget() -> (targetName: String, path: String)? {
    switch testMockConfig {
    case .none, .absolute:
      return nil
    case let .swiftPackage(targetName):
      if let targetName = targetName {
        return (targetName.firstUppercased, "./\(targetName.firstUppercased)")
      } else {
        return ("\(config.schemaNamespace.firstUppercased)TestMocks", "./TestMocks")
      }
    }
  }
}

fileprivate extension ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType.ApolloSDKVersion {
  var dependencyString: TemplateString {
    switch self {
    case .default:
      return """
      .package(url: "https://github.com/apollographql/apollo-ios.git", exact: "\(Constants.CodegenVersion)")
      """
    case .branch(let name):
      return """
      .package(url: "https://github.com/apollographql/apollo-ios.git", branch: "\(name)")
      """
    case .commit(let hash):
      return """
      .package(url: "https://github.com/apollographql/apollo-ios.git", revision: "\(hash)")
      """
    case .local(let path):
      return """
      .package(path: "\(path)")
      """
    }
  }
}
