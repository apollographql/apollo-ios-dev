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

    guard
      !SwiftKeywords.DisallowedSchemaNamespaceNames.contains(self.schemaNamespace.lowercased())
    else {
      throw ApolloCodegen.Error.schemaNameConflict(name: self.schemaNamespace)
    }

    if case .swiftPackage = self.output.testMocks,
       self.output.schemaTypes.moduleType != .swiftPackageManager {
      throw ApolloCodegen.Error.testMocksInvalidSwiftPackageConfiguration
    }

    if case .swiftPackageManager = self.output.schemaTypes.moduleType,
       self.options.cocoapodsCompatibleImportStatements == true {
      throw ApolloCodegen.Error.invalidConfiguration(message: """
        cocoapodsCompatibleImportStatements cannot be set to 'true' when the output schema types \
        module type is Swift Package Manager. Change the cocoapodsCompatibleImportStatements \
        value to 'false', or choose a different module type, to resolve the conflict.
        """)
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
        namedType.swiftName == self.schemaNamespace.firstUppercased
      }),
      !compilationResult.fragments.contains(where: { fragmentDefinition in
        fragmentDefinition.name == self.schemaNamespace.firstUppercased
      })
    else {
      throw ApolloCodegen.Error.schemaNameConflict(name: self.schemaNamespace)
    }
  }

  // MARK: - GraphQL Definition Validation

  /// Validates that there are no type conflicts within a SelectionSet
  func validateTypeConflicts(
    for selectionSet: IR.SelectionSet,
    in containingObject: String,
    including parentTypes: [String: String] = [:]
  ) throws {
    // Check for type conflicts resulting from singularization/pluralization of fields
    var typeNamesByFormattedTypeName = [String: String]()

    var fields: [IR.EntityField] = selectionSet.selections.direct?.fields.values.compactMap { $0 as? IR.EntityField } ?? []
    fields.append(contentsOf: selectionSet.selections.merged.fields.values.compactMap { $0 as? IR.EntityField } )

    try fields.forEach { field in
      let formattedTypeName = field.formattedSelectionSetName(with: self.pluralizer)
      if let existingFieldName = typeNamesByFormattedTypeName[formattedTypeName] {
        throw ApolloCodegen.Error.typeNameConflict(
          name: existingFieldName,
          conflictingName: field.name,
          containingObject: containingObject
        )
      }
      typeNamesByFormattedTypeName[formattedTypeName] = field.name
    }

    // Combine `parentTypes` and `typeNamesByFormattedTypeName` to check against fragment names and
    // pass into recursive function calls
    var combinedTypeNames = parentTypes
    combinedTypeNames.merge(typeNamesByFormattedTypeName) { (current, _) in current }

    // passing each fields selection set for validation after we have fully built our `typeNamesByFormattedTypeName` dictionary
    try fields.forEach { field in
      try validateTypeConflicts(
        for: field.selectionSet,
        in: containingObject,
        including: combinedTypeNames
      )
    }

    var namedFragments: [IR.NamedFragment] = selectionSet.selections.direct?.namedFragments.values.map(\.fragment) ?? []
    namedFragments.append(contentsOf: selectionSet.selections.merged.namedFragments.values.map(\.fragment))

    try namedFragments.forEach { fragment in
      if let existingTypeName = combinedTypeNames[fragment.generatedDefinitionName] {
        throw ApolloCodegen.Error.typeNameConflict(
          name: existingTypeName,
          conflictingName: fragment.name,
          containingObject: containingObject
        )
      }
    }

    // gather nested fragments to loop through and check as well
    var nestedSelectionSets: [IR.SelectionSet] = selectionSet.selections.direct?.inlineFragments.values.map(\.selectionSet) ?? []
    nestedSelectionSets.append(contentsOf: selectionSet.selections.merged.inlineFragments.values.map(\.selectionSet))

    try nestedSelectionSets.forEach { nestedSet in
      try validateTypeConflicts(
        for: nestedSet,
        in: containingObject,
        including: combinedTypeNames
      )
    }
  }
}
