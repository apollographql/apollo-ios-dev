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

  func test__multipartResponse__givenSingleChunk_shouldReturnSingleChunk() async throws {
    let url = URL(string: "http://www.test.com/multipart-single-chunk")!
    let boundary = "-"
    let multipartString = "--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1\"}}\r\n--\(boundary)--"

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let (dataStream, response) = try await self.session.bytes(for: request, delegate: nil)
    guard let httpResponse = response as? HTTPURLResponse else {
      fail()
      return
    }

    XCTAssertEqual(httpResponse.url, request.url)
    XCTAssertTrue(httpResponse.isSuccessful)
    XCTAssertTrue(httpResponse.isMultipart)

    var chunkCount = 0
    for try await chunk in dataStream.chunks {
      chunkCount += 1
      let chunkString = String(data: chunk, encoding: .utf8)
      switch chunkCount {
      case 1:
        expect(chunkString).to(equal(multipartString))
      case 2:
        // "" is the second result and is expected to be empty
        expect(chunkString).to(equal(""))
      default:
        fail("unexpected chunk received: \(chunkString ?? "")")
      }
    }

    // Results are sent twice for multipart responses with both received here because this test infrastructure uses
    // URLSessionClient directly whereas in a request chain the interceptors may handle data differently.
    //
    // 1. When multipart chunks is received, to be processed immediately
    // 2. When the operation completes, with any remaining task data
    expect(chunkCount).to(equal(2))
  }

  func test__multipart__givenMultipleChunks_recievedAtTheSameTime_shouldReturnAllChunks() async throws {
    let url = URL(string: "http://www.test.com/multipart-many-chunks")!
    let boundary = "-"
    let multipartString = "--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1\"}}\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field2\": \"value2\"}}\r\n--\(boundary)--"

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let (dataStream, response) = try await self.session.bytes(for: request, delegate: nil)
    guard let httpResponse = response as? HTTPURLResponse else {
      fail()
      return
    }

    XCTAssertEqual(httpResponse.url, request.url)
    XCTAssertTrue(httpResponse.isSuccessful)
    XCTAssertTrue(httpResponse.isMultipart)

    var chunkCount = 0
    for try await chunk in dataStream.chunks {
      chunkCount += 1
      let chunkString = String(data: chunk, encoding: .utf8)
      switch chunkCount {
      case 1:
        let expected = "--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1\"}}\r\n"
        expect(chunkString).to(equal(expected))
      case 2:
        let expected = "--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field2\": \"value2\"}}\r\n"
        expect(chunkString).to(equal(expected))
      case 3:
        // "" is the final result and is expected to be empty
        expect(chunkString).to(equal(""))
      default:
        fail("unexpected chunk received: \(chunkString ?? "")")
      }
    }

    // Results are sent twice for multipart responses with both received here because this test infrastructure uses
    // URLSessionClient directly whereas in a request chain the interceptors may handle data differently.
    //
    // 1. When multipart chunks is received, to be processed immediately
    // 2. When the operation completes, with any remaining task data
    expect(chunkCount).to(equal(3))
  }

  func test__multipart__givenCompleteAndPartialChunks_shouldReturnCompleteChunkSeparateFromPartialChunk() async throws {
    let url = URL(string: "http://www.test.com/multipart-complete-and-partial-chunk")!
    let boundary = "-"
    let completeChunk = "--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1\"}}"
    let partialChunk = "\r\n--\(boundary)\r\nConte"
    let multipartString = completeChunk + partialChunk

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let (dataStream, response) = try await self.session.bytes(for: request, delegate: nil)
    guard let httpResponse = response as? HTTPURLResponse else {
      fail()
      return
    }

    XCTAssertEqual(httpResponse.url, request.url)
    XCTAssertTrue(httpResponse.isSuccessful)
    XCTAssertTrue(httpResponse.isMultipart)

    var chunkCount = 0
    for try await chunk in dataStream.chunks {
      chunkCount += 1
      let chunkString = String(data: chunk, encoding: .utf8)
      switch chunkCount {
      case 1:
        expect(chunkString).to(equal(completeChunk))
      case 2:
        expect(chunkString).to(equal(partialChunk))
      default:
        fail("unexpected chunk received: \(chunkString ?? "")")
      }
    }

    // Results are sent twice for multipart responses with both received here because this test infrastructure uses
    // URLSessionClient directly whereas in a request chain the interceptors may handle data differently.
    //
    // 1. When multipart chunks is received, to be processed immediately
    // 2. When the operation completes, with any remaining task data
    expect(chunkCount).to(equal(2))
  }

  func test__multipart__givenChunkContainingBoundaryString_shouldNotSplitChunk() async throws {
    let url = URL(string: "http://www.test.com/multipart-containing-boundary-string")!
    let boundary = "-"
    let multipartString = "--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1--\(boundary)\"}}\r\n--\(boundary)--"

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let (dataStream, response) = try await self.session.bytes(for: request, delegate: nil)
    guard let httpResponse = response as? HTTPURLResponse else {
      fail()
      return
    }

    XCTAssertEqual(httpResponse.url, request.url)
    XCTAssertTrue(httpResponse.isSuccessful)
    XCTAssertTrue(httpResponse.isMultipart)

    var chunkCount = 0
    for try await chunk in dataStream.chunks {
      chunkCount += 1
      let chunkString = String(data: chunk, encoding: .utf8)
      switch chunkCount {
      case 1:
        expect(chunkString).to(equal(multipartString))
      case 2:
        // "" is the second result and is expected to be empty
        expect(chunkString).to(equal(""))
      default:
        fail("unexpected chunk received: \(chunkString ?? "")")
      }
    }

    // Results are sent twice for multipart responses with both received here because this test infrastructure uses
    // URLSessionClient directly whereas in a request chain the interceptors may handle data differently.
    //
    // 1. When multipart chunks is received, to be processed immediately
    // 2. When the operation completes, with any remaining task data
    expect(chunkCount).to(equal(2))
  }

  func test__multipart__givenChunkContainingBoundaryStringWithoutClosingBoundary_shouldNotSplitChunk() async throws {
    let url = URL(string: "http://www.test.com/multipart-without-closing-boundary")!
    let boundary = "-"
    let multipartString = "--\(boundary)\r\nContent-Type: application/json\r\n\r\n{\"data\": {\"field1\": \"value1--\(boundary)\"}}"

    let request = await self.request(
      for: url,
      responseData: multipartString.data(using: .utf8),
      statusCode: 200,
      headerFields: ["Content-Type": "multipart/mixed; boundary=\(boundary)"]
    )

    let (dataStream, response) = try await self.session.bytes(for: request, delegate: nil)
    guard let httpResponse = response as? HTTPURLResponse else {
      fail()
      return
    }

    XCTAssertEqual(httpResponse.url, request.url)
    XCTAssertTrue(httpResponse.isSuccessful)
    XCTAssertTrue(httpResponse.isMultipart)

    var chunkCount = 0
    for try await chunk in dataStream.chunks {
      chunkCount += 1
      let chunkString = String(data: chunk, encoding: .utf8)
      switch chunkCount {
      case 1:
        expect(chunkString).to(equal(multipartString))
      default:
        fail("unexpected chunk received: \(chunkString ?? "")")
      }
    }

    // Results are sent twice for multipart responses with both received here because this test infrastructure uses
    // URLSessionClient directly whereas in a request chain the interceptors may handle data differently.
    //
    // 1. When multipart chunks is received, to be processed immediately
    // 2. When the operation completes, with any remaining task data
    expect(chunkCount).to(equal(1))
  }
}
