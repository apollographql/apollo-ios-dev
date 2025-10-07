import OrderedCollections
import TemplateString

// MARK: TemplateRenderer

/// Defines the file target of the template.
enum TemplateTarget: Equatable {
  /// Used in schema types files; enum, input object, union, etc.
  case schemaFile(type: SchemaFileType)
  /// Used in operation files; query, mutation, fragment, etc.
  case operationFile(moduleImports: OrderedSet<String>? = nil)
  /// Used in files that define a module; Swift Package Manager, etc.
  case moduleFile
  /// Used in test mock files; schema object `Mockable` extensions
  case testMockFile

  enum SchemaFileType: Equatable {
    case schemaMetadata
    case schemaConfiguration
    case object
    case interface
    case union
    case `enum`
    case customScalar
    case inputObject

    var namespaceComponent: String? {
      switch self {
      case .schemaMetadata, .enum, .customScalar, .inputObject, .schemaConfiguration:
        return nil
      case .object:
        return "Objects"
      case .interface:
        return "Interfaces"
      case .union:
        return "Unions"
      }
    }
  }
}

/// A protocol to handle the rendering of a file template based on the target file type and
/// codegen configuration.
///
/// All templates that output to a file should conform to this protocol, this does not include
/// templates that are used by others such as `HeaderCommentTemplate` or `ImportStatementTemplate`.
protocol TemplateRenderer: Sendable {
  /// Shared codegen configuration.
  var config: ApolloCodegen.ConfigurationContext { get }

  /// File target of the template.
  var target: TemplateTarget { get }

  /// Renders the header of the template.
  func renderHeaderTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString?

  /// Renders a template section that must be outside of any namespace wrapping.
  ///
  /// This section is rendered below the header and import statements and above the body and any
  /// namespace wrapper used in the template.
  func renderDetachedTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString?

  /// Renders the body of the template. This body can be rendered within any namespace wrapping.
  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString
}

// MARK: Extension - File rendering

extension TemplateRenderer {

  func renderHeaderTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString? {
    TemplateString(HeaderCommentTemplate.template.description)
  }

  func renderDetachedTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString? {
    nil
  }

  /// A tuple of the `String` for the `body` of a rendered template and an array of
  /// non-fatal `errors` that occured during rendering.
  ///
  /// If there are no non-fatal errors during rendering, the `errors` array will be empty.
  /// Any fatal errors should be thrown during rendering.
  typealias RenderResult = (body: String, errors: [ApolloCodegen.NonFatalError])

  /// Renders the template converting all input values and generating a final String
  /// representation of the template.
  ///
  /// - Parameter config: Shared codegen configuration.
  /// - Returns: Swift code derived from the template format.
  func render() -> RenderResult {
    let errorRecorder = ApolloCodegen.NonFatalError.Recorder()

    let body = {
      switch target {
      case .schemaFile(let type):
        return renderSchemaFile(type, errorRecorder)

      case .operationFile(let moduleImports):
        return renderOperationFile(moduleImports, errorRecorder)

      case .moduleFile:
        return renderModuleFile(errorRecorder)

      case .testMockFile:
        return renderTestMockFile(errorRecorder)
      }
    }()

    return (body, errorRecorder.recordedErrors)
  }

  private func renderSchemaFile(
    _ type: TemplateTarget.SchemaFileType,
    _ errorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> String {
    let namespace: String? = {
      if case .schemaConfiguration = type {
        return nil
      }

      let useSchemaNamespace = !config.output.schemaTypes.isInModule
      switch (useSchemaNamespace, type.namespaceComponent) {
      case (false, nil):
        return nil
      case (true, nil):
        return config.schemaNamespace.firstUppercased
      case (false, .some(let schemaTypeNamespace)):
        return schemaTypeNamespace
      case (true, .some(let schemaTypeNamespace)):
        return "\(config.schemaNamespace.firstUppercased).\(schemaTypeNamespace)"
      }
    }()

    return TemplateString(
      """
      \(ifLet: renderHeaderTemplate(nonFatalErrorRecorder: errorRecorder), { "\($0)\n" })
      \(ImportStatementTemplate.SchemaType.template(for: config, type: type))

      \(ifLet: renderDetachedTemplate(nonFatalErrorRecorder: errorRecorder), { "\($0)\n" })
      \(ifLet: namespace, {
      renderBodyTemplate(nonFatalErrorRecorder: errorRecorder)
        .wrappedInNamespace(
          $0,
          accessModifier: accessControlModifier(for: .namespace)
        )
      },
      else: renderBodyTemplate(nonFatalErrorRecorder: errorRecorder))
      """
    ).description
  }

  private func renderOperationFile(
    _ moduleImports: OrderedSet<String>?,
    _ errorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> String {
    TemplateString(
      """
      \(ifLet: renderHeaderTemplate(nonFatalErrorRecorder: errorRecorder), { "\($0)\n" })
      \(ImportStatementTemplate.Operation.template(for: config))
      \(ifLet: moduleImports, { "\(ModuleImportStatementTemplate.template(moduleImports: $0))" })

      \(if: config.output.operations.isInModule && !config.output.schemaTypes.isInModule,
      renderBodyTemplate(nonFatalErrorRecorder: errorRecorder)
        .wrappedInNamespace(
          config.schemaNamespace.firstUppercased,
          accessModifier: accessControlModifier(for: .namespace)
      ),
      else: renderBodyTemplate(nonFatalErrorRecorder: errorRecorder))
      """
    ).description
  }

  private func renderModuleFile(
    _ errorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> String {
    TemplateString(
      """
      \(ifLet: renderHeaderTemplate(nonFatalErrorRecorder: errorRecorder), { "\($0)\n" })
      \(renderBodyTemplate(nonFatalErrorRecorder: errorRecorder))
      """
    ).description
  }

  private func renderTestMockFile(
    _ errorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> String {
    TemplateString(
      """
      \(ifLet: renderHeaderTemplate(nonFatalErrorRecorder: errorRecorder), { "\($0)\n" })
      \(ImportStatementTemplate.TestMock.template(for: config))

      \(renderBodyTemplate(nonFatalErrorRecorder: errorRecorder))
      """
    ).description
  }
}

// MARK: Extension - Access modifier & SPI

extension TemplateRenderer {
  func accessControlModifier(for scope: AccessControlRenderer.Scope) -> String {
    self.accessControlRenderer(for: scope).accessControl()
  }

  func accessControlRenderer(for scope: AccessControlRenderer.Scope) -> AccessControlRenderer {
    return AccessControlRenderer(
      target: self.target,
      config: self.config.config,
      scope: scope
    )
  }
}

// MARK: Extension - Namespace

extension TemplateString {
  /// Wraps `self` in an extension on `namespace`.
  fileprivate func wrappedInNamespace(_ namespace: String, accessModifier: String) -> Self {
    TemplateString(
      """
      \(accessModifier)extension \(namespace) {
        \(self)
      }
      """
    )
  }
}

// MARK: - Header Comment Template

/// Provides the format to identify a file as automatically generated.
struct HeaderCommentTemplate {
  static let template: StaticString =
    """
    // @generated
    // This file was automatically generated and should not be edited.
    """

  static func editableFileHeader(fileCanBeEditedTo reason: TemplateString) -> TemplateString {
    """
    // @generated
    // This file was automatically generated and can be edited to
    \(comment: reason.description)
    //
    // Any changes to this file will not be overwritten by future
    // code generation execution.
    """
  }
}

// MARK: Import Statement Template

/// Provides the format to import Swift modules required by the template type.
struct ImportStatementTemplate {

  enum SchemaType {
    static func template(
      for config: ApolloCodegen.ConfigurationContext,
      type: TemplateTarget.SchemaFileType
    ) -> String {
      let apolloAPIImport = "import \(TemplateConstants.ApolloAPITargetName)"
      switch type {
      case .inputObject:
        return "@_spi(Internal) @_spi(Unsafe) \(apolloAPIImport)"
      case .customScalar:
        return "@_spi(Internal) @_spi(Execution) \(apolloAPIImport)"
      case .enum:
        return "@_spi(Internal) \(apolloAPIImport)"
      default:
        return apolloAPIImport
      }
    }
  }

  enum Operation {
    static func template(
      for config: ApolloCodegen.ConfigurationContext
    ) -> TemplateString {
      return """
        @_exported import \(TemplateConstants.ApolloAPITargetName)
        @_spi(Execution) @_spi(Unsafe) import \(TemplateConstants.ApolloAPITargetName)
        \(if: config.output.operations != .inSchemaModule, "import \(config.schemaModuleName)")
        """
    }
  }

  enum TestMock {
    static func template(for config: ApolloCodegen.ConfigurationContext) -> TemplateString {
      return """
        import ApolloTestSupport
        @testable import \(config.schemaModuleName)
        """
    }
  }
}

/// Provides the format to import additional Swift modules required by the template type.
/// These are custom import statements defined using the `@import(module:)` directive.
struct ModuleImportStatementTemplate {

  static func template(
    moduleImports: OrderedSet<String>
  ) -> TemplateString {
    return """
      \(moduleImports.map { "import \($0)" }.joined(separator: "\n"))
      """
  }

}

fileprivate extension ApolloCodegenConfiguration {
  var schemaModuleName: String {
    switch output.schemaTypes.moduleType {
    case .embeddedInTarget(let targetName, _): return targetName
    case .swiftPackage, .other: return schemaNamespace.firstUppercased
    }
  }
}
