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
            },
            "hasNext": true
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
          --graphql--
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

  func test__error__givenChunk_withMissingPartialOrIncrementalData_shouldReturnError() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"],
        data: """
          
          --graphql
          content-type: application/json

          {
            "key": "value"
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
          matchError(MultipartResponseDeferParser.ParsingError.cannotParsePayloadData)
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
        "key": "value"
      ],
      "hasNext": true
    ]

    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"],
        data: """
          
          --graphql
          content-type: application/json

          {
            "data" : {
              "key" : "value"
            },
            "hasNext": true
          }
          --graphql--
          """.crlfFormattedData()
      )
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beSuccess())

      guard
        let response = try! result.get(),
        let deserialized = try! JSONSerialization.jsonObject(with: response.rawData) as? JSONObject
      else {
        return fail("data could not be deserialized!")
      }

      expect(deserialized).to(equal(expected))
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenSingleChunk_withMultipleContentTypeDirectives_shouldReturnSuccess() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    let expected: JSONObject = [
      "data": [
        "key": "value"
      ],
      "hasNext": true
    ]

    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"],
        data: """
          
          --graphql
          Content-Type: application/json; charset=utf-8

          {
            "data" : {
              "key" : "value"
            },
            "hasNext": true
          }
          --graphql--
          """.crlfFormattedData()
      )
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beSuccess())

      guard
        let response = try! result.get(),
        let deserialized = try! JSONSerialization.jsonObject(with: response.rawData) as? JSONObject
      else {
        return fail("data could not be deserialized!")
      }

      expect(deserialized).to(equal(expected))
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenSingleChunk_withGraphQLOverHTTPContentType_shouldReturnSuccess() throws {
    let subject = InterceptorTester(interceptor: MultipartResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    let expected: JSONObject = [
      "data": [
        "key": "value"
      ],
      "hasNext": true
    ]

    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"],
        data: """
          
          --graphql
          content-type: application/graphql-response+json

          {
            "data" : {
              "key" : "value"
            },
            "hasNext": true
          }
          --graphql--
          """.crlfFormattedData()
      )
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beSuccess())

      guard
        let response = try! result.get(),
        let deserialized = try! JSONSerialization.jsonObject(with: response.rawData) as? JSONObject
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
          "__typename": "AnAnimal",
          "animal": [
            "__typename": "Animal",
            "species": "Canis familiaris"
          ]
        ],
        "hasNext": true
      ],
      [
        "incremental": [
          [
            "label": "deferredGenus",
            "data": [
              "genus": "Canis"
            ],
            "path": [
              "animal"
            ]
          ]
        ],
        "hasNext": false
      ]
    ]

    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: .mock(
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"],
        data: """
          
          --graphql
          content-type: application/json

          {
            "data": {
              "__typename": "AnAnimal",
              "animal": {
                "__typename": "Animal",
                "species": "Canis familiaris"
              }
            },
            "hasNext": true
          }
          --graphql
          content-type: application/json

          {
            "incremental": [
              {
                "label": "deferredGenus",
                "data": {
                  "genus": "Canis"
                },
                "path": [
                  "animal"
                ]
              }
            ],
            "hasNext": false
          }
          --graphql--
          """.crlfFormattedData()
      )
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beSuccess())

      guard
        let response = try! result.get(),
        let deserialized = try! JSONSerialization.jsonObject(with: response.rawData) as? JSONObject
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
