import XCTest
import ApolloAPI
import ApolloInternalTestHelpers
import GitHubAPI

@testable @_spi(Execution) import Apollo

class ParsingPerformanceTests: XCTestCase {

  func testParseSingleResponse() throws {
    let body = try loadResponseBody(
      for: IssuesAndCommentsForRepositoryQuery.self
    )

    let parser = JSONResponseParser(
      response: .mock(),
      operationVariables: nil,
      includeCacheRecords: false
    )

    measure {
      whileRecordingErrors {
        let result: ParsedResult<IssuesAndCommentsForRepositoryQuery> =
          try awaitResult { try await parser.parseSingleResponse(body: body) }

        let data = try XCTUnwrap(result.result.data)
        XCTAssertEqual(data.repository?.name, "apollo-ios")
      }
    }
  }

  func testParseSingleResponseWithCacheRecords() throws {
    let body = try loadResponseBody(
      for: IssuesAndCommentsForRepositoryQuery.self
    )

    let parser = JSONResponseParser(
      response: .mock(),
      operationVariables: nil,
      includeCacheRecords: true
    )

    measure {
      whileRecordingErrors {
        let result: ParsedResult<IssuesAndCommentsForRepositoryQuery> =
          try awaitResult { try await parser.parseSingleResponse(body: body) }

        let data = try XCTUnwrap(result.result.data)
        XCTAssertEqual(data.repository?.name, "apollo-ios")
        XCTAssertNotNil(result.cacheRecords)
      }
    }
  }

  func testMultipartSubscriptionChunkParsing() throws {
    let chunk = """
      content-type: application/json

      {"payload":{"data":{"ticker":1}}}
      """.crlfFormattedData()

    measure {
      whileRecordingErrors {
        for _ in 0..<1000 {
          let result = try MultipartResponseSubscriptionParser.parse(
            multipartChunk: chunk
          )
          XCTAssertNotNil(result)
        }
      }
    }
  }

  // MARK: - Helpers

  private func awaitResult<T: Sendable>(
    _ work: @escaping @Sendable () async throws -> T
  ) throws -> T {
    let expectation = expectation(description: "Async work")
    nonisolated(unsafe) var result: Result<T, any Error>!
    let fulfill: @Sendable () -> Void = { [expectation] in expectation.fulfill() }
    Task {
      do {
        let value = try await work()
        result = .success(value)
      } catch {
        result = .failure(error)
      }
      fulfill()
    }
    wait(for: [expectation], timeout: 30.0)
    return try result.get()
  }

  private func loadResponseBody<Query: GraphQLQuery>(
    for queryType: Query.Type,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> JSONObject {
    let bundle = Bundle(for: type(of: self))

    guard let url = bundle.url(
      forResource: Query.operationName,
      withExtension: "json"
    ) else {
      throw XCTFailure(
        "Missing response file for query: \(Query.operationName)",
        file: file,
        line: line
      )
    }

    let data = try Data(contentsOf: url)
    let body = try JSONSerialization.jsonObject(with: data, options: []) as! JSONObject
    return body
  }
}
