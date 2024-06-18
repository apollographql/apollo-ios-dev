#if os(macOS)
import XCTest
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers
@testable import ApolloCodegenLib
@testable import GraphQLCompiler

class StarWarsApolloSchemaDownloaderTests: XCTestCase {

  func testDownloadingSchema_usingIntrospection_shouldOutputSDL() async throws {
    let fileManager = try testIsolatedFileManager()

    let configuration = ApolloSchemaDownloadConfiguration(
      using: .introspection(endpointURL: TestServerURL.starWarsServer.url),
      outputPath: fileManager.filePathBuilder.schemaOutputURL.path
    )

    XCTAssertFalse(ApolloFileManager.default.doesFileExist(atPath: configuration.outputPath))

    try await ApolloSchemaDownloader.fetch(configuration: configuration)

    // Does the file now exist?
    XCTAssertTrue(ApolloFileManager.default.doesFileExist(atPath: configuration.outputPath))

    // Is it non-empty?
    let data = try Data(contentsOf: URL(fileURLWithPath: configuration.outputPath))
    XCTAssertFalse(data.isEmpty)

    // It should not be JSON
    XCTAssertNil(try? JSONSerialization.jsonObject(with: data, options: []) as? [AnyHashable:Any])

    // Can it be turned into the expected schema?
    let frontend = try await GraphQLJSFrontend()
    let source = try await frontend.makeSource(from: URL(fileURLWithPath: configuration.outputPath))
    let schema = try await frontend.loadSchema(from: [source])
    let episodeType = try await schema.getType(named: "Episode")
    XCTAssertEqual(episodeType?.name.schemaName, "Episode")

    // OK delete it now
    try ApolloFileManager.default.deleteFile(atPath: configuration.outputPath)
    XCTAssertFalse(ApolloFileManager.default.doesFileExist(atPath: configuration.outputPath))
  }

}
#endif
