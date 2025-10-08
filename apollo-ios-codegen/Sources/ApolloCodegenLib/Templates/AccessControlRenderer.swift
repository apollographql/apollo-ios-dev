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

  private let accessModifier: ApolloCodegenConfiguration.AccessModifier?

  init(
    target: TemplateTarget,
    config: ApolloCodegenConfiguration,
    scope: Scope
  ) {
    self.accessModifier = Self.accessControlModifier(target: target, config: config, scope: scope)
  }

  func accessControl(withSPIs spis: [SPI] = []) -> String {
    var string = accessModifier?.swiftString ?? ""

    guard shouldIncludeSPI else { return string }

    for spi in spis {
      string = "@_spi(\(spi)) " + string
    }
    return string
  }

  /// SPI should only be used on public declarations. Internal declarations must omit them.
  private var shouldIncludeSPI: Bool {
    accessModifier == .public
  }

  private static func accessControlModifier(
    target: TemplateTarget,
    config: ApolloCodegenConfiguration,
    scope: Scope
  ) -> ApolloCodegenConfiguration.AccessModifier? {
    switch target {
    case .moduleFile, .schemaFile: return schemaAccessControlModifier(scope, config)
    case .operationFile: return operationAccessControlModifier(scope, config)
    case .testMockFile: return testMockAccessControlModifier(scope, config)
    }
  }

  private static func schemaAccessControlModifier(
    _ scope: Scope,
    _ config: ApolloCodegenConfiguration,
  ) -> ApolloCodegenConfiguration.AccessModifier? {
    switch (config.output.schemaTypes.moduleType, scope) {
    case (.embeddedInTarget, .parent):
      return nil
    case (.embeddedInTarget(_, .public), .namespace),
      (.embeddedInTarget(_, .public), .member):
      return .public
    case (.embeddedInTarget(_, .internal), .namespace),
      (.embeddedInTarget(_, .internal), .member):
      return .internal
    case (.swiftPackage, _),
      (.other, _):
      return .public
    }
  }

  private static func operationAccessControlModifier(
    _ scope: Scope,
    _ config: ApolloCodegenConfiguration,
  ) -> ApolloCodegenConfiguration.AccessModifier? {
    switch (config.output.operations, scope) {
    case (.inSchemaModule, _):
      return schemaAccessControlModifier(scope, config)
    case (.absolute(_, .public), _),
      (.relative(_, .public), _):
      return .public
    case (.absolute(_, .internal), _),
      (.relative(_, .internal), _):
      return .internal
    }
  }

  private static func testMockAccessControlModifier(
    _ scope: Scope,
    _ config: ApolloCodegenConfiguration,
  ) -> ApolloCodegenConfiguration.AccessModifier? {
    switch (config.output.testMocks, scope) {
    case (.none, _):
      return nil
    case (.absolute(_, .internal), _):
      return .internal
    case (.swiftPackage, _),
      (.absolute(_, .public), _):
      return .public
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
