import Foundation
import ArgumentParser
import ApolloCodegenLib

public struct GenerateOperationManifest: AsyncParsableCommand {

  // MARK: - Configuration
  
  public static var configuration = CommandConfiguration(
    abstract: "Generate Persisted Queries operation manifest based on a code generation configuration."
  )

  @OptionGroup var inputs: InputOptions

  // MARK: - Implementation
  
  public init() { }
  
  public func run() async throws {
    try await _run()
  }
  
  func _run(
    fileManager: FileManager = .default,
    projectRootURL: URL? = nil,
    codegenProvider: any CodegenProvider.Type = ApolloCodegen.self,
    logger: any LogLevelSetter.Type = CodegenLogger.self
  ) async throws {
    logger.SetLoggingLevel(verbose: inputs.verbose)

    let configuration = try inputs.getCodegenConfiguration(fileManager: fileManager)

    try validate(configuration: configuration, projectRootURL: projectRootURL)

    try await generateManifest(
      configuration: configuration,
      codegenProvider: codegenProvider
    )
  }
  
  private func generateManifest(
    configuration: ApolloCodegenConfiguration,
    codegenProvider: any CodegenProvider.Type
  ) async throws {
    try await codegenProvider.build(
      with: configuration,
      withRootURL: rootOutputURL(for: inputs),
      itemsToGenerate: [.operationManifest],
      operationIdentifierProvider: nil
    )
  }

  // MARK: - Validation

  func validate(
    configuration: ApolloCodegenConfiguration,
    projectRootURL: URL?
  ) throws {
    try checkForCLIVersionMismatch(with: inputs, projectRootURL: projectRootURL)

    guard configuration.operationManifest != nil else {
      throw ValidationError("""
          `operationManifest` section must be set in the codegen configuration JSON in order
          to generate an operation manifest.
          """)
    }
  }
  
}
