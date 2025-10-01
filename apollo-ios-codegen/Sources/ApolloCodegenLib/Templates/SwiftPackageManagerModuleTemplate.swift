import Foundation
import TemplateString

/// Provides the format to define a Swift Package Manager module in Swift code. The output must
/// conform to the [configuration definition of a Swift package](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html#).
struct SwiftPackageManagerModuleTemplate: TemplateRenderer {

  let testMockConfig: ApolloCodegenConfiguration.TestMockFileOutput

  let target: TemplateTarget = .moduleFile

  let config: ApolloCodegen.ConfigurationContext
  
  let apolloSDKDependency: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType.ApolloSDKDependency
  
  init(
    testMockConfig: ApolloCodegenConfiguration.TestMockFileOutput,
    config: ApolloCodegen.ConfigurationContext
  ) {
    self.testMockConfig = testMockConfig
    self.config = config
    
    switch config.config.output.schemaTypes.moduleType {
    case .swiftPackage(let apolloSDKDependency):
      self.apolloSDKDependency = apolloSDKDependency
    default:
      self.apolloSDKDependency = .default
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
    // swift-tools-version:6.1

    import PackageDescription

    let package = Package(
      name: "\(casedSchemaNamespace)",
      platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
      ],
      products: [
        .library(name: "\(casedSchemaNamespace)", targets: ["\(casedSchemaNamespace)"]),
        \(ifLet: testMockTarget(), { """
        .library(name: "\($0.targetName)", targets: ["\($0.targetName)"]),
        """})
      ],
      dependencies: [
        \(apolloSDKDependency.dependencyString),
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
      ],
      swiftLanguageModes: [.v6, .v5]
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

fileprivate extension ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType.ApolloSDKDependency {
  var dependencyString: TemplateString {
    switch self.sdkVersion {
    case .default:
      return """
      .package(url: "\(self.url)", exact: "\(Constants.CodegenVersion)")
      """
    case .branch(let name):
      return """
      .package(url: "\(self.url)", branch: "\(name)")
      """
    case .commit(let hash):
      return """
      .package(url: "\(self.url)", revision: "\(hash)")
      """
    case .exact(let version):
      return """
      .package(url: "\(self.url)", exact: "\(version)")
      """
    case .from(let version):
      return """
      .package(url: "\(self.url)", from: "\(version)")
      """
    case .local(let path):
      return """
      .package(name: "apollo-ios", path: "\(path)")
      """
    }
  }
}
