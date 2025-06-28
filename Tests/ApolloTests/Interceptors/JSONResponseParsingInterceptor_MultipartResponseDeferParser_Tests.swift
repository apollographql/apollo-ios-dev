@_spi(Internal) import ApolloAPI
import ApolloInternalTestHelpers
import Foundation
import Nimble
import XCTest

@testable import Apollo

final class JSONResponseParsingInterceptor_MultipartResponseDeferParser_Tests: XCTestCase {

  var subject: JSONResponseParsingInterceptor!

  override func setUp() {
    super.setUp()
    subject = JSONResponseParsingInterceptor()
  }

  override func tearDown() {
    super.tearDown()
    subject = nil
  }

  // MARK: - Error tests

  func test__intercept__givenChunk_withIncorrectContentType_shouldThrowError() async throws {
    let operation = MockQuery<MockSelectionSet>()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.mock(
      headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"]
    )
    let chunkStream = streamMocker.getStream()

    var actualResultsIterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
      content-type: test/custom

      {
        "data" : {
          "key" : "value"
        },
        "hasNext": true
      }          
      """.crlfFormattedData()
    )

    await expect {
      try await actualResultsIterator.next()
    }.to(
      throwError(
        MultipartResponseDeferParser.ParsingError.unsupportedContentType(type: "test/custom")
      )
    )
  }

  func test__intercept__givenUnrecognizableChunk_shouldThrowError() async throws {
    let operation = MockQuery<MockSelectionSet>()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.mock(
      headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"]
    )
    let chunkStream = streamMocker.getStream()

    var actualResultsIterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
      content-type: application/json

      not_a_valid_json_object
      """.crlfFormattedData()
    )

    await expect {
      try await actualResultsIterator.next()
    }.to(
      throwError(
        MultipartResponseDeferParser.ParsingError.cannotParseChunkData
      )
    )
  }

  func test__intercept__givenChunk_withMissingPartialOrIncrementalData_shouldThrowError() async throws {
    let operation = MockQuery<MockSelectionSet>()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.mock(
      headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"]
    )
    let chunkStream = streamMocker.getStream()

    var actualResultsIterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
      content-type: application/json

      {
        "key": "value"
      }
      """.crlfFormattedData()
    )

    await expect {
      try await actualResultsIterator.next()
    }.to(
      throwError(
        MultipartResponseDeferParser.ParsingError.cannotParsePayloadData
      )
    )
  }

  // MARK: Parsing tests

  func test__intercept__givenSingleChunk_shouldReturnSuccess() async throws {
    let operation = MockQuery<MockSelectionSet>()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.mock(
      headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"]
    )
    let chunkStream = streamMocker.getStream()

    var actualResultsIterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    let responseChunk = """
      content-type: application/json

      {
        "data" : {
          "key" : "value"
        },
        "hasNext": true
      }
      """.crlfFormattedData()

    streamMocker.emit(responseChunk)

    let result1 = try await actualResultsIterator.next()

    expect(result1?.rawResponseChunk).to(equal(responseChunk))
  }

  func test__intercept__givenSingleChunk_withMultipleContentTypeDirectives_shouldReturnSuccess() async throws {
    let operation = MockQuery<MockSelectionSet>()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.mock(
      headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"]
    )
    let chunkStream = streamMocker.getStream()

    var actualResultsIterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    let responseChunk = """
      Content-Type: application/json; charset=utf-8

      {
        "data" : {
          "key" : "value"
        },
        "hasNext": true
      }
      """.crlfFormattedData()

    streamMocker.emit(responseChunk)

    let result1 = try await actualResultsIterator.next()

    expect(result1?.rawResponseChunk).to(equal(responseChunk))
  }

  func test__intercept__givenSingleChunk_withGraphQLOverHTTPContentType_shouldReturnSuccess() async throws {
    let operation = MockQuery<MockSelectionSet>()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.mock(
      headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"]
    )
    let chunkStream = streamMocker.getStream()

    var actualResultsIterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    let responseChunk = """
      content-type: application/graphql-response+json

      {
        "data" : {
          "key" : "value"
        },
        "hasNext": true
      }          
      """.crlfFormattedData()

    streamMocker.emit(responseChunk)

    let result1 = try await actualResultsIterator.next()

    expect(result1?.rawResponseChunk).to(equal(responseChunk))
  }

}
