#if os(macOS)
import XCTest
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers
@testable import ApolloCodegenLib
@testable import GraphQLCompiler

class SchemaRegistryApolloSchemaDownloaderTests: XCTestCase {
  func testDownloadingSchema_fromSchemaRegistry_shouldOutputSDL() async throws {
    let fileManager = try testIsolatedFileManager()
    let testOutputFolderURL = fileManager.directoryURL

    XCTAssertFalse(ApolloFileManager.default.doesFileExist(atPath: testOutputFolderURL.path))

    guard let apiKey = ProcessInfo.processInfo.environment["REGISTRY_API_KEY"] else {
     throw XCTSkip("No API key could be fetched from the environment to test downloading from the schema registry")
    }

    let settings = ApolloSchemaDownloadConfiguration.DownloadMethod.ApolloRegistrySettings(
      apiKey: apiKey,
      graphID: "Apollo-Fullstack-8zo5jl"
    )
    let configuration = ApolloSchemaDownloadConfiguration(
      using: .apolloRegistry(settings),
      outputPath: testOutputFolderURL.path
    )

    try await ApolloSchemaDownloader.fetch(configuration: configuration)
    XCTAssertTrue(ApolloFileManager.default.doesFileExist(atPath: configuration.outputPath))

    // Can it be turned into the expected schema?
    let frontend = try await GraphQLJSFrontend()
    let source = try await frontend.makeSource(from: URL(fileURLWithPath: configuration.outputPath))
    let schema = try await frontend.loadSchema(from: [source])
    let rocketType = try await schema.getType(named: "Rocket")
    XCTAssertEqual(rocketType?.name.schemaName, "Rocket")
  }
}
#endif
