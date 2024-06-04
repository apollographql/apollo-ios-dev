import Foundation
import ArgumentParser
import ApolloCodegenLib

public struct Generate: AsyncParsableCommand {

  // MARK: - Configuration
  
  public static var configuration = CommandConfiguration(
    abstract: "Generate Swift source code based on a code generation configuration."
  )

  @OptionGroup var inputs: InputOptions

  @Flag(
    name: .shortAndLong,
    help: "Fetch the GraphQL schema before Swift code generation."
  )
  var fetchSchema: Bool = false

  // MARK: - Implementation

  public init() { }

  public func run() async throws {
    try await _run()
  }

  func _run(
    fileManager: FileManager = .default,
    projectRootURL: URL? = nil,
    codegenProvider: any CodegenProvider.Type = ApolloCodegen.self,
    schemaDownloadProvider: any SchemaDownloadProvider.Type = ApolloSchemaDownloader.self,
    logger: any LogLevelSetter.Type = CodegenLogger.self
  ) async throws {
    logger.SetLoggingLevel(verbose: inputs.verbose)

    try checkForCLIVersionMismatch(
      with: inputs,
      projectRootURL: projectRootURL
    )

    try await generate(
      configuration: inputs.getCodegenConfiguration(fileManager: fileManager),
      codegenProvider: codegenProvider,
      schemaDownloadProvider: schemaDownloadProvider
    )
  }

  private func generate(
    configuration: ApolloCodegenConfiguration,
    codegenProvider: any CodegenProvider.Type,
    schemaDownloadProvider: any SchemaDownloadProvider.Type
  ) async throws {
    if fetchSchema {
      guard
        let schemaDownload = configuration.schemaDownload
      else {
        throw Error(errorDescription: """
          Missing schema download configuration. Hint: check the `schemaDownload` \
          property of your configuration.
          """
        )
      }

      try await fetchSchema(
        configuration: schemaDownload,
        schemaDownloadProvider: schemaDownloadProvider
      )
    }
    
    var itemsToGenerate: ApolloCodegen.ItemsToGenerate = .code
        
    if let operationManifest = configuration.operationManifest,
        operationManifest.generateManifestOnCodeGeneration {
      itemsToGenerate.insert(.operationManifest)
    }

    try await codegenProvider.build(
      with: configuration,
      withRootURL: rootOutputURL(for: inputs),
      itemsToGenerate: itemsToGenerate,
      operationIdentifierProvider: nil
    )
  }

  private func fetchSchema(
    configuration: ApolloSchemaDownloadConfiguration,
    schemaDownloadProvider: any SchemaDownloadProvider.Type
  ) async throws {
    try await schemaDownloadProvider.fetch(
      configuration: configuration,
      withRootURL: rootOutputURL(for: inputs),
      session: nil
    )
  }
}
