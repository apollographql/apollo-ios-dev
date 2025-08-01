import GraphQLCompiler
import IR

extension ApolloCodegen.ConfigurationContext {

  // MARK: - Config Value Validation

  /// Validates the configuration against deterministic errors that will cause code generation to
  /// fail. This validation step does not take into account schema and operation specific types, it
  /// is only a static analysis of the configuration.
  ///
  /// - Parameter config: Code generation configuration settings.
  func validateConfigValues() throws {
    guard
      !self.schemaNamespace.isEmpty,
      !self.schemaNamespace.contains(where: { $0.isWhitespace })
    else {
      throw ApolloCodegen.Error.invalidSchemaName(self.schemaNamespace, message: """
        Cannot be empty nor contain spaces. If your schema namespace has spaces consider \
        replacing them with the underscore character.
        """)
    }

    guard self.experimentalFeatures.fieldMerging == .all ||
            self.options.selectionSetInitializers == []
    else {
      throw ApolloCodegen.Error.fieldMergingIncompatibility
    }

    guard
      !SwiftKeywords.DisallowedSchemaNamespaceNames.contains(self.schemaNamespace.lowercased())
    else {
      throw ApolloCodegen.Error.schemaNameConflict(name: self.schemaNamespace)
    }

    if case .swiftPackage = self.output.testMocks {
      switch self.output.schemaTypes.moduleType {
      case .swiftPackage(_), .swiftPackageManager:
        break
      default:
        throw ApolloCodegen.Error.testMocksInvalidSwiftPackageConfiguration
      }
    }    

    if case let .embeddedInTarget(targetName, _) = self.output.schemaTypes.moduleType,
       SwiftKeywords.DisallowedEmbeddedTargetNames.contains(targetName.lowercased()) {
      throw ApolloCodegen.Error.targetNameConflict(name: targetName)
    }

    for searchPath in self.input.schemaSearchPaths {
      try validate(inputSearchPath: searchPath)
    }
    for searchPath in self.input.operationSearchPaths {
      try validate(inputSearchPath: searchPath)
    }
  }

  private func validate(inputSearchPath: String) throws {
    guard inputSearchPath.contains(".") && !inputSearchPath.hasSuffix(".") else {
      throw ApolloCodegen.Error.inputSearchPathInvalid(path: inputSearchPath)
    }
  }

  // MARK: - Compilation Result Validation

  /// Validates the configuration context against the GraphQL compilation result, checking for
  /// configuration errors that are dependent on the schema and operations.
  func validate(_ compilationResult: CompilationResult) throws {
    guard
      !compilationResult.referencedTypes.contains(where: { namedType in
        namedType.name.swiftName == self.schemaNamespace.firstUppercased
      }),
      !compilationResult.fragments.contains(where: { fragmentDefinition in
        fragmentDefinition.name == self.schemaNamespace.firstUppercased
      })
    else {
      throw ApolloCodegen.Error.schemaNameConflict(name: self.schemaNamespace)
    }
  }
  
}
