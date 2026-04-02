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

  private func makeTransport() -> RequestChainNetworkTransport {
    RequestChainNetworkTransport(
      urlSession: mockSession,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: Self.endpoint
    )
  }

  private func makeClient(
    metadata: ClientAwarenessMetadata = ClientAwarenessMetadata()
  ) -> ApolloClient {
    ApolloClient(
      networkTransport: makeTransport(),
      store: store,
      clientAwarenessMetadata: metadata
    )
  }

  /// Registers a mock handler that captures the URLRequest, then performs the given fetch.
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
    let httpBody: Data?
    if let bodyStream = request.httpBodyStream {
      httpBody = try Data(reading: bodyStream)
    } else {
      httpBody = request.httpBody
    }
    let body = try XCTUnwrap(httpBody)
    return try JSONSerializationFormat.deserialize(data: body) as JSONObject
  }

  // MARK: - JSON Request Tests

  func test__fetch__usingDefaultMetadata__shouldAddClientLibraryExtensionToBody__shouldNotIncludeClientApplicationHeaders()
    async throws
  {
    // Default ClientAwarenessMetadata has includeApolloLibraryAwareness: true,
    // clientApplicationName: nil, clientApplicationVersion: nil
    let client = makeClient()
    let request = try await captureRequest(client: client)

    // No application headers should be set
    expect(request.value(forHTTPHeaderField: "apollographql-client-name")).to(beNil())
    expect(request.value(forHTTPHeaderField: "apollographql-client-version")).to(beNil())

    // Body should contain clientLibrary extension
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

    // No application headers
    expect(request.value(forHTTPHeaderField: "apollographql-client-name")).to(beNil())
    expect(request.value(forHTTPHeaderField: "apollographql-client-version")).to(beNil())

    // Body should contain clientLibrary extension
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

    // Application headers should be set
    expect(request.value(forHTTPHeaderField: "apollographql-client-name"))
      .to(equal("test-client"))
    expect(request.value(forHTTPHeaderField: "apollographql-client-version"))
      .to(equal("test-client-version"))

    // Body should NOT contain clientLibrary extension
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

    // Application headers should be set
    expect(request.value(forHTTPHeaderField: "apollographql-client-name"))
      .to(equal("test-client"))
    expect(request.value(forHTTPHeaderField: "apollographql-client-version"))
      .to(equal("1.0.0"))

    // Body should also contain clientLibrary extension
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

    // No application headers
    expect(request.value(forHTTPHeaderField: "apollographql-client-name")).to(beNil())
    expect(request.value(forHTTPHeaderField: "apollographql-client-version")).to(beNil())

    // No clientLibrary extension in body
    let body = try jsonBody(from: request)
    expect(body["extensions"] as? JSONObject).to(beNil())
  }

  // MARK: - Upload Request Tests

  func test__upload__usingDefaultMetadata__shouldAddClientLibraryExtensionToBody__shouldNotIncludeClientApplicationHeaders()
    async throws
  {
    let transport = makeTransport()
    let client = ApolloClient(
      networkTransport: transport,
      store: store
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

    // No application headers
    expect(request.value(forHTTPHeaderField: "apollographql-client-name")).to(beNil())
    expect(request.value(forHTTPHeaderField: "apollographql-client-version")).to(beNil())

    // Multipart body should contain clientLibrary extension in the operations part
    let bodyData: Data
    if let bodyStream = request.httpBodyStream {
      bodyData = try Data(reading: bodyStream)
    } else {
      bodyData = try XCTUnwrap(request.httpBody)
    }
    let bodyString = try XCTUnwrap(String(data: bodyData, encoding: .utf8))

    expect(bodyString).to(contain("\"clientLibrary\""))
    expect(bodyString).to(contain(Constants.ApolloClientName))
    expect(bodyString).to(contain(Constants.ApolloClientVersion))
  }

  func test__upload__givenApplicationNameAndVersion__shouldAddClientApplicationHeaders__shouldNotAddClientLibraryExtension()
    async throws
  {
    let transport = makeTransport()
    let client = ApolloClient(
      networkTransport: transport,
      store: store,
      clientAwarenessMetadata: ClientAwarenessMetadata(
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

    // Application headers should be set
    expect(request.value(forHTTPHeaderField: "apollographql-client-name"))
      .to(equal("test-client"))
    expect(request.value(forHTTPHeaderField: "apollographql-client-version"))
      .to(equal("test-client-version"))

    // Multipart body should NOT contain clientLibrary extension
    let bodyData: Data
    if let bodyStream = request.httpBodyStream {
      bodyData = try Data(reading: bodyStream)
    } else {
      bodyData = try XCTUnwrap(request.httpBody)
    }
    let bodyString = try XCTUnwrap(String(data: bodyData, encoding: .utf8))

    expect(bodyString).notTo(contain("\"clientLibrary\""))
  }
}

// MARK: - Data InputStream Helper

private extension Data {
  init(reading input: InputStream) throws {
    self.init()
    input.open()
    defer { input.close() }

    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while input.hasBytesAvailable {
      let read = input.read(buffer, maxLength: bufferSize)
      if read < 0 {
        throw input.streamError!
      } else if read == 0 {
        break
      }
      self.append(buffer, count: read)
    }
  }
}
