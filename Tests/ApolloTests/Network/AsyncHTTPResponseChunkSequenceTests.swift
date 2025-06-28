import XCTest
@testable import Apollo
import Nimble
import ApolloInternalTestHelpers

class AsyncHTTPResponseChunkSequenceTests: XCTestCase, MockResponseProvider {

  var session: MockURLSession!
  var sessionConfiguration: URLSessionConfiguration!

  @MainActor
  override func setUp() {
    super.setUp()

    session = MockURLSession(responseProvider: Self.self)
  }

  override func tearDown() async throws {
    await Self.cleanUpRequestHandlers()
    session = nil
    sessionConfiguration = nil

    try await super.tearDown()
  }

  private func request(
    for url: URL,
    responseData: Data?,
    statusCode: Int,
    httpVersion: String? = nil,
    headerFields: [String: String]? = nil
  ) async -> URLRequest {
    let request = URLRequest(
      url: url,
      cachePolicy: .reloadIgnoringCacheData,
      timeoutInterval: 10
    )

    await Self.registerRequestHandler(for: url) { request in
      guard let requestURL = request.url else {
        throw URLError(.badURL)
      }

      let response = HTTPURLResponse(
        url: requestURL,
        statusCode: statusCode,
        httpVersion: httpVersion,
        headerFields: headerFields
      )

      return (response!, responseData)
    }

    return request
  }

  func test__multipartResponse__givenBeginWith_Delimeter_Boundary_shouldParseOut() async throws {
    let url = URL(string: "http://www.test.com/multipart-single-chunk")!
    let boundary = "-"
    let multipartString = "\r\n--\(boundary)\r\nTest"

    let expectedChunks = [
      "Test"
    ]

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let (chunks, _) = try await self.session.chunks(for: request)

    await expect {
      try await chunks.getAllValues().map { String(data:$0 , encoding: .utf8) }
    }.to(equal(expectedChunks))
  }

  func test__multipartResponse__givenBeginWith_CRLF_Delimeter_Boundary_shouldParseOut() async throws {
    let url = URL(string: "http://www.test.com/multipart-single-chunk")!
    let boundary = "-"
    let multipartString = "\r\n\r\n--\(boundary)\r\nTest"

    let expectedChunks = [
      "Test"
    ]

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let (chunks, _) = try await self.session.chunks(for: request)

    await expect {
      try await chunks.getAllValues().map { String(data:$0 , encoding: .utf8) }
    }.to(equal(expectedChunks))
  }

  func test__multipartResponse__givenEndwithCRLF_shouldIncludeCRLF() async throws {
    let url = URL(string: "http://www.test.com/multipart-single-chunk")!
    let boundary = "-"
    let multipartString = "\r\n\r\n--\(boundary)\r\nTest\r\n"

    let expectedChunks = [
      "Test\r\n"
    ]

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let (chunks, _) = try await self.session.chunks(for: request)

    await expect {
      try await chunks.getAllValues().map { String(data:$0 , encoding: .utf8) }
    }.to(equal(expectedChunks))
  }

  func test__multipartResponse__givenEndWithCloseDelimeterAfterBoundary_shouldParseOutDelimeter() async throws {
    let url = URL(string: "http://www.test.com/multipart-single-chunk")!
    let boundary = "-"
    let multipartString = "\r\n--\(boundary)\r\nTest\r\n--\(boundary)--"

    let expectedChunks = [
      "Test"
    ]

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let (chunks, _) = try await self.session.chunks(for: request)

    await expect {
      try await chunks.getAllValues().map { String(data:$0 , encoding: .utf8) }
    }.to(equal(expectedChunks))
  }

  func test__multipartResponse__givenEndWithCRLF_Boundary_CloseDelimeter_shouldParseOutEnd() async throws {
    let url = URL(string: "http://www.test.com/multipart-single-chunk")!
    let boundary = "-"
    let multipartString = "\r\n--\(boundary)\r\nTest\r\n\r\n--\(boundary)--"

    let expectedChunks = [
      "Test\r\n"
    ]

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let (chunks, _) = try await self.session.chunks(for: request)

    await expect {
      try await chunks.getAllValues().map { String(data:$0 , encoding: .utf8) }
    }.to(equal(expectedChunks))
  }

  func test__multipartResponse__givenSingleChunk_shouldReturnSingleChunk() async throws {
    let url = URL(string: "http://www.test.com/multipart-single-chunk")!
    let boundary = "-"
    let multipartString = "\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1\"}}\r\n--\(boundary)--"

    let expectedChunks = [
      "Content-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1\"}}"
    ]

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let (chunks, response) = try await self.session.chunks(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      fail()
      return
    }

    XCTAssertEqual(httpResponse.url, request.url)
    XCTAssertTrue(httpResponse.isSuccessful)
    XCTAssertTrue(httpResponse.isMultipart)

    await expect {
      try await chunks.getAllValues().map { String(data:$0 , encoding: .utf8) }
    }.to(equal(expectedChunks))
  }

  func test__multipart__givenMultipleChunks_recievedAtTheSameTime_shouldReturnAllChunks() async throws {
    let url = URL(string: "http://www.test.com/multipart-many-chunks")!
    let boundary = "-"
    let multipartString = "\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1\"}}\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field2\": \"value2\"}}\r\n--\(boundary)--"

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let expectedChunks = [
      "Content-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1\"}}",
      "Content-Type: application/json\r\n\r\n{\"data\": {\"field2\": \"value2\"}}"
    ]

    let (chunks, response) = try await self.session.chunks(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      fail()
      return
    }

    XCTAssertEqual(httpResponse.url, request.url)
    XCTAssertTrue(httpResponse.isSuccessful)
    XCTAssertTrue(httpResponse.isMultipart)

    await expect {
      try await chunks.getAllValues().map { String(data:$0 , encoding: .utf8) }
    }.to(equal(expectedChunks))
  }

  func test__multipart__givenCompleteAndPartialChunks_shouldReturnCompleteChunkSeparateFromPartialChunk() async throws {
    let url = URL(string: "http://www.test.com/multipart-complete-and-partial-chunk")!
    let boundary = "-"
    let completeChunk = "\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1\"}}"
    let partialChunk = "\r\n--\(boundary)\r\nConte"
    let multipartString = completeChunk + partialChunk

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )


    let expectedChunks = [
      "Content-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1\"}}",
      "Conte"
    ]

    let (chunks, response) = try await self.session.chunks(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      fail()
      return
    }

    XCTAssertEqual(httpResponse.url, request.url)
    XCTAssertTrue(httpResponse.isSuccessful)
    XCTAssertTrue(httpResponse.isMultipart)


    await expect {
      try await chunks.getAllValues().map { String(data:$0 , encoding: .utf8) }
    }.to(equal(expectedChunks))
  }

  func test__multipart__givenChunkContainingBoundaryString_shouldNotSplitChunk() async throws {
    let url = URL(string: "http://www.test.com/multipart-containing-boundary-string")!
    let boundary = "-"
    let multipartString = "\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1--\(boundary)\"}}\r\n--\(boundary)--"

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let expectedChunks = [
      "Content-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1--\(boundary)\"}}"
    ]

    let (chunks, response) = try await self.session.chunks(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      fail()
      return
    }

    XCTAssertEqual(httpResponse.url, request.url)
    XCTAssertTrue(httpResponse.isSuccessful)
    XCTAssertTrue(httpResponse.isMultipart)

    await expect {
      try await chunks.getAllValues().map { String(data:$0 , encoding: .utf8) }
    }.to(equal(expectedChunks))
  }
}
