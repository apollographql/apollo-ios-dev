import Foundation
import ArgumentParser
import ApolloCodegenLib

public struct FetchSchema: AsyncParsableCommand {

  // MARK: - Configuration

  public static var configuration = CommandConfiguration(
    commandName: "fetch-schema",
    abstract: "Download a GraphQL schema from the Apollo Registry or GraphQL introspection."
  )

  @OptionGroup var inputs: InputOptions

  // MARK: - Implementation

  public init() { }

  public func run() async throws {
    try await _run()
  }

  func _run(
    fileManager: FileManager = .default,
    schemaDownloadProvider: any SchemaDownloadProvider.Type = ApolloSchemaDownloader.self,
    logger: any LogLevelSetter.Type = CodegenLogger.self
  ) async throws {
    logger.SetLoggingLevel(verbose: inputs.verbose)

    try await fetchSchema(
      configuration: inputs.getCodegenConfiguration(fileManager: fileManager),
      schemaDownloadProvider: schemaDownloadProvider
    )    
  }

  private func fetchSchema(
    configuration codegenConfiguration: ApolloCodegenConfiguration,
    schemaDownloadProvider: any SchemaDownloadProvider.Type
  ) async throws {
    guard let schemaDownload = codegenConfiguration.schemaDownload else {
      throw Error(errorDescription: """
        Missing schema download configuration. Hint: check the `schemaDownload` \
        property of your configuration.
        """
      )
    }

    try await schemaDownloadProvider.fetch(
      configuration: schemaDownload,
      withRootURL: rootOutputURL(for: inputs),
      session: nil
    )
  }
}
