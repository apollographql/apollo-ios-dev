import XCTest
import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

final class MultipartResponseSubscriptionParserTests: XCTestCase {

  let defaultTimeout = 0.5

  // MARK: - Error tests

  func test__error__givenChunk_withIncorrectContentType_shouldReturnError() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockSubscription.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"],
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
          matchError(MultipartResponseSubscriptionParser.ParsingError.unsupportedContentType(type: "test/custom"))
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__error__givenChunk_withTransportError_shouldReturnError() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockSubscription.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"],
        data: """
          --graphql
          content-type: application/json

          {
            "errors" : [
              {
                "message" : "forced test failure!"
              }
            ]
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
          matchError(MultipartResponseSubscriptionParser.ParsingError.irrecoverableError(message: "forced test failure!"))
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__error__givenUnrecognizableChunk_shouldReturnError() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockSubscription.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"],
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
          matchError(MultipartResponseSubscriptionParser.ParsingError.cannotParseChunkData)
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__error__givenChunk_withMissingPayload_shouldReturnError() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockSubscription.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"],
        data: """
          --graphql
          content-type: application/json

          {
            "key": "value"
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
          matchError(MultipartResponseSubscriptionParser.ParsingError.cannotParsePayloadData)
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  // MARK: Parsing tests

  func test__parsing__givenSingleChunk_shouldReturnSuccess() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    let expected: JSONObject = [
      "data": [
        "__typename": "Time",
        "ticker": 1
      ]
    ]

    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"],
        data: """
          --graphql
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 1
              }
            }
          }
          --graphql
          """.crlfFormattedData()
      )
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beSuccess())

      guard
        let data = try! result.get(),
        let deserialized = try! JSONSerialization.jsonObject(with: data) as? JSONObject
      else {
        return fail("data could not be deserialized!")
      }

      expect(deserialized).to(equal(expected))
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenMultipleChunks_shouldReturnMultipleSuccess() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")
    expectation.expectedFulfillmentCount = 2

    var expected: [JSONObject] = [
      [
        "data": [
          "__typename": "Time",
          "ticker": 2
        ]
      ],
      [
        "data": [
          "__typename": "Time",
          "ticker": 3
        ]
      ]
    ]

    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"],
        data: """
          --graphql
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 2
              }
            }
          }
          --graphql
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 3
              }
            }
          }
          --graphql
          """.crlfFormattedData()
      )
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beSuccess())

      guard
        let data = try! result.get(),
        let deserialized = try! JSONSerialization.jsonObject(with: data) as? JSONObject
      else {
        return fail("data could not be deserialized!")
      }

      expect(expected).to(contain(deserialized))
      expected.removeAll(where: { $0 == deserialized })
    }

    wait(for: [expectation], timeout: defaultTimeout)
    expect(expected).to(beEmpty())
  }
}
