import Foundation

/// The @_spi values used by Apollo iOS
enum SPI {
  case Unsafe
  case Internal
  case Execution
}

struct AccessControlRenderer {

  enum Scope {
    case namespace
    case parent
    case member
  }

  private let computedModifier: String

  init(
    target: TemplateTarget,
    config: ApolloCodegenConfiguration,
    scope: Scope
  ) {
    self.computedModifier = Self.accessControlModifier(target: target, config: config, scope: scope)
  }

  func accessControl(withSPIs spis: [SPI] = []) -> String {
    var string = computedModifier
    for spi in spis {
      string = "@_spi(\(spi)) " + string
    }
    return string
  }

  private static func accessControlModifier(
    target: TemplateTarget,
    config: ApolloCodegenConfiguration,
    scope: Scope
  ) -> String {
    switch target {
    case .moduleFile, .schemaFile: return schemaAccessControlModifier(scope, config)
    case .operationFile: return operationAccessControlModifier(scope, config)
    case .testMockFile: return testMockAccessControlModifier(scope, config)
    }
  }

  private static func schemaAccessControlModifier(
    _ scope: Scope,
    _ config: ApolloCodegenConfiguration,
  ) -> String {
    switch (config.output.schemaTypes.moduleType, scope) {
    case (.embeddedInTarget, .parent):
      return ""
    case (.embeddedInTarget(_, .public), .namespace),
      (.embeddedInTarget(_, .public), .member):
      return ApolloCodegenConfiguration.AccessModifier.public.swiftString
    case (.embeddedInTarget(_, .internal), .namespace),
      (.embeddedInTarget(_, .internal), .member):
      return ApolloCodegenConfiguration.AccessModifier.internal.swiftString
    case (.swiftPackage, _),
      (.other, _):
      return ApolloCodegenConfiguration.AccessModifier.public.swiftString
    }
  }

  private static func operationAccessControlModifier(
    _ scope: Scope,
    _ config: ApolloCodegenConfiguration,
  ) -> String {
    switch (config.output.operations, scope) {
    case (.inSchemaModule, _):
      return schemaAccessControlModifier(scope, config)
    case (.absolute(_, .public), _),
      (.relative(_, .public), _):
      return ApolloCodegenConfiguration.AccessModifier.public.swiftString
    case (.absolute(_, .internal), _),
      (.relative(_, .internal), _):
      return ApolloCodegenConfiguration.AccessModifier.internal.swiftString
    }
  }

  private static func testMockAccessControlModifier(
    _ scope: Scope,
    _ config: ApolloCodegenConfiguration,
  ) -> String {
    switch (config.output.testMocks, scope) {
    case (.none, _):
      return ""
    case (.absolute(_, .internal), _):
      return ApolloCodegenConfiguration.AccessModifier.internal.swiftString
    case (.swiftPackage, _),
      (.absolute(_, .public), _):
      return ApolloCodegenConfiguration.AccessModifier.public.swiftString
    }
  }

}

fileprivate extension ApolloCodegenConfiguration.AccessModifier {
  var swiftString: String {
    switch self {
    case .public: return "public "  // there should be no spaces in these strings
    case .internal: return ""
    }
  }
}
