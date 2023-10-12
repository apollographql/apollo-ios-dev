import Foundation
import IR
import GraphQLCompiler
import OrderedCollections

// Only available on macOS
#if os(macOS)

/// A class to facilitate running code generation
public class ApolloCodegen {

  // MARK: Public

  /// Errors that can occur during code generation.
  public enum Error: Swift.Error, LocalizedError {
    /// An error occured during validation of the GraphQL schema or operations.
    case graphQLSourceValidationFailure(atLines: [String])
    case testMocksInvalidSwiftPackageConfiguration
    case inputSearchPathInvalid(path: String)
    case schemaNameConflict(name: String)
    case cannotLoadSchema
    case cannotLoadOperations
    case invalidConfiguration(message: String)
    case invalidSchemaName(_ name: String, message: String)
    case targetNameConflict(name: String)
    case typeNameConflict(name: String, conflictingName: String, containingObject: String)

    public var errorDescription: String? {
      switch self {
      case let .graphQLSourceValidationFailure(lines):
        return """
          An error occured during validation of the GraphQL schema or operations! Check \(lines)
          """
      case .testMocksInvalidSwiftPackageConfiguration:
        return """
          Schema Types must be generated with module type 'swiftPackageManager' to generate a \
          swift package for test mocks.
          """
      case let .inputSearchPathInvalid(path):
        return """
          Input search path '\(path)' is invalid. Input search paths must include a file \
          extension component. (eg. '.graphql')
          """
      case let .schemaNameConflict(name):
        return """
          Schema namespace '\(name)' conflicts with name of a type in the generated code. Please \
          choose a different schema name. Suggestions: \(name)Schema, \(name)GraphQL, \(name)API.
          """
      case .cannotLoadSchema:
        return "A GraphQL schema could not be found. Please verify the schema search paths."
      case .cannotLoadOperations:
        return "No GraphQL operations could be found. Please verify the operation search paths."
      case let .invalidConfiguration(message):
        return "The codegen configuration has conflicting values: \(message)"
      case let .invalidSchemaName(name, message):
        return "The schema namespace `\(name)` is invalid: \(message)"
      case let .targetNameConflict(name):
        return """
        Target name '\(name)' conflicts with a reserved library name. Please choose a different \
        target name.
        """
      case let .typeNameConflict(name, conflictingName, containingObject):
        return """
        TypeNameConflict - \
        Field '\(conflictingName)' conflicts with field '\(name)' in operation/fragment `\(containingObject)`. \
        Recommend using a field alias for one of these fields to resolve this conflict. \
        For more info see: https://www.apollographql.com/docs/ios/troubleshooting/codegen-troubleshooting#typenameconflict
        """
      }
    }
  }
  
  /// OptionSet used to configure what items should be generated during code generation.
  public struct ItemsToGenerate: OptionSet {
    public var rawValue: Int
    
    /// Only generate your code (Operations, Fragments, Enums, etc), this option maintains the codegen functionality
    /// from before this option set was created.
    public static let code = ItemsToGenerate(rawValue: 1 << 0)
    
    /// Only generate the operation manifest used for persisted queries and automatic persisted queries.
    public static let operationManifest = ItemsToGenerate(rawValue: 1 << 1)
    
    /// Generate all available items during code generation.
    public static let all: ItemsToGenerate = [
      .code,
      .operationManifest
    ]
    
    public init(rawValue: Int) {
      self.rawValue = rawValue
    }
    
  }

  /// Executes the code generation engine with a specified configuration.
  ///
  /// - Parameters:
  ///   - configuration: A configuration object that specifies inputs, outputs and behaviours used
  ///     during code generation.
  ///   - rootURL: The root `URL` to resolve relative `URL`s in the configuration's paths against.
  ///     If `nil`, the current working directory of the executing process will be used.
  ///   - itemsToGenerate: Uses the `ItemsToGenerate` option set to determine what items should be generated during codegen.
  ///     By default this will use [.code] which maintains how codegen functioned prior to these options being added.
  ///   - operationIdentifierProvider: [optional] An async closure used to compute the operation
  ///     identifiers for operations in the persisted queries manifest. If not provided, the default
  ///     identifier will be computed as a SHA256 hash of the operation's source text.
  public static func build(
    with configuration: ApolloCodegenConfiguration,
    withRootURL rootURL: URL? = nil,
    itemsToGenerate: ItemsToGenerate = [.code],
    operationIdentifierProvider: OperationIdentifierProvider? = nil
  ) async throws {
    let idFactory = OperationIdentifierFactory(
      idProvider: operationIdentifierProvider ?? DefaultOperationIdentifierProvider
    )

    let codegen = ApolloCodegen(
      config: ConfigurationContext(
        config: configuration,
        rootURL: rootURL
      ),
      operationIdentifierFactory: idFactory,
      itemsToGenerate: itemsToGenerate
    )

    try await codegen.build()
  }

  /// Validates the configuration against deterministic errors that will cause code generation to
  /// fail. This validation step does not take into account schema and operation specific types, it
  /// is only a static analysis of the configuration.
  ///
  /// - Parameter config: Code generation configuration settings.
  public static func _validate(config: ApolloCodegenConfiguration) throws {
    try ConfigurationContext(config: config).validateConfigValues()
  }

  // MARK: - Internal

  @dynamicMemberLookup
  class ConfigurationContext {
    let config: ApolloCodegenConfiguration
    let pluralizer: Pluralizer
    let rootURL: URL?

    init(
      config: ApolloCodegenConfiguration,
      rootURL: URL? = nil
    ) {
      self.config = config
      self.pluralizer = Pluralizer(rules: config.options.additionalInflectionRules)
      self.rootURL = rootURL?.standardizedFileURL
    }

    subscript<T>(dynamicMember keyPath: KeyPath<ApolloCodegenConfiguration, T>) -> T {
      config[keyPath: keyPath]
    }
  }

  let config: ConfigurationContext
  let operationIdentifierFactory: OperationIdentifierFactory
  let itemsToGenerate: ItemsToGenerate

  init(
    config: ConfigurationContext,
    operationIdentifierFactory: OperationIdentifierFactory,
    itemsToGenerate: ItemsToGenerate
  ) {
    self.config = config
    self.operationIdentifierFactory = operationIdentifierFactory
    self.itemsToGenerate = itemsToGenerate
  }

  internal func build(fileManager: ApolloFileManager = .default) async throws {
    try config.validateConfigValues()
    
    let compilationResult = try await compileGraphQLResult()

    try config.validate(compilationResult)
    
    let ir = IRBuilder(compilationResult: compilationResult)
    
    try await withThrowingTaskGroup(of: Void.self) { group in
      if itemsToGenerate.contains(.operationManifest) {
        group.addTask {
          try await self.generateOperationManifest(
            operations: compilationResult.operations,
            fileManager: fileManager
          )
        }
      }
      
      if itemsToGenerate.contains(.code) {
        group.addTask { [self] in
          let existingGeneratedFilePaths = config.options.pruneGeneratedFiles ?
          try findExistingGeneratedFilePaths(fileManager: fileManager) : []

          try await self.generateFiles(
            compilationResult: compilationResult,
            ir: ir,
            fileManager: fileManager
          )

          if config.options.pruneGeneratedFiles {
            try await self.deleteExtraneousGeneratedFiles(
              from: existingGeneratedFilePaths,
              afterCodeGenerationUsing: fileManager
            )
          }
        }
      }
      try await group.waitForAll()
    }
  }

  /// Performs GraphQL source validation and compiles the schema and operation source documents.
  func compileGraphQLResult() async throws -> CompilationResult {
    let frontend = try await GraphQLJSFrontend()
    async let graphQLSchema = try createSchema(frontend)
    async let operationsDocument = try createOperationsDocument(frontend)
    let validationOptions = ValidationOptions(config: config)

    let graphqlErrors = try await frontend.validateDocument(
      schema: graphQLSchema,
      document: operationsDocument,
      validationOptions: validationOptions
    )

    guard graphqlErrors.isEmpty else {
      let errorlines = graphqlErrors.flatMap({
        if let logLines = $0.logLines {
          return logLines
        } else {
          return ["\($0.name ?? "unknown"): \($0.message ?? "")"]
        }
      })
      CodegenLogger.log(errorlines.joined(separator: "\n"), logLevel: .error)
      throw Error.graphQLSourceValidationFailure(atLines: errorlines)
    }

    return try await frontend.compile(
      schema: graphQLSchema,
      document: operationsDocument,
      experimentalLegacySafelistingCompatibleOperations:
        config.experimentalFeatures.legacySafelistingCompatibleOperations,
      validationOptions: validationOptions
    )
  }

  func createSchema(
    _ frontend: GraphQLJSFrontend
  ) async throws -> GraphQLSchema {
    let matches = try Self.match(
      searchPaths: config.input.schemaSearchPaths,
      relativeTo: config.rootURL
    )

    guard !matches.isEmpty else {
      throw Error.cannotLoadSchema
    }

    let sources = try await withThrowingTaskGroup(of: (Int, GraphQLSource).self) { group in
      for (index, match) in matches.enumerated() {
        group.addTask {
          (index, try await frontend.makeSource(from: URL(fileURLWithPath: match)))
        }
      }
        var sources: [GraphQLSource?] = Array(repeating: nil, count: matches.count)

      for try await (index, source) in group {
        sources[index] = source
      }

      return sources.compactMap { $0 }
    }

    return try await frontend.loadSchema(from: sources)
  }

  func createOperationsDocument(
    _ frontend: GraphQLJSFrontend
  ) async throws -> GraphQLDocument {
    let matches = try Self.match(
      searchPaths: config.input.operationSearchPaths,
      relativeTo: config.rootURL)

    guard !matches.isEmpty else {
      throw Error.cannotLoadOperations
    }

    let documents = try await withThrowingTaskGroup(of: (Int, GraphQLDocument).self) { group in
      for (index, match) in matches.enumerated() {
        group.addTask {
          (index, try await frontend.parseDocument(
            from: URL(fileURLWithPath: match),
            experimentalClientControlledNullability:
              self.config.experimentalFeatures.clientControlledNullability
          ))
        }
      }

      var documents: [GraphQLDocument?] = Array(repeating: nil, count: matches.count)
      for try await (index, document) in group {
        documents[index] = document
      }

      return documents.compactMap { $0 }
    }

    return try await frontend.mergeDocuments(documents)
  }

  static func match(searchPaths: [String], relativeTo relativeURL: URL?) throws -> OrderedSet<String> {
    let excludedDirectories = [
      ".build",
      ".swiftpm",
      ".Pods"]

    return try Glob(searchPaths, relativeTo: relativeURL)
      .match(excludingDirectories: excludedDirectories)
  }

  /// Generates Swift files for the compiled schema, ir and configured output structure.
  func generateFiles(
    compilationResult: CompilationResult,
    ir: IRBuilder,
    fileManager: ApolloFileManager
  ) async throws {
    try await generateGraphQLDefinitionFiles(
      fragments: compilationResult.fragments,
      operations: compilationResult.operations,
      ir: ir,
      fileManager: fileManager
    )

    try await generateSchemaFiles(ir: ir, fileManager: fileManager)
  }

  private func generateOperationManifest(
    operations: [CompilationResult.OperationDefinition],
    fileManager: ApolloFileManager
  ) async throws {
    let idFactory = self.operationIdentifierFactory

    let operationManifest = try await withThrowingTaskGroup(
      of: (Int, item: OperationManifestTemplate.OperationManifestItem).self,
      returning: OperationManifestTemplate.OperationManifest.self
    ) { group in
      for (index, operation) in operations.enumerated() {
        group.addTask {
          return (index, item: (
            OperationDescriptor(operation),
            try await idFactory.identifier(for: operation)
          ))
        }
      }

      var operationManifest: [OperationManifestTemplate.OperationManifestItem?] = Array(repeating: nil, count: operations.count)
      for try await (index, item) in group {
        operationManifest[index] = item
      }
      return operationManifest.compactMap { $0 }
    }

    try await OperationManifestFileGenerator(config: config)
      .generate(
        operationManifest: operationManifest,
        fileManager: fileManager
      )
  }

  /// Generates the files for the GraphQL fragments and operation definitions provided.
  private func generateGraphQLDefinitionFiles(
    fragments: [CompilationResult.FragmentDefinition],
    operations: [CompilationResult.OperationDefinition],
    ir: IRBuilder,
    fileManager: ApolloFileManager
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      for fragment in fragments {
        group.addTask {
          let irFragment = await ir.build(fragment: fragment)
          try self.config.validateTypeConflicts(
            for: irFragment.rootField.selectionSet,
            in: irFragment.definition.name
          )
          try await FragmentFileGenerator(irFragment: irFragment, config: self.config)
            .generate(forConfig: self.config, fileManager: fileManager)
        }
      }

      for operation in operations {
        group.addTask {
          async let identifier = self.operationIdentifierFactory.identifier(for: operation)

          let irOperation = await ir.build(operation: operation)
          try self.config.validateTypeConflicts(
            for: irOperation.rootField.selectionSet,
            in: irOperation.definition.name
          )

          try await OperationFileGenerator(
            irOperation: irOperation,
            operationIdentifier: await identifier,
            config: self.config
          ).generate(forConfig: self.config, fileManager: fileManager)
        }
      }
      
      try await group.waitForAll()
    }
  }

  /// Generates the schema types and schema metadata files for the `ir`'s compiled schema.
  private func generateSchemaFiles(
    ir: IRBuilder,
    fileManager: ApolloFileManager
  ) async throws {
    let config = config

    try await withThrowingTaskGroup(of: Void.self) { group in
      for graphQLObject in ir.schema.referencedTypes.objects {
        group.addTask {
          try await ObjectFileGenerator(
            graphqlObject: graphQLObject,
            config: config
          ).generate(
            forConfig: config,
            fileManager: fileManager
          )

          if config.output.testMocks != .none {
            let fields = await ir.fieldCollector.collectedFields(for: graphQLObject)
            try await MockObjectFileGenerator(
              graphqlObject: graphQLObject,
              fields: fields,
              ir: ir,
              config: config
            ).generate(
              forConfig: config,
              fileManager: fileManager
            )
          }
        }
      }

      try await group.waitForAll()
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for graphQLEnum in ir.schema.referencedTypes.enums {
        group.addTask {
          try await EnumFileGenerator(graphqlEnum: graphQLEnum, config: config)
            .generate(forConfig: config, fileManager: fileManager)
        }
      }
      try await group.waitForAll()
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for graphQLInterface in ir.schema.referencedTypes.interfaces {
        group.addTask {
          try await InterfaceFileGenerator(graphqlInterface: graphQLInterface, config: config)
            .generate(forConfig: config, fileManager: fileManager)
        }
      }
      try await group.waitForAll()
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for graphQLUnion in ir.schema.referencedTypes.unions {
        group.addTask {
          try await UnionFileGenerator(
            graphqlUnion: graphQLUnion,
            config: config
          ).generate(
            forConfig: config,
            fileManager: fileManager
          )
        }
      }
      try await group.waitForAll()
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for graphQLInputObject in ir.schema.referencedTypes.inputObjects {
        group.addTask {
          try await InputObjectFileGenerator(
            graphqlInputObject: graphQLInputObject,
            config: config
          ).generate(
            forConfig: config,
            fileManager: fileManager
          )
        }
      }
      try await group.waitForAll()
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for graphQLScalar in ir.schema.referencedTypes.customScalars {
        group.addTask {
          try await CustomScalarFileGenerator(graphqlScalar: graphQLScalar, config: config)
            .generate(forConfig: config, fileManager: fileManager)
        }
      }
      try await group.waitForAll()
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      if config.output.testMocks != .none {
        group.addTask {
          try await MockUnionsFileGenerator(
            ir: ir,
            config: config
          )?.generate(
            forConfig: config,
            fileManager: fileManager
          )
        }

        group.addTask {
          try await MockInterfacesFileGenerator(
            ir: ir,
            config: config
          )?.generate(
            forConfig: config,
            fileManager: fileManager
          )
        }
      }

      group.addTask {
        try await SchemaMetadataFileGenerator(schema: ir.schema, config: config)
          .generate(forConfig: config, fileManager: fileManager)
      }
      group.addTask {
        try await SchemaConfigurationFileGenerator(config: config)
          .generate(forConfig: config, fileManager: fileManager)
      }

      group.addTask {
        try await SchemaModuleFileGenerator.generate(config, fileManager: fileManager)
      }

      try await group.waitForAll()
    }
  }

  /// MARK: - Generated File Pruning

  private func findExistingGeneratedFilePaths(
    fileManager: ApolloFileManager = .default
  ) throws -> Set<String> {
    var globs: [Glob] = []
    globs.append(Glob(
      ["\(config.output.schemaTypes.path)/**/*.graphql.swift"],
      relativeTo: config.rootURL
    ))

    switch config.output.operations {
    case .inSchemaModule: break

    case let .absolute(operationsPath, _):
      globs.append(Glob(
        ["\(operationsPath)/**/*.graphql.swift"],
        relativeTo: config.rootURL
      ))

    case let .relative(subpath, _):
      let searchPaths = config.input.operationSearchPaths.map { searchPath -> String in
        let startOfLastPathComponent = searchPath.lastIndex(of: "/") ?? searchPath.firstIndex(of: ".")!
        var path = searchPath.prefix(upTo: startOfLastPathComponent)
        if let subpath = subpath {
          path += "/\(subpath)"
        }
        path += "/*.graphql.swift"
        return path.description
      }

      globs.append(Glob(
        searchPaths,
        relativeTo: config.rootURL
      ))
    }

    switch config.output.testMocks {
    case let .absolute(testMocksPath, _):
      globs.append(Glob(
        ["\(testMocksPath)/**/*.graphql.swift"],
        relativeTo: config.rootURL
      ))
    default: break
    }

    return try globs.reduce(into: []) { partialResult, glob in
      partialResult.formUnion(try glob.match())
    }
  }

  func deleteExtraneousGeneratedFiles(
    from oldGeneratedFilePaths: Set<String>,
    afterCodeGenerationUsing fileManager: ApolloFileManager
  ) async throws {
    let filePathsToDelete = await oldGeneratedFilePaths.subtracting(fileManager.writtenFiles)

    for path in filePathsToDelete {
      try fileManager.deleteFile(atPath: path)
    }
  }

}

#endif
