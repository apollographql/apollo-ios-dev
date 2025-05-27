@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import XCTest
import Nimble

class JSONResponseParsingInterceptorTests: XCTestCase {

  var subject: JSONResponseParsingInterceptor!

  override func setUp() {
    super.setUp()
    subject = JSONResponseParsingInterceptor()
  }

  override func tearDown() {
    super.tearDown()
    subject = nil
  }

  func test__intercept__callsNextWithSameRequest() async throws {
    let expectedRequest = JSONRequest.mock(operation: MockOperation<MockSelectionSet>())

    nonisolated(unsafe) var nextCalled = false
    _ = try await subject.intercept(request: expectedRequest) { request in
      nextCalled = true

      expect(request).to(equal(expectedRequest))
      return InterceptorResultStream(stream: .init(unfolding: { return nil }))
    }

    await expect(nextCalled).toEventually(beTrue())
  }

  func test__intercept__givenEmptyResponse_throwsParsingError() async throws {
    let expectedRequest = JSONRequest.mock(operation: MockOperation<MockSelectionSet>())

    await expect {
      _ = try await self.subject.intercept(request: expectedRequest) { request in
        return InterceptorResultStream(stream: .init(unfolding: {
          return .init(response: .mock(), rawResponseChunk: Data())
        }))
      }.getResults().getAllValues()
    }.to(throwError(
      JSONResponseParsingError.couldNotParseToJSON(data: Data())
    ))
  }

  // Multipart Header Error Tests

  func test__error__givenResponse_withMissingMultipartBoundaryHeader_shouldReturnError() async throws {
    let subject = JSONResponseParsingInterceptor()

    let resultStream = try await subject.intercept(
      request: JSONRequest<MockSubscription<MockSelectionSet>>.mock(operation: MockSubscription.mock())
    ) { _ in
      let mockResult = InterceptorResult<MockSubscription<MockSelectionSet>>(
        response: .mock(headerFields: ["Content-Type": "multipart/mixed"]),
        rawResponseChunk: Data()
      )

      return InterceptorResultStream(
        stream: .init(unfolding: {
          return mockResult
        })
      )
    }.getResults()

    // when
    await expect { try await resultStream.getAllValues() }
    // then
      .to(throwError(JSONResponseParsingError.missingMultipartBoundary))
  }

  func test__error__givenResponse_withMissingMultipartProtocolSpecifier_shouldReturnError() async throws {
    let subject = JSONResponseParsingInterceptor()

    let resultStream = try await subject.intercept(
      request: JSONRequest<MockSubscription<MockSelectionSet>>.mock(operation: MockSubscription.mock())
    ) { _ in
      let mockResult = InterceptorResult<MockSubscription<MockSelectionSet>>(
        response: .mock(headerFields: ["Content-Type": "multipart/mixed;boundary=\"graphql\""]),
        rawResponseChunk: Data()
      )

      return InterceptorResultStream(
        stream: .init(unfolding: {
          return mockResult
        })
      )
    }.getResults()

    // when
    await expect { try await resultStream.getAllValues() }
    // then
      .to(throwError(JSONResponseParsingError.invalidMultipartProtocol))
  }

  func test__error__givenResponse_withUnknownMultipartProtocolSpecifier_shouldReturnError() async throws {
    let subject = JSONResponseParsingInterceptor()

    let resultStream = try await subject.intercept(
      request: JSONRequest<MockSubscription<MockSelectionSet>>.mock(operation: MockSubscription.mock())
    ) { _ in
      let mockResult = InterceptorResult<MockSubscription<MockSelectionSet>>(
        response: .mock(headerFields: ["Content-Type": "multipart/mixed;boundary=\"graphql\";unknownSpec=0"]),
        rawResponseChunk: Data()
      )

      return InterceptorResultStream(
        stream: .init(unfolding: {
          return mockResult
        })
      )
    }.getResults()

    // when
    await expect { try await resultStream.getAllValues() }
    // then
      .to(throwError(JSONResponseParsingError.invalidMultipartProtocol))
  }

  func test__error__givenResponse_withInvalidData_shouldReturnError() async throws {
    let subject = JSONResponseParsingInterceptor()
    let invalidData = "🙃".data(using: .unicode)!

    let resultStream = try await subject.intercept(
      request: JSONRequest<MockSubscription<MockSelectionSet>>.mock(operation: MockSubscription.mock())
    ) { _ in
      let mockResult = InterceptorResult<MockSubscription<MockSelectionSet>>(
        response: .mock(),
        rawResponseChunk: invalidData
      )

      return InterceptorResultStream(
        stream: .init(unfolding: {
          return mockResult
        })
      )
    }.getResults()

    // when
    await expect { try await resultStream.getAllValues() }
    // then
      .to(throwError(JSONResponseParsingError.couldNotParseToJSON(data: invalidData)))
  }
}
