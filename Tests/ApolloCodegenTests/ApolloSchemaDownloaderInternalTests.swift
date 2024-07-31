import XCTest
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers
@testable import ApolloCodegenLib
@testable import GraphQLCompiler

class ApolloSchemaDownloaderInternalTests: XCTestCase {
  var mockFileManager: MockApolloFileManager!

  override func setUp() {
    super.setUp()
    mockFileManager = MockApolloFileManager(strict: true)
  }

  override func tearDown() {
    mockFileManager = nil
    super.tearDown()
  }

  // MARK: Conversion Tests

  func testFormatConversion_givenIntrospectionJSON_shouldOutputValidSDL() async throws {
    let testFilePathBuilder = TestFilePathBuilder(test: self)

    let bundle = Bundle(for: type(of: self))
    guard let jsonURL = bundle.url(
      forResource: "introspection_response",
      withExtension: "json"
    ) else {
      throw XCTFailure("Missing resource file!", file: #file, line: #line)
    }

    let configuration = ApolloSchemaDownloadConfiguration(
      using: .introspection(endpointURL: TestURL.mockPort8080.url),
      outputPath: testFilePathBuilder.schemaOutputURL.path
    )

    try await ApolloSchemaDownloader.convertFromIntrospectionJSONToSDLFile(
      jsonFileURL: jsonURL,
      configuration: configuration,
      withRootURL: nil
    )

    XCTAssertTrue(ApolloFileManager.default.doesFileExist(atPath: configuration.outputPath))

    let frontend = try await GraphQLJSFrontend()
    let source = try await frontend.makeSource(from: URL(fileURLWithPath: configuration.outputPath))
    let schema = try await frontend.loadSchema(from: [source])

    let authorType = try await schema.getType(named: "Author")
    XCTAssertEqual(authorType?.name.schemaName, "Author")

    let postType = try await schema.getType(named: "Post")
    XCTAssertEqual(postType?.name.schemaName, "Post")
  }

  func testFormatConversion_givenIntrospectionJSON_withExperimentalDeferDirective_shouldOutputValidSDL() async throws {
    let testFilePathBuilder = TestFilePathBuilder(test: self)

    let bundle = Bundle(for: type(of: self))
    guard let jsonURL = bundle.url(
      forResource: "introspection_response_with_defer_directive",
      withExtension: "json"
    ) else {
      throw XCTFailure("Missing resource file!", file: #file, line: #line)
    }

    let configuration = ApolloSchemaDownloadConfiguration(
      using: .introspection(endpointURL: TestURL.mockPort8080.url),
      outputPath: testFilePathBuilder.schemaOutputURL.path
    )

    try await ApolloSchemaDownloader.convertFromIntrospectionJSONToSDLFile(
      jsonFileURL: jsonURL,
      configuration: configuration,
      withRootURL: nil
    )

    XCTAssertTrue(ApolloFileManager.default.doesFileExist(atPath: configuration.outputPath))

    let frontend = try await GraphQLJSFrontend()
    let source = try await frontend.makeSource(from: URL(fileURLWithPath: configuration.outputPath))
    let schema = try await frontend.loadSchema(from: [source])

    let bookType = try await schema.getType(named: "Book")
    XCTAssertEqual(bookType?.name.schemaName, "Book")
  }

  // MARK: Request Tests

  func testRequest_givenIntrospectionGETDownload_shouldOutputGETRequest() throws {
    let url = ApolloInternalTestHelpers.TestURL.mockServer.url
    let queryParameterName = "customParam"
    let headers: [ApolloSchemaDownloadConfiguration.HTTPHeader] = [
      .init(key: "key1", value: "value1"),
      .init(key: "key2", value: "value2")
    ]

    let request = try ApolloSchemaDownloader.introspectionRequest(
      from: url,
      httpMethod: .GET(queryParameterName: queryParameterName),
      headers: headers,
      includeDeprecatedInputValues: false
    )

    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertNil(request.httpBody)

    XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
    for header in headers {
      XCTAssertEqual(request.allHTTPHeaderFields?[header.key], header.value)
    }

    var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
    components?.queryItems = [URLQueryItem(name: queryParameterName, value: ApolloSchemaDownloader.introspectionQuery(includeDeprecatedInputValues: false))]

    XCTAssertNotNil(components?.url)
    XCTAssertEqual(request.url, components?.url)
  }
  
  func testRequest_givenIntrospectionGETDownload_andIncludeDeprecatedInputValues_shouldOutputGETRequest() throws {
    let url = ApolloInternalTestHelpers.TestURL.mockServer.url
    let queryParameterName = "customParam"
    let headers: [ApolloSchemaDownloadConfiguration.HTTPHeader] = [
      .init(key: "key1", value: "value1"),
      .init(key: "key2", value: "value2")
    ]

    let request = try ApolloSchemaDownloader.introspectionRequest(
      from: url,
      httpMethod: .GET(queryParameterName: queryParameterName),
      headers: headers,
      includeDeprecatedInputValues: true
    )

    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertNil(request.httpBody)

    XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
    for header in headers {
      XCTAssertEqual(request.allHTTPHeaderFields?[header.key], header.value)
    }

    var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
    components?.queryItems = [URLQueryItem(name: queryParameterName, value: ApolloSchemaDownloader.introspectionQuery(includeDeprecatedInputValues: true))]

    XCTAssertNotNil(components?.url)
    XCTAssertEqual(request.url, components?.url)
  }

  func testRequest_givenIntrospectionPOSTDownload_shouldOutputPOSTRequest() throws {
    let url = ApolloInternalTestHelpers.TestURL.mockServer.url
    let headers: [ApolloSchemaDownloadConfiguration.HTTPHeader] = [
      .init(key: "key1", value: "value1"),
      .init(key: "key2", value: "value2")
    ]

    let request = try ApolloSchemaDownloader.introspectionRequest(
      from: url,
      httpMethod: .POST,
      headers: headers,
      includeDeprecatedInputValues: false
    )

    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url, url)

    XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
    for header in headers {
      XCTAssertEqual(request.allHTTPHeaderFields?[header.key], header.value)
    }

    let requestBody = UntypedGraphQLRequestBodyCreator.requestBody(
      for: ApolloSchemaDownloader.introspectionQuery(includeDeprecatedInputValues: false),
      variables: nil,
      operationName: "IntrospectionQuery"
    )
    let bodyData = try JSONSerialization.data(withJSONObject: requestBody, options: [.sortedKeys])

    XCTAssertEqual(request.httpBody, bodyData)
  }

  func testRequest_givenRegistryDownload_shouldOutputPOSTRequest() throws {
    let apiKey = "custom-api-key"
    let graphID = "graph-id"
    let variant = "a-variant"
    let headers: [ApolloSchemaDownloadConfiguration.HTTPHeader] = [
      .init(key: "key1", value: "value1"),
      .init(key: "key2", value: "value2"),
    ]

    let request = try ApolloSchemaDownloader.registryRequest(
      with: .init(
        apiKey: apiKey,
        graphID: graphID,
        variant: variant
      ),
      headers: headers
    )

    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url, ApolloSchemaDownloader.RegistryEndpoint)

    XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
    XCTAssertEqual(request.allHTTPHeaderFields?["x-api-key"], apiKey)
    for header in headers {
      XCTAssertEqual(request.allHTTPHeaderFields?[header.key], header.value)
    }

    let variables: [String: String] = [
      "graphID": graphID,
      "variant": variant
    ]
    let requestBody = UntypedGraphQLRequestBodyCreator.requestBody(for: ApolloSchemaDownloader.RegistryDownloadQuery,
                                                                   variables: variables,
                                                                   operationName: "DownloadSchema")
    let bodyData = try JSONSerialization.data(withJSONObject: requestBody, options: [.sortedKeys])

    XCTAssertEqual(request.httpBody, bodyData)
  }

  // MARK: Path Tests

  func test__write__givenRelativePath_noRootURL_shouldUseRelativePath() async throws {
    // given
    let path = "./subfolder/output.test"

    mockFileManager.base.changeCurrentDirectoryPath(TestFileHelper.sourceRootURL().path)

    mockFileManager.mock(closure: .fileExists({ path, isDirectory in
      return false
    }))

    mockFileManager.mock(closure: .createDirectory({ path, intermediateDirectories, attributes in
      // no-op
    }))

    mockFileManager.mock(closure: .createFile({ path, data, attributes in
      let expected = TestFileHelper.sourceRootURL()
        .appendingPathComponent("subfolder/output.test").path

      // then
      XCTAssertEqual(path, expected)

      return true
    }))

    // when
    try await ApolloSchemaDownloader.write(
      "Test File",
      path: path,
      rootURL: nil,
      fileManager: mockFileManager)
  }

  func test__write__givenAbsolutePath_noRootURL_shouldUseAbsolutePath() async throws {
    // given
    let path = "/absolute/path/subfolder/output.test"

    mockFileManager.base.changeCurrentDirectoryPath(TestFileHelper.sourceRootURL().path)

    mockFileManager.mock(closure: .fileExists({ path, isDirectory in
      return false
    }))

    mockFileManager.mock(closure: .createDirectory({ path, intermediateDirectories, attributes in
      // no-op
    }))

    mockFileManager.mock(closure: .createFile({ path, data, attributes in
      let expected = "/absolute/path/subfolder/output.test"

      // then
      XCTAssertEqual(path, expected)

      return true
    }))

    // when
    try await ApolloSchemaDownloader.write(
      "Test File",
      path: path,
      rootURL: nil,
      fileManager: mockFileManager)
  }

  func test__write__givenPath_withRootURL_shouldExtendRootURL() async throws {
    // given
    let path = "output.test"

    mockFileManager.base.changeCurrentDirectoryPath(TestFileHelper.sourceRootURL().path)

    mockFileManager.mock(closure: .fileExists({ path, isDirectory in
      return false
    }))

    mockFileManager.mock(closure: .createDirectory({ path, intermediateDirectories, attributes in
      // no-op
    }))

    mockFileManager.mock(closure: .createFile({ path, data, attributes in
      let expected = "/rootURL/path/output.test"

      // then
      XCTAssertEqual(path, expected)

      return true
    }))

    // when
    try await ApolloSchemaDownloader.write(
      "Test File",
      path: path,
      rootURL: URL(fileURLWithPath: "/rootURL/path/"),
      fileManager: mockFileManager)
  }
}
