@_spi(Execution) @_spi(Unsafe) @_spi(Internal) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable @_spi(Internal) import Apollo

class ClientAwarenessMetadataTests: XCTestCase, MockResponseProvider {

  private static let endpoint = TestURL.mockServer.url

  var mockSession: MockURLSession!
  var store: ApolloStore!

  override func setUp() async throws {
    try await super.setUp()
    self.mockSession = MockURLSession(responseProvider: Self.self)
    self.store = ApolloStore(cache: NoCache())
  }

  override func tearDown() async throws {
    await Self.cleanUpRequestHandlers()
    self.mockSession = nil
    self.store = nil
    try await super.tearDown()
  }

  // MARK: - Helpers

  private static func mockResponseData() -> Data {
    """
    {
      "data": {
        "__typename": "Query"
      }
    }
    """.data(using: .utf8)!
  }

  private func makeTransport(
    apqConfig: AutoPersistedQueryConfiguration = .init()
  ) -> RequestChainNetworkTransport {
    RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint,
      apqConfig: apqConfig
    )
  }

  private func makeClient(
    metadata: ClientAwarenessMetadata = ClientAwarenessMetadata(),
    apqConfig: AutoPersistedQueryConfiguration = .init()
  ) -> ApolloClient {
    ApolloClient(
      networkTransport: makeTransport(apqConfig: apqConfig),
      store: store,
      clientAwarenessMetadata: metadata
    )
  }

  /// Registers a mock handler that captures the URLRequest, then performs a fetch.
  /// Returns the captured URLRequest for inspection.
  private func captureRequest(
    client: ApolloClient
  ) async throws -> URLRequest {
    nonisolated(unsafe) var capturedRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) { request in
      capturedRequest = request
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await client.fetch(
      query: MockQuery<MockSelectionSet>(),
      cachePolicy: .networkOnly
    )

    return try XCTUnwrap(capturedRequest)
  }

  /// Extracts the JSON body from a captured URLRequest, handling both
  /// httpBody and httpBodyStream (used by upload requests).
  private func jsonBody(from request: URLRequest) throws -> JSONObject {
    let httpBody: Data
    if let bodyStream = request.httpBodyStream {
      httpBody = try Data(reading: bodyStream)
    } else {
      httpBody = try XCTUnwrap(request.httpBody)
    }
    return try JSONSerializationFormat.deserialize(data: httpBody) as JSONObject
  }

  /// Extracts the "operations" JSON object from a multipart upload request body.
  /// Multipart bodies contain a part named "operations" with the GraphQL JSON payload.
  private func operationsJSON(from request: URLRequest) throws -> JSONObject {
    let bodyData: Data
    if let bodyStream = request.httpBodyStream {
      bodyData = try Data(reading: bodyStream)
    } else {
      bodyData = try XCTUnwrap(request.httpBody)
    }
    let bodyString = try XCTUnwrap(String(data: bodyData, encoding: .utf8))

    // Extract the operations part from multipart body.
    // Format: Content-Disposition: form-data; name="operations"\r\n\r\n{...JSON...}\r\n--boundary
    let parts = bodyString.components(separatedBy: "Content-Disposition: form-data; name=\"operations\"")
    let operationsPart = try XCTUnwrap(parts.last, "Could not find operations part in multipart body")

    // The JSON starts after the blank line following the Content-Disposition header
    let lines = operationsPart.components(separatedBy: "\n")
    // Find the first non-empty line after the header separator (blank line)
    var foundBlankLine = false
    var jsonString: String?
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        foundBlankLine = true
        continue
      }
      if foundBlankLine {
        jsonString = trimmed
        break
      }
    }

    let json = try XCTUnwrap(jsonString, "Could not find JSON in operations part")
    let data = try XCTUnwrap(json.data(using: .utf8))
    return try JSONSerializationFormat.deserialize(data: data) as JSONObject
  }

  // MARK: - JSON Request Tests

  func test__fetch__usingDefaultMetadata__shouldAddClientLibraryExtensionToBody__shouldNotIncludeClientApplicationHeaders()
    async throws
  {
    let client = makeClient()
    let request = try await captureRequest(client: client)

    expect(request.value(forHTTPHeaderField: "apollographql-client-name")).to(beNil())
    expect(request.value(forHTTPHeaderField: "apollographql-client-version")).to(beNil())

    let body = try jsonBody(from: request)
    let extensions = try XCTUnwrap(body["extensions"] as? JSONObject)
    let clientLibrary = try XCTUnwrap(extensions["clientLibrary"] as? JSONObject)
    expect(clientLibrary["name"] as? String).to(equal(Constants.ApolloClientName))
    expect(clientLibrary["version"] as? String).to(equal(Constants.ApolloClientVersion))
  }

  func test__fetch__givenIncludeApolloSDKAwarenessTrue__shouldAddClientLibraryExtensionToBody()
    async throws
  {
    let client = makeClient(
      metadata: ClientAwarenessMetadata(includeApolloLibraryAwareness: true)
    )
    let request = try await captureRequest(client: client)

    expect(request.value(forHTTPHeaderField: "apollographql-client-name")).to(beNil())
    expect(request.value(forHTTPHeaderField: "apollographql-client-version")).to(beNil())

    let body = try jsonBody(from: request)
    let extensions = try XCTUnwrap(body["extensions"] as? JSONObject)
    let clientLibrary = try XCTUnwrap(extensions["clientLibrary"] as? JSONObject)
    expect(clientLibrary["name"] as? String).to(equal(Constants.ApolloClientName))
    expect(clientLibrary["version"] as? String).to(equal(Constants.ApolloClientVersion))
  }

  func test__fetch__givenApplicationNameAndVersion__shouldAddClientApplicationHeaders__shouldNotAddClientLibraryExtension()
    async throws
  {
    let client = makeClient(
      metadata: ClientAwarenessMetadata(
        clientApplicationName: "test-client",
        clientApplicationVersion: "test-client-version",
        includeApolloLibraryAwareness: false
      )
    )
    let request = try await captureRequest(client: client)

    expect(request.value(forHTTPHeaderField: "apollographql-client-name"))
      .to(equal("test-client"))
    expect(request.value(forHTTPHeaderField: "apollographql-client-version"))
      .to(equal("test-client-version"))

    let body = try jsonBody(from: request)
    expect(body["extensions"] as? JSONObject).to(beNil())
  }

  func test__fetch__givenApplicationNameAndVersionWithLibraryAwareness__shouldAddBothHeadersAndExtension()
    async throws
  {
    let client = makeClient(
      metadata: ClientAwarenessMetadata(
        clientApplicationName: "test-client",
        clientApplicationVersion: "1.0.0",
        includeApolloLibraryAwareness: true
      )
    )
    let request = try await captureRequest(client: client)

    expect(request.value(forHTTPHeaderField: "apollographql-client-name"))
      .to(equal("test-client"))
    expect(request.value(forHTTPHeaderField: "apollographql-client-version"))
      .to(equal("1.0.0"))

    let body = try jsonBody(from: request)
    let extensions = try XCTUnwrap(body["extensions"] as? JSONObject)
    let clientLibrary = try XCTUnwrap(extensions["clientLibrary"] as? JSONObject)
    expect(clientLibrary["name"] as? String).to(equal(Constants.ApolloClientName))
    expect(clientLibrary["version"] as? String).to(equal(Constants.ApolloClientVersion))
  }

  func test__fetch__givenMetadataNone__shouldNotAddHeadersOrExtension()
    async throws
  {
    let client = makeClient(metadata: .none)
    let request = try await captureRequest(client: client)

    expect(request.value(forHTTPHeaderField: "apollographql-client-name")).to(beNil())
    expect(request.value(forHTTPHeaderField: "apollographql-client-version")).to(beNil())

    let body = try jsonBody(from: request)
    expect(body["extensions"] as? JSONObject).to(beNil())
  }

  // MARK: - APQ + Library Awareness Coexistence Test

  func test__fetch__givenAPQEnabledWithLibraryAwareness__extensionsShouldContainBothPersistedQueryAndClientLibrary()
    async throws
  {
    let client = makeClient(
      metadata: ClientAwarenessMetadata(includeApolloLibraryAwareness: true),
      apqConfig: .init(autoPersistQueries: true)
    )

    nonisolated(unsafe) var capturedRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) { request in
      capturedRequest = request
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    _ = try await client.fetch(
      query: APQMockQuery(),
      cachePolicy: .networkOnly
    )

    let request = try XCTUnwrap(capturedRequest)
    let body = try jsonBody(from: request)
    let extensions = try XCTUnwrap(body["extensions"] as? JSONObject)

    // persistedQuery should be present from APQ
    let persistedQuery = try XCTUnwrap(extensions["persistedQuery"] as? JSONObject)
    expect(persistedQuery["version"] as? Int).to(equal(1))
    expect(persistedQuery["sha256Hash"]).toNot(beNil())

    // clientLibrary should also be present from library awareness
    let clientLibrary = try XCTUnwrap(extensions["clientLibrary"] as? JSONObject)
    expect(clientLibrary["name"] as? String).to(equal(Constants.ApolloClientName))
    expect(clientLibrary["version"] as? String).to(equal(Constants.ApolloClientVersion))
  }

  // MARK: - Upload Request Tests

  func test__upload__usingDefaultMetadata__shouldAddClientLibraryExtensionToBody__shouldNotIncludeClientApplicationHeaders()
    async throws
  {
    let client = makeClient()

    nonisolated(unsafe) var capturedRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) { request in
      capturedRequest = request
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    let file = GraphQLFile(
      fieldName: "file",
      originalName: "test.txt",
      data: "test content".data(using: .utf8)!
    )

    _ = try await client.upload(
      operation: MockMutation<MockSelectionSet>(),
      files: [file]
    )

    let request = try XCTUnwrap(capturedRequest)

    expect(request.value(forHTTPHeaderField: "apollographql-client-name")).to(beNil())
    expect(request.value(forHTTPHeaderField: "apollographql-client-version")).to(beNil())

    let operations = try operationsJSON(from: request)
    let extensions = try XCTUnwrap(operations["extensions"] as? JSONObject)
    let clientLibrary = try XCTUnwrap(extensions["clientLibrary"] as? JSONObject)
    expect(clientLibrary["name"] as? String).to(equal(Constants.ApolloClientName))
    expect(clientLibrary["version"] as? String).to(equal(Constants.ApolloClientVersion))
  }

  func test__upload__givenApplicationNameAndVersion__shouldAddClientApplicationHeaders__shouldNotAddClientLibraryExtension()
    async throws
  {
    let client = makeClient(
      metadata: ClientAwarenessMetadata(
        clientApplicationName: "test-client",
        clientApplicationVersion: "test-client-version",
        includeApolloLibraryAwareness: false
      )
    )

    nonisolated(unsafe) var capturedRequest: URLRequest?

    await Self.registerRequestHandler(for: Self.endpoint) { request in
      capturedRequest = request
      return (HTTPURLResponse.mock(), Self.mockResponseData())
    }

    let file = GraphQLFile(
      fieldName: "file",
      originalName: "test.txt",
      data: "test content".data(using: .utf8)!
    )

    _ = try await client.upload(
      operation: MockMutation<MockSelectionSet>(),
      files: [file]
    )

    let request = try XCTUnwrap(capturedRequest)

    expect(request.value(forHTTPHeaderField: "apollographql-client-name"))
      .to(equal("test-client"))
    expect(request.value(forHTTPHeaderField: "apollographql-client-version"))
      .to(equal("test-client-version"))

    let operations = try operationsJSON(from: request)
    expect(operations["extensions"] as? JSONObject).to(beNil())
  }

  // MARK: - Static Property Tests

  func test__defaultClientName__shouldContainApolloSuffix() {
    let name = ClientAwarenessMetadata.defaultClientName
    // In a test host with a bundle identifier, the name is "<bundleID>-apollo-ios".
    // Without a bundle identifier, the fallback is "apollo-ios-client".
    // Both cases end with "apollo-ios" somewhere in the string.
    expect(name).to(contain("apollo-ios"))
    expect(name).toNot(beEmpty())
  }

  func test__defaultClientVersion__shouldReturnNonEmptyString() {
    let version = ClientAwarenessMetadata.defaultClientVersion
    expect(version).toNot(beEmpty())
  }

  func test__enabledWithDefaults__shouldSetAllProperties() {
    let metadata = ClientAwarenessMetadata.enabledWithDefaults
    expect(metadata.clientApplicationName).to(equal(ClientAwarenessMetadata.defaultClientName))
    expect(metadata.clientApplicationVersion).to(equal(ClientAwarenessMetadata.defaultClientVersion))
    expect(metadata.includeApolloLibraryAwareness).to(beTrue())
  }

  func test__none__shouldDisableAllProperties() {
    let metadata = ClientAwarenessMetadata.none
    expect(metadata.clientApplicationName).to(beNil())
    expect(metadata.clientApplicationVersion).to(beNil())
    expect(metadata.includeApolloLibraryAwareness).to(beFalse())
  }

  // MARK: - Mock Helpers

  /// A mock query with an operationIdentifier for APQ testing.
  private final class APQMockQuery: MockQuery<MockSelectionSet>, @unchecked Sendable {
    override class var operationDocument: OperationDocument {
      .init(
        operationIdentifier: "abc123def456",
        definition: .init("APQMockQuery - Operation Definition")
      )
    }
  }
}
