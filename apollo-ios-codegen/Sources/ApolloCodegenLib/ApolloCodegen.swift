import Foundation
import IR
import GraphQLCompiler
import OrderedCollections
import Utilities

// Only available on macOS
#if os(macOS)

/// A class to facilitate running code generation
public final class ApolloCodegen: Sendable {

  // MARK: - Public

  /// OptionSet used to configure what items should be generated during code generation.
  public struct ItemsToGenerate: OptionSet, Sendable {
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
  struct ConfigurationContext: Sendable, Equatable {
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
    
    processSchemaCustomizations(ir: ir)

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

          // To ensure generated files aren't accidentally pruned, pruning must be done after all
          // files are generated. Because of the async nature of this code, testing this is
          // difficult. When modifying this code, please ensure that pruning waits until after all
          // generated files are created before it begins.
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
      reduceGeneratedSchemaTypes: config.options.reduceGeneratedSchemaTypes,
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

    let sources = try await matches.concurrentCompactMap { match in
      try await frontend.makeSource(from: URL(fileURLWithPath: match))
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

    let documents = try await matches.concurrentCompactMap { match in
      try await frontend.parseDocument(from: URL(fileURLWithPath: match))
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
    var nonFatalErrors = NonFatalErrors()

    nonFatalErrors.merge(
      try await generateGraphQLDefinitionFiles(
        fragments: compilationResult.fragments,
        operations: compilationResult.operations,
        ir: ir,
        fileManager: fileManager
      )
    )

    nonFatalErrors.merge(
      try await generateSchemaFiles(ir: ir, fileManager: fileManager)
    )

    guard nonFatalErrors.isEmpty else {
      throw nonFatalErrors
    }
  }

  private func generateOperationManifest(
    operations: [CompilationResult.OperationDefinition],
    fileManager: ApolloFileManager
  ) async throws {
    let idFactory = self.operationIdentifierFactory

    let operationManifest = try await operations.concurrentCompactMap { operation in
      return (
        OperationDescriptor(operation),
        try await idFactory.identifier(for: operation)
      )
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
  ) async throws -> NonFatalErrors {
    let mergeNamedFragmentFields = config.experimentalFeatures.fieldMerging.options
      .contains(.namedFragments)

    /// A `ConfigurationContext` to use when generated local cache mutations.
    ///
    /// Local cache mutations require some codegen options to be overridden to generate valid objects. 
    /// This context overrides only the necessary properties, copying all other values from the user-provided `context`.
    lazy var cacheMutationContext: ConfigurationContext = {
      ConfigurationContext(
        config: ApolloCodegenConfiguration(
          schemaNamespace: self.config.schemaNamespace,
          input: self.config.input,
          output: self.config.output,
          options: self.config.options,
          experimentalFeatures: ApolloCodegenConfiguration.ExperimentalFeatures(
            fieldMerging: .all,
            legacySafelistingCompatibleOperations: self.config.experimentalFeatures.legacySafelistingCompatibleOperations
          ),
          schemaDownload: self.config.schemaDownload,
          operationManifest: self.config.operationManifest
        ),
        rootURL: self.config.rootURL
      )
    }()

    return try await nonFatalErrorCollectingTaskGroup() { group in
      for fragment in fragments {
        let fragmentConfig = fragment.isLocalCacheMutation ? cacheMutationContext : self.config

        group.addTask {
          let irFragment = await ir.build(
            fragment: fragment,
            mergingNamedFragmentFields: fragment.isLocalCacheMutation ? true : mergeNamedFragmentFields
          )

          let errors = try await FragmentFileGenerator(
            irFragment: irFragment,
            config: fragmentConfig
          ).generate(
            forConfig: fragmentConfig,
            fileManager: fileManager
          )
          return (irFragment.name, errors)
        }
      }

      for operation in operations {
        let operationConfig = operation.isLocalCacheMutation ? cacheMutationContext : self.config

        group.addTask {
          async let identifier = self.operationIdentifierFactory.identifier(for: operation)

          let irOperation = await ir.build(
            operation: operation,
            mergingNamedFragmentFields: operation.isLocalCacheMutation ? true : mergeNamedFragmentFields
          )

          let errors = try await OperationFileGenerator(
            irOperation: irOperation,
            operationIdentifier: await identifier,
            config: operationConfig
          ).generate(
            forConfig: operationConfig,
            fileManager: fileManager
          )
          return (irOperation.name, errors)
        }
      }
    }
  }
  
  func processSchemaCustomizations(ir: IRBuilder) {
    for (name, customization) in config.options.schemaCustomization.customTypeNames {
      if let type = ir.schema.referencedTypes.allTypes.first(where: { $0.name.schemaName == name }) {
        if type is GraphQLObjectType ||
            type is GraphQLInterfaceType ||
            type is GraphQLUnionType {
          switch customization {
          case .type(let name):
            type.name.customName = name
          default:
            break
          }
        } else if let scalarType = type as? GraphQLScalarType {
          guard scalarType.isCustomScalar else {
            return
          }
          
          switch customization {
          case .type(let name):
            type.name.customName = name
          default:
            break
          }
        } else if let enumType = type as? GraphQLEnumType {
          switch customization {
          case .type(let name):
            enumType.name.customName = name
            break
          case .enum(let name, let cases):
            enumType.name.customName = name
            
            if let cases = cases {
              for value in enumType.values {
                if let caseName = cases[value.name.schemaName] {
                  value.name.customName = caseName
                }
              }
            }
            break
          default:
            break
          }
        } else if let inputObjectType = type as? GraphQLInputObjectType {
          switch customization {
          case .type(let name):
            inputObjectType.name.customName = name
            break
          case .inputObject(let name, let fields):
            inputObjectType.name.customName = name
            
            if let fields = fields {
              for (_, field) in inputObjectType.fields {
                if let fieldName = fields[field.name.schemaName] {
                  field.name.customName = fieldName
                }
              }
            }
            break
          default:
            break
          }
        }
      }
    }
  }

  /// Generates the schema types and schema metadata files for the `ir`'s compiled schema.
  private func generateSchemaFiles(
    ir: IRBuilder,
    fileManager: ApolloFileManager
  ) async throws -> NonFatalErrors {
    let config = config

    var nonFatalErrors = NonFatalErrors()

    nonFatalErrors.merge(
      try await nonFatalErrorCollectingTaskGroup() { group in
        for graphqlObject in ir.schema.referencedTypes.objects {
          addFileGenerationTask(
            for: ObjectFileGenerator(
              graphqlObject: graphqlObject,
              config: config
            ),
            to: &group,
            fileManager: fileManager
          )

          if config.output.testMocks != .none {
            let fields = await ir.fieldCollector.collectedFields(for: graphqlObject)
            addFileGenerationTask(
              for: MockObjectFileGenerator(
                graphqlObject: graphqlObject,
                fields: fields,
                ir: ir,
                config: config
              ),
              to: &group,
              fileManager: fileManager
            )
          }
        }
      }
    )

    nonFatalErrors.merge(
      try await nonFatalErrorCollectingTaskGroup() { group in
        for graphqlEnum in ir.schema.referencedTypes.enums {
          addFileGenerationTask(
            for: EnumFileGenerator(
              graphqlEnum: graphqlEnum,
              config: config
            ),
            to: &group,
            fileManager: fileManager
          )
        }
      }
    )


    nonFatalErrors.merge(
      try await nonFatalErrorCollectingTaskGroup() { group in
        for graphqlInterface in ir.schema.referencedTypes.interfaces {
          addFileGenerationTask(
            for: InterfaceFileGenerator(
              graphqlInterface: graphqlInterface,
              config: config
            ),
            to: &group,
            fileManager: fileManager
          )
        }
      }
    )

    nonFatalErrors.merge(
      try await nonFatalErrorCollectingTaskGroup() { group in
        for graphqlUnion in ir.schema.referencedTypes.unions {
          addFileGenerationTask(
            for: UnionFileGenerator(
              graphqlUnion: graphqlUnion,
              config: config
            ),
            to: &group,
            fileManager: fileManager
          )
        }
      }
    )

    nonFatalErrors.merge(
      try await nonFatalErrorCollectingTaskGroup() { group in
        for graphqlInputObject in ir.schema.referencedTypes.inputObjects {
          addFileGenerationTask(
            for: InputObjectFileGenerator(
              graphqlInputObject: graphqlInputObject,
              config: config
            ),
            to: &group,
            fileManager: fileManager
          )
        }
      }
    )

    nonFatalErrors.merge(
      try await nonFatalErrorCollectingTaskGroup() { group in
        for graphqlScalar in ir.schema.referencedTypes.customScalars {
          addFileGenerationTask(
            for: CustomScalarFileGenerator(
              graphqlScalar: graphqlScalar,
              config: config
            ),
            to: &group, fileManager: fileManager
          )
        }
      }
    )

    nonFatalErrors.merge(
      try await nonFatalErrorCollectingTaskGroup() { group in
        if config.output.testMocks != .none {

          if let mockUnionsFileGenerator = MockUnionsFileGenerator(ir: ir,config: config) {
            addFileGenerationTask(
              for: mockUnionsFileGenerator,
              to: &group,
              fileManager: fileManager
            )
          }

          if let mockInterfacesFileGenerator = MockInterfacesFileGenerator(ir: ir, config: config) {
            addFileGenerationTask(
              for: mockInterfacesFileGenerator,
              to: &group,
              fileManager: fileManager
            )
          }
        }

        addFileGenerationTask(
          for: SchemaMetadataFileGenerator(
            schema: ir.schema,
            config: config
          ),
          to: &group,
          fileManager: fileManager
        )

        addFileGenerationTask(
          for: SchemaConfigurationFileGenerator(config: config),
          to: &group,
          fileManager: fileManager
        )

        group.addTask {
          let errors = try await SchemaModuleFileGenerator.generate(
            config,
            fileManager: fileManager
          )
          return ("SchemaModule", errors)
        }

      }
    )

    return nonFatalErrors
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
      try await fileManager.deleteFile(atPath: path)
    }
  }

}

// MARK: - Task Group Helpers

extension ApolloCodegen {
  fileprivate func nonFatalErrorCollectingTaskGroup(
    _ block: (inout ThrowingTaskGroup<NonFatalErrors.DefinitionEntry, any Swift.Error>) async throws -> Void
  ) async throws -> NonFatalErrors {
    return try await withThrowingTaskGroup(
      of: (NonFatalErrors.DefinitionEntry).self
    ) { group in
      try await block(&group)

      var results = OrderedDictionary<NonFatalErrors.FileName, [NonFatalError]>()
      for try await (definition, errors) in group {
        guard !errors.isEmpty else { continue }
        results[definition] = errors
      }

      return NonFatalErrors(errorsByFile: results)
    }
  }

  fileprivate func addFileGenerationTask(
    for fileGenerator: any FileGenerator,
    to group: inout ThrowingTaskGroup<ApolloCodegen.NonFatalErrors.DefinitionEntry, any Swift.Error>,
    fileManager: ApolloFileManager
  ) {
    let config = config

    group.addTask {
      let errors = try await fileGenerator.generate(
        forConfig: config,
        fileManager: fileManager
      )

      return (fileGenerator.fileName, errors)
    }
  }
}

#endif
