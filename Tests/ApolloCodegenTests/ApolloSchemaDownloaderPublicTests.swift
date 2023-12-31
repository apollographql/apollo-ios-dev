import XCTest
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers
import ApolloCodegenLib // Do not use @testable with this import! Plain `import` ensures the correct access modifiers are used.

class ApolloSchemaDownloaderPublicTests: XCTestCase {

  var testFilePathBuilder: TestFilePathBuilder!

  override func setUp() {
    super.setUp()
    testFilePathBuilder = TestFilePathBuilder(test: self)
  }

  override func tearDown() {
    testFilePathBuilder = nil
    super.tearDown()
  }

  func testCreatingSchemaDownloadConfiguration_forIntrospectionDownload_usingDefaultParameters() throws {
    let configuration = ApolloSchemaDownloadConfiguration(
      using: .introspection(endpointURL: TestURL.mockPort8080.url),
      outputPath: testFilePathBuilder.schemaOutputURL.path
    )

    XCTAssertEqual(configuration.downloadMethod, .introspection(endpointURL: TestURL.mockPort8080.url))
    XCTAssertEqual(configuration.outputPath, testFilePathBuilder.schemaOutputURL.path)
    XCTAssertTrue(configuration.headers.isEmpty)
  }

  func testCreatingSchemaDownloadConfiguration_forRegistryDownload_usingDefaultParameters() throws {
    let settings = ApolloSchemaDownloadConfiguration.DownloadMethod.ApolloRegistrySettings(
      apiKey: "Fake_API_Key",
      graphID: "Fake_Graph_ID"
    )
    
    let configuration = ApolloSchemaDownloadConfiguration(
      using: .apolloRegistry(settings),
      outputPath: testFilePathBuilder.schemaOutputURL.path
    )

    XCTAssertEqual(configuration.downloadMethod, .apolloRegistry(settings))
    XCTAssertEqual(configuration.outputPath, testFilePathBuilder.schemaOutputURL.path)
    XCTAssertTrue(configuration.headers.isEmpty)
  }

  func testCreatingSchemaDownloadConfiguration_forRegistryDownload_usingAllParameters() throws {
    let settings = ApolloSchemaDownloadConfiguration.DownloadMethod.ApolloRegistrySettings(
      apiKey: "Fake_API_Key",
      graphID: "Fake_Graph_ID",
      variant: "Fake_Variant"
    )
    let headers = [
      ApolloSchemaDownloadConfiguration.HTTPHeader(
        key: "Authorization",
        value: "Bearer tokenGoesHere"
      ),
      ApolloSchemaDownloadConfiguration.HTTPHeader(
        key: "Custom-Header",
        value: "Custom_Customer"
      )
    ]

    let schemaFileName = "different_name"
    let outputURL = testFilePathBuilder.testIsolatedOutputFolder
      .appendingPathComponent("\(schemaFileName).graphqls")
    
    let configuration = ApolloSchemaDownloadConfiguration(
      using: .apolloRegistry(settings),
      headers: headers,
      outputPath: outputURL.path
    )

    XCTAssertEqual(configuration.downloadMethod, .apolloRegistry(settings))
    XCTAssertEqual(configuration.headers, headers)
    XCTAssertEqual(configuration.outputPath, outputURL.path)
  }
  
}

