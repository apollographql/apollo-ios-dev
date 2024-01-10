import XCTest
import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

final class MultipartResponseDeferParserTests: XCTestCase {

  let defaultTimeout = 0.5

  // MARK: - Error tests

  func test__error__givenChunk_withIncorrectContentType_shouldReturnError() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"],
        data: """
          --graphql
          content-type: test/custom

          {
            "data" : {
              "key" : "value"
            }
          }
          --graphql
          """.crlfFormattedData()
      )
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beFailure { error in
        expect(error).to(
          matchError(MultipartResponseDeferParser.ParsingError.unsupportedContentType(type: "test/custom"))
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__error__givenUnrecognizableChunk_shouldReturnError() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"],
        data: """
          --graphql
          content-type: application/json

          not_a_valid_json_object
          --graphql
          """.crlfFormattedData()
      )
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beFailure { error in
        expect(error).to(
          matchError(MultipartResponseDeferParser.ParsingError.cannotParseChunkData)
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  // MARK: Parsing tests

  #warning("Need parsing tests - to be done after #3147")
}
