import XCTest
import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

final class MultipartResponseSubscriptionParserTests: XCTestCase {

  let defaultTimeout = 0.5

  // MARK: - Error tests

  func test__error__givenIncorrectContentType_shouldReturnError() throws {
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
          --graphql--
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

  func test__error__givenTransportError_shouldReturnError() throws {
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
          --graphql--
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

  func test__error__givenTransportErrorWithNullPayload_shouldReturnError() throws {
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
            "payload": null,
            "errors" : [
              {
                "message" : "forced test failure!"
              }
            ]
          }
          --graphql--
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

  func test__error__givenTransportErrorWithValidPayload_errorShouldTakePrecendenceAndReturnError() throws {
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
          --graphql--
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

  func test__error__givenTransportErrorIncludingUnknownKeys_shouldReturnErrorWithMessageOnly() throws {
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
                "message" : "forced test failure!",
                "path": [
                  "hello"
                ],
                "foo": "bar"
              }
            ]
          }
          --graphql--
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

  func test__error__givenMalformedJSON_shouldReturnError() throws {
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
          --graphql--
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

  // MARK: Parsing tests

  private class Time: MockSelectionSet {
    typealias Schema = MockSchemaMetadata

    override class var __selections: [Selection] {[
      .field("__typename", String.self),
      .field("ticker", Int.self)
    ]}

    var ticker: Int { __data["ticker"] }
  }

  private func buildNetworkTransport(
    responseData: Data,
    multipartBoundary boundary: String = "graphql"
  ) -> RequestChainNetworkTransport {
    let client = MockURLSessionClient(
      response: .mock(headerFields: ["Content-Type": "multipart/mixed;boundary=\(boundary);subscriptionSpec=1.0"]),
      data: responseData
    )

    let provider = MockInterceptorProvider([
      NetworkFetchInterceptor(client: client),
      MultipartResponseParsingInterceptor(),
      JSONResponseParsingInterceptor()
    ])

    return RequestChainNetworkTransport(
      interceptorProvider: provider,
      endpointURL: TestURL.mockServer.url
    )
  }

  func test__parsing__givenHeartbeat_shouldIgnore() throws {
    let network = buildNetworkTransport(responseData: """
      
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
      content-type: application/json

      {}
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
      --graphql--
      """.crlfFormattedData()
    )

    let expectation = expectation(description: "Heartbeat ignored")
    expectation.expectedFulfillmentCount = 2

    _ = network.send(operation: MockSubscription<Time>()) { result in
      switch (result) {
      case let .success(data):
        guard let time = data.data else {
          fail("Unexpected missing data!")
          return
        }

        expect(time.__typename).to(equal("Time"))

        switch time.ticker {
        case 1...2: expectation.fulfill()
        default: fail("Unexpected data value!")
        }

      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenNullPayload_shouldIgnore() throws {
    let network = buildNetworkTransport(responseData: """
      
      --graphql
      Content-Type: application/json

      {
        "payload": null
      }
      --graphql
      Content-Type: application/json

      {
        "payload": {
          "data": {
            "__typename": "Time",
            "ticker": 1
          }
        }
      }
      --graphql--
      """.crlfFormattedData()
    )

    let expectation = expectation(description: "Null payload ignored")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      switch (result) {
      case let .success(data):
        guard let time = data.data else {
          fail("Unexpected missing data!")
          return
        }

        expect(time.__typename).to(equal("Time"))
        expect(time.ticker).to(equal(1))

        expectation.fulfill()

      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenNullErrors_shouldIgnore() throws {
    let network = buildNetworkTransport(responseData: """
      
      --graphql
      content-type: application/json

      {
        "errors": null
      }
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
      --graphql--
      """.crlfFormattedData()
    )

    let expectation = expectation(description: "Null errors ignored")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      switch (result) {
      case let .success(data):
        guard let time = data.data else {
          fail("Unexpected missing data!")
          return
        }

        expect(time.__typename).to(equal("Time"))
        expect(time.ticker).to(equal(1))

        expectation.fulfill()

      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenSingleChunk_shouldReturnSuccess() throws {
    let network = buildNetworkTransport(responseData: """
      
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
      --graphql--
      """.crlfFormattedData()
    )

    let expectedData = try Time(data: [
      "__typename": "Time",
      "ticker": 1
    ], variables: nil)

    let expectation = expectation(description: "Multipart data received")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        expect(data.data).to(equal(expectedData))
      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenSingleChunk_withMultipleContentTypeDirectives_shouldReturnSuccess() throws {
    let network = buildNetworkTransport(responseData: """
      
      --graphql
      Content-Type: application/json; charset=utf-8

      {
        "payload": {
          "data": {
            "__typename": "Time",
            "ticker": 1
          }
        }
      }
      --graphql--
      """.crlfFormattedData()
    )

    let expectedData = try Time(data: [
      "__typename": "Time",
      "ticker": 1
    ], variables: nil)

    let expectation = expectation(description: "Multipart data received")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        expect(data.data).to(equal(expectedData))
      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenSingleChunk_withDashBoundaryInMessageBody_shouldReturnSuccess() throws {
    let multipartBoundary = "-"
    let network = buildNetworkTransport(
      responseData: """
        
        --\(multipartBoundary)
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
        --\(multipartBoundary)--
        """.crlfFormattedData(),
      multipartBoundary: multipartBoundary
    )

    let expectedData = try Time(data: [
      "__typename": "Time",
      "ticker": 1
    ], variables: nil)

    let expectation = expectation(description: "Multipart data received")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        expect(data.data).to(equal(expectedData))
      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenMultipleChunks_shouldReturnMultipleSuccesses() throws {
    let network = buildNetworkTransport(responseData: """
      
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
      --graphql--
      """.crlfFormattedData()
    )

    let expectation = expectation(description: "Multipart data received")
    expectation.expectedFulfillmentCount = 2

    _ = network.send(operation: MockSubscription<Time>()) { result in
      switch (result) {
      case let .success(data):
        guard let time = data.data else {
          fail("Unexpected missing data!")
          return
        }

        expect(time.__typename).to(equal("Time"))
        switch time.ticker {
        case 2...3: expectation.fulfill()
        default: fail("Unexpected data value!")
        }

      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenPayloadAndUnknownKeys_shouldReturnSuccessAndIgnoreUnknownKeys() throws {
    let network = buildNetworkTransport(responseData: """
      
      --graphql
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
      --graphql--
      """.crlfFormattedData()
    )

    let expectedData = try Time(data: [
      "__typename": "Time",
      "ticker": 1
    ], variables: nil)

    let expectation = expectation(description: "Multipart data received")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        expect(data.data).to(equal(expectedData))
      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenPayloadWithDataAndGraphQLError_shouldReturnSuccessWithDataAndGraphQLError() throws {
    let network = buildNetworkTransport(responseData: """
      
      --graphql
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
      --graphql--
      """.crlfFormattedData()
    )

    let expectation = expectation(description: "Multipart data received")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      switch (result) {
      case let .success(data):
        guard let time = data.data else {
          fail("Unexpected missing data!")
          return
        }

        expect(time.__typename).to(equal("Time"))
        expect(time.ticker).to(equal(4))
        expect(data.errors).to(equal([GraphQLError("test error")]))

        expectation.fulfill()

      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenPayloadWithNullDataAndGraphQLError_shouldReturnSuccessWithOnlyGraphQLError() throws {
    let network = buildNetworkTransport(responseData: """
      
      --graphql
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
      --graphql--
      """.crlfFormattedData()
    )

    let expectation = expectation(description: "Multipart data received")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      switch (result) {
      case let .success(data):
        expect(data.errors).to(equal([GraphQLError("test error")]))

        expectation.fulfill()

      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenEndOfStream_shouldReturnSuccess() throws {
    let network = buildNetworkTransport(responseData: """
      
      --graphql
      content-type: application/json

      {
        "payload": {
          "data": {
            "__typename": "Time",
            "ticker": 5
          }
        }
      }
      --graphql--
      """.crlfFormattedData()
    )

    let expectedData = try Time(data: [
      "__typename": "Time",
      "ticker": 5
    ], variables: nil)

    let expectation = expectation(description: "Multipart data received")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        expect(data.data).to(equal(expectedData))
      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }
}
