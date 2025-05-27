import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

final class JSONResponseParsingInterceptor_MultipartResponseSubscriptionParser_Tests: XCTestCase {

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

  func test__error__givenIncorrectContentType_shouldReturnError() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<MockSelectionSet>>()

    var actualResultsIterator = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription.mock())
    ) { _ in
      streamMocker.getStream()
    }.getResults().makeAsyncIterator()

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: test/custom

          {
            "data" : {
              "key" : "value"
            }
          }          
          """.crlfFormattedData()
      )
    )

    await expect {
      try await actualResultsIterator.next()
    }.to(
      throwError(
        MultipartResponseSubscriptionParser.ParsingError.unsupportedContentType(type: "test/custom")
      )
    )
  }

  func test__error__givenTransportError_shouldReturnError() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<MockSelectionSet>>()

    var actualResultsIterator = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription.mock())
    ) { _ in
      streamMocker.getStream()
    }.getResults().makeAsyncIterator()

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/json

          {
            "errors" : [
              {
                "message" : "forced test failure!"
              }
            ]
          }          
          """.crlfFormattedData()
      )
    )

    await expect {
      try await actualResultsIterator.next()
    }.to(
      throwError(
        MultipartResponseSubscriptionParser.ParsingError.irrecoverableError(message: "forced test failure!")
      )
    )
  }

  func test__error__givenTransportErrorWithNullPayload_shouldReturnError() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<MockSelectionSet>>()

    var actualResultsIterator = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription.mock())
    ) { _ in
      streamMocker.getStream()
    }.getResults().makeAsyncIterator()

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/json

          {
            "payload": null,
            "errors" : [
              {
                "message" : "forced test failure!"
              }
            ]
          }
          """.crlfFormattedData()
      )
    )

    await expect {
      try await actualResultsIterator.next()
    }.to(
      throwError(
        MultipartResponseSubscriptionParser.ParsingError.irrecoverableError(message: "forced test failure!")
      )
    )
  }

  func test__error__givenTransportErrorWithValidPayload_errorShouldTakePrecendenceAndReturnError() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<MockSelectionSet>>()

    var actualResultsIterator = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription.mock())
    ) { _ in
      streamMocker.getStream()
    }.getResults().makeAsyncIterator()

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 1
              }
            },
            "errors" : [
              {
                "message" : "forced test failure!"
              }
            ]
          }
          """.crlfFormattedData()
      )
    )

    await expect {
      try await actualResultsIterator.next()
    }.to(
      throwError(
        MultipartResponseSubscriptionParser.ParsingError.irrecoverableError(message: "forced test failure!")
      )
    )
  }

  func test__error__givenTransportErrorIncludingUnknownKeys_shouldReturnErrorWithMessageOnly() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<MockSelectionSet>>()

    var actualResultsIterator = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription.mock())
    ) { _ in
      streamMocker.getStream()
    }.getResults().makeAsyncIterator()

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/json

          {
            "errors" : [
              {
                "message" : "forced test failure!",
                "path": [
                  "hello"
                ],
                "foo": "bar"
              }
            ]
          }
          """.crlfFormattedData()
      )
    )

    await expect {
      try await actualResultsIterator.next()
    }.to(
      throwError(
        MultipartResponseSubscriptionParser.ParsingError.irrecoverableError(message: "forced test failure!")
      )
    )
  }

  func test__error__givenMalformedJSON_shouldReturnError() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<MockSelectionSet>>()

    var actualResultsIterator = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription.mock())
    ) { _ in
      streamMocker.getStream()
    }.getResults().makeAsyncIterator()

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/json

          not_a_valid_json_object
          """.crlfFormattedData()
      )
    )

    await expect {
      try await actualResultsIterator.next()
    }.to(
      throwError(
        MultipartResponseSubscriptionParser.ParsingError.cannotParseChunkData
      )
    )
  }

  // MARK: Parsing tests

  private class Time: MockSelectionSet, @unchecked Sendable {
    typealias Schema = MockSchemaMetadata

    override class var __selections: [Selection] {
      [
        .field("__typename", String.self),
        .field("ticker", Int.self),
      ]
    }

    var ticker: Int { __data["ticker"] }
  }

  func test__parsing__givenHeartbeat_shouldIgnore() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }

    let response: HTTPURLResponse = .mock(
      headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
    )

    streamMocker.emit(
      response: .mock(
        response: response,
        dataChunk: """
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 1
              }
            }
          }                    
          """.crlfFormattedData()
      )
    )

    streamMocker.emit(
      response: .mock(
        response: response,
        dataChunk: """
          content-type: application/json

          {}         
          """.crlfFormattedData()
      )
    )

    streamMocker.emit(
      response: .mock(
        response: response,
        dataChunk: """
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 2
              }
            }
          }          
          """.crlfFormattedData()
      )
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(2))
    expect(results[0].parsedResult?.result.data?.ticker).to(equal(1))
    expect(results[1].parsedResult?.result.data?.ticker).to(equal(2))
  }

  func test__parsing__givenCapitalizedContentType_shouldReturnSuccess() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }

    let response: HTTPURLResponse = .mock(
      headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
    )

    streamMocker.emit(
      response: .mock(
        response: response,
        dataChunk: """
          Content-Type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 1
              }
            }
          }
          """.crlfFormattedData()
      )
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].parsedResult?.result.data?.ticker).to(equal(1))
  }

  func test__parsing__givenNullPayload_shouldIgnore() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }

    let response: HTTPURLResponse = .mock(
      headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
    )

    streamMocker.emit(
      response: .mock(
        response: response,
        dataChunk: """
          content-type: application/json

          {
            "payload": null
          }
          """.crlfFormattedData()
      )
    )

    streamMocker.emit(
      response: .mock(
        response: response,
        dataChunk: """
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 1
              }
            }
          }
          """.crlfFormattedData()
      )
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].parsedResult?.result.data?.ticker).to(equal(1))
  }

  func test__parsing__givenNullErrors_shouldIgnore() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }
    let response: HTTPURLResponse = .mock(
      headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
    )

    streamMocker.emit(
      response: .mock(
        response: response,
        dataChunk: """
          content-type: application/json

          {
            "errors": null
          }
          """.crlfFormattedData()
      )
    )
    streamMocker.emit(
      response: .mock(
        response: response,
        dataChunk: """
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 1
              }
            }
          }
          """.crlfFormattedData()
      )
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].parsedResult?.result.data?.ticker).to(equal(1))
  }

  func test__parsing__givenSingleChunk_shouldReturnSuccess() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 1
              }
            }
          }
          """.crlfFormattedData()
      )
    )

    let expectedData = try await Time(
      data: [
        "__typename": "Time",
        "ticker": 1,
      ],
      variables: nil
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].parsedResult?.result.data).to(equal(expectedData))
  }

  func test__parsing__givenSingleChunk_withMultipleContentTypeDirectives_shouldReturnSuccess() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/json; charset=utf-8

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 1
              }
            }
          }          
          """.crlfFormattedData()
      )
    )

    let expectedData = try await Time(
      data: [
        "__typename": "Time",
        "ticker": 1,
      ],
      variables: nil
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].parsedResult?.result.data).to(equal(expectedData))
  }

  func test__parsing__givenSingleChunk_withGraphQLOverHTTPContentType_shouldReturnSuccess() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/graphql-response+json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 1
              }
            }
          }
          """.crlfFormattedData()
      )
    )

    let expectedData = try await Time(
      data: [
        "__typename": "Time",
        "ticker": 1,
      ],
      variables: nil
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].parsedResult?.result.data).to(equal(expectedData))
  }

  func test__parsing__givenSingleChunk_withDashBoundaryInMessageBody_shouldReturnSuccess() async throws {
    let multipartBoundary = "-"

    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=\(multipartBoundary);subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 1,
                "description": "lots\(multipartBoundary)of-\(multipartBoundary)similar--\(multipartBoundary)boundaries---\(multipartBoundary)in----\(multipartBoundary)this-----\(multipartBoundary)string"
              }
            }
          }
          """.crlfFormattedData()
      )
    )

    let expectedData = try await Time(
      data: [
        "__typename": "Time",
        "ticker": 1,
      ],
      variables: nil
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].parsedResult?.result.data).to(equal(expectedData))
  }

  func test__parsing__givenMultipleChunks_shouldReturnMultipleSuccesses() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }
    let response: HTTPURLResponse = .mock(
      headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
    )

    streamMocker.emit(
      response: .mock(
        response: response,
        dataChunk: """
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 2
              }
            }
          }
          """.crlfFormattedData()
      )
    )
    streamMocker.emit(
      response: .mock(
        response: response,
        dataChunk: """
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 3
              }
            }
          }
          """.crlfFormattedData()
      )
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(2))
    expect(results[0].parsedResult?.result.data?.ticker).to(equal(2))
    expect(results[1].parsedResult?.result.data?.ticker).to(equal(3))
  }

  func test__parsing__givenPayloadAndUnknownKeys_shouldReturnSuccessAndIgnoreUnknownKeys() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/json

          {
            "foo": "bar",
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 1
              }
            }
          }
          """.crlfFormattedData()
      )
    )

    let expectedData = try await Time(
      data: [
        "__typename": "Time",
        "ticker": 1,
      ],
      variables: nil
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].parsedResult?.result.data).to(equal(expectedData))
  }

  func test__parsing__givenPayloadWithDataAndGraphQLError_shouldReturnSuccessWithDataAndGraphQLError() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/json

          {
            "payload": {
              "data": {
                "__typename": "Time",
                "ticker": 4
              },
              "errors": [
                {
                  "message": "test error"
                }
              ]
            }
          }
          """.crlfFormattedData()
      )
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].parsedResult?.result.data?.ticker).to(equal(4))
    expect(results[0].parsedResult?.result.errors).to(equal([GraphQLError("test error")]))
  }

  func test__parsing__givenPayloadWithNullDataAndGraphQLError_shouldReturnSuccessWithOnlyGraphQLError() async throws {
    let streamMocker = InterceptorResponseMocker<MockSubscription<Time>>()

    let resultStream = try await subject.intercept(
      request: JSONRequest.mock(operation: MockSubscription<Time>())
    ) { _ in
      streamMocker.getStream()
    }

    streamMocker.emit(
      response: .mock(
        response: .mock(
          headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
        ),
        dataChunk: """
          content-type: application/json

          {
            "payload": {
              "data": null,
              "errors": [
                {
                  "message": "test error"
                }
              ]
            }
          }
          """.crlfFormattedData()
      )
    )

    streamMocker.finish()

    let results = try await resultStream.getResults().getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].parsedResult?.result.data).to(beNil())
    expect(results[0].parsedResult?.result.errors).to(equal([GraphQLError("test error")]))
  }

}
