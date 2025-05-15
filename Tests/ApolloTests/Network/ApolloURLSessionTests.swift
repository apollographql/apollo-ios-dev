import XCTest
@testable import Apollo
import Nimble
import ApolloInternalTestHelpers

class ApolloURLSessionTests: XCTestCase, MockResponseProvider {

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
  
  func test__request__basicGet() async throws {
    let url = URL(string: "http://www.test.com/basicget")!
    let stringResponse = "Basic GET Response Data"
    let request = await self.request(
      for: url,
      responseData: stringResponse.data(using: .utf8),
      statusCode: 200
    )

    let (dataStream, response) = try await self.session.bytes(for: request, delegate: nil)

    XCTAssertEqual(request.url, response.url)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

    var chunkCount = 0
    for try await chunk in dataStream.chunks {
      chunkCount += 1
      expect(chunk).toNot(beEmpty())
      expect(String(data: chunk, encoding: .utf8)).to(equal(stringResponse))
    }

    expect(chunkCount).to(equal(1))
  }
  
  func test__request__gettingImage() async throws {
    let url = URL(string: "http://www.test.com/gettingImage")!
    #if os(macOS)
    let responseImg = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
    let responseData = responseImg?.tiffRepresentation
    #else
    guard let responseImg = UIImage(systemName: "pencil") else {
      XCTFail("Failed to create UIImage from system name.")
      return
    }
    let responseData = responseImg.pngData()
    #endif
    let headerFields = ["Content-Type": "image/jpeg"]
    let request = await self.request(
      for: url,
      responseData: responseData,
      statusCode: 200,
      headerFields: headerFields
    )

    let (dataStream, response) = try await self.session.bytes(for: request, delegate: nil)
    guard let httpResponse = response as? HTTPURLResponse else {
      fail()
      return
    }

    XCTAssertEqual(httpResponse.allHeaderFields["Content-Type"] as! String, "image/jpeg")
    XCTAssertEqual(request.url, httpResponse.url)

    var chunkCount = 0
    for try await chunk in dataStream.chunks {
      chunkCount += 1
      expect(chunk).toNot(beEmpty())

      #if os(macOS)
      let image = NSImage(data: chunk)
      XCTAssertNotNil(image)
      #else
      let image = UIImage(data: chunk)
      XCTAssertNotNil(image)
      #endif
    }

    expect(chunkCount).to(equal(1))
  }
  
  func test__request__postingJSON() async throws {
    let testJSON = ["key": "value"]
    let data = try JSONSerialization.data(withJSONObject: testJSON, options: .prettyPrinted)
    let url = URL(string: "http://www.test.com/postingJSON")!
    let headerFields = ["Content-Type": "application/json"]

    var request = await self.request(
      for: url,
      responseData: data,
      statusCode: 200,
      headerFields: headerFields
    )
    request.httpBody = data
    request.httpMethod = GraphQLHTTPMethod.POST.rawValue

    let (dataStream, response) = try await self.session.bytes(for: request, delegate: nil)
    guard let httpResponse = response as? HTTPURLResponse else {
      fail()
      return
    }

    XCTAssertEqual(request.url, httpResponse.url)

    var chunkCount = 0
    for try await chunk in dataStream.chunks {
      chunkCount += 1
      let parsedJSON = try JSONSerialization.jsonObject(with: chunk) as! [String : String]
      XCTAssertEqual(parsedJSON, testJSON)
    }

    expect(chunkCount).to(equal(1))
  }
  
  func test__request__cancellingTaskDirectly_shouldThrowCancellationError() async throws {
    let url = URL(string: "http://www.test.com/cancelTaskDirectly")!
    let request = await request(
      for: url,
      responseData: nil,
      statusCode: -1
    )

    let task = Task {
      await expect {
        try await self.session.bytes(for: request, delegate: nil)
      }.to(throwError(CancellationError()))
    }

    task.cancel()

    let expectation = await task.value
    expect(expectation.status).to(equal(.passed))
  }

  func test__request__multipleSimultaneousRequests() async throws {
    let expectation = self.expectation(description: "request sent, response received")
    let iterations = 20
    expectation.expectedFulfillmentCount = iterations
    @Atomic var taskIDs: [Int] = []
    
    var responseStrings = [Int: String]()
    var requests = [Int: URLRequest]()

    for i in 0..<iterations {
      let url = URL(string: "http://www.test.com/multipleSimultaneousRequests\(i)")!
      let responseStr = "Simultaneous Request \(i)"
      let request = await self.request(
        for: url,
        responseData: responseStr.data(using: .utf8),
        statusCode: 200
      )

      responseStrings[i] = responseStr
      requests[i] = request
    }

    await withThrowingTaskGroup(of: Void.self) { group in
      for (index, request) in requests {
        group.addTask {
          let (dataStream, response) = try await self.session.bytes(for: request, delegate: nil)
          guard let httpResponse = response as? HTTPURLResponse else {
            fail()
            return
          }

          XCTAssertEqual(httpResponse.url, request.url)
          var isFirstChunk: Bool = true
          for try await chunk in dataStream.chunks {
            XCTAssertTrue(isFirstChunk)
            isFirstChunk = false

            let expectedResponse = responseStrings[index]
            XCTAssertFalse(chunk.isEmpty)
            let actualResponse = String(data: chunk, encoding: .utf8)
            XCTAssertEqual(expectedResponse, actualResponse)
          }
        }
      }
    }
  }

  func test__request__sendingRequestToInvalidatedSession_returnsAppropriateError() async {
    session.invalidateAndCancel()

    let url = URL(string: "http://www.test.com/invalidatedRequestTest")!
    let request = await request(
      for: url,
      responseData: nil,
      statusCode: 400
    )

    _ = await Task {
      await expect {
        try await self.session.bytes(for: request, delegate: nil)
      }.to(throwError(CancellationError()))
    }.value
  }

}
