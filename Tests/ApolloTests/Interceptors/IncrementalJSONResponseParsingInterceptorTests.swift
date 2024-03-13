import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import XCTest
import Nimble

class IncrementalJSONResponseParsingInterceptorTests: XCTestCase {

  class CatQuery: MockQuery<CatQuery.CatSelectionSet> {
    class CatSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("isJellicle", Bool.self)
      ]}
    }
  }

  class DogQuery: MockQuery<DogQuery.DogSelectionSet> {
    class DogSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("favouriteToy", String.self)
      ]}
    }
  }

  let defaultTimeout = 0.5

  // MARK: Errors

  func test__errors__givenNoResponse_shouldThrow() {
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: nil
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beFailure { error in
        expect(error).to(
          matchError(IncrementalJSONResponseParsingInterceptor.ParsingError.noResponseToParse)
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test_errors_givenEmptyDataResponse_shouldThrow() {
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: .mock(data: Data())
    ) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beFailure { error in
        expect(error).to(
          matchError(
            IncrementalJSONResponseParsingInterceptor.ParsingError.couldNotParseToJSON(data: Data())
          )
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test_errors_givenIncrementalResponse_withMismatchedPartialResult_shouldThrow() {
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")
    expectation.expectedFulfillmentCount = 2

    subject.intercept(
      request: .mock(operation: CatQuery()),
      response: .mock(data: #"{"data":{"isJellicle":false}}"#.data(using: .utf8)!)
    ) { result in

      expect(result).to(beSuccess())
      expectation.fulfill()

      subject.intercept(
        request: .mock(operation: DogQuery()),
        response: .mock(data: #"{"incremental":{"favouriteToy":"Stick"}}"#.data(using: .utf8)!)
      ) { result in

        expect(result).to(beFailure { error in
          expect(error).to(matchError(
            IncrementalJSONResponseParsingInterceptor.ParsingError.mismatchedCurrentResultType
          ))
          expectation.fulfill()
        })
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test_errors_givenResponse_withMissingIncrementalKey_shouldThrow() {
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")
    expectation.expectedFulfillmentCount = 2

    subject.intercept(
      request: .mock(operation: CatQuery()),
      response: .mock(data: #"{"data":{"isJellicle":false}}"#.data(using: .utf8)!)
    ) { result in

      expect(result).to(beSuccess())
      expectation.fulfill()

      subject.intercept(
        request: .mock(operation: CatQuery()),
        response: .mock(data: #"{"data":{"isJellicle":false}}"#.data(using: .utf8)!)
      ) { result in

        expect(result).to(beFailure { error in
          expect(error).to(matchError(
            IncrementalJSONResponseParsingInterceptor.ParsingError.couldNotParseIncrementalJSON(
              json: ["data": ["isJellicle": false]]
            )
          ))
          expectation.fulfill()
        })
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }
}
