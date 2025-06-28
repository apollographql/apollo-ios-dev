import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

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

  func test__intercept__givenEmptyResponse_throwsParsingError() async throws {
    // given
    let operation = MockQuery<MockSelectionSet>()
    let expectedRequest = JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly)

    let streamMocker = AsyncStreamMocker<Data>()
    streamMocker.emit(Data())

    // when
    await expect {
      try await self.subject.parse(
        response: HTTPResponse(
          response: .mock(),
          chunks: streamMocker.getStream()
        ),
        for: expectedRequest,
        includeCacheRecords: false
      )
      .getStream()
      .getAllValues()
    }.to(
      throwError(
        JSONResponseParsingError.couldNotParseToJSON(data: Data())
      )
    )
  }

  // Multipart Header Error Tests

  func test__error__givenResponse_withMissingMultipartBoundaryHeader_shouldReturnError() async throws {
    // given
    let operation = MockSubscription<MockSelectionSet>()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.mock(headerFields: ["Content-Type": "multipart/mixed"])
    streamMocker.emit(Data())

    // when
    await expect {
      try await self.subject.parse(
        response: HTTPResponse(
          response: urlResponse,
          chunks: streamMocker.getStream()
        ),
        for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
        includeCacheRecords: false
      )
      .getStream()
      .getAllValues()
    }.to(
      throwError(
        JSONResponseParsingError.missingMultipartBoundary
      )
    )
  }

  func test__error__givenResponse_withMissingMultipartProtocolSpecifier_shouldReturnError() async throws {
    // given
    let operation = MockSubscription<MockSelectionSet>.mock()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.mock(headerFields: ["Content-Type": "multipart/mixed;boundary=\"graphql\""])
    streamMocker.emit(Data())

    // when
    await expect {
      try await self.subject.parse(
        response: HTTPResponse(
          response: urlResponse,
          chunks: streamMocker.getStream()
        ),
        for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
        includeCacheRecords: false
      )
      .getStream()
      .getAllValues()
    }.to(
      throwError(
        JSONResponseParsingError.invalidMultipartProtocol
      )
    )
  }

  func test__error__givenResponse_withUnknownMultipartProtocolSpecifier_shouldReturnError() async throws {
    // given
    let operation = MockSubscription<MockSelectionSet>.mock()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.mock(headerFields: ["Content-Type": "multipart/mixed;boundary=\"graphql\";unknownSpec=0"])
    streamMocker.emit(Data())

    // when
    await expect {
      try await self.subject.parse(
        response: HTTPResponse(
          response: urlResponse,
          chunks: streamMocker.getStream()
        ),
        for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
        includeCacheRecords: false
      )
      .getStream()
      .getAllValues()
    }.to(
      throwError(
        JSONResponseParsingError.invalidMultipartProtocol
      )
    )
  }

  func test__error__givenResponse_withInvalidData_shouldReturnError() async throws {
    // given
    let operation = MockSubscription<MockSelectionSet>.mock()
    let invalidData = "🙃".data(using: .unicode)!
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.mock()
    streamMocker.emit(invalidData)

    // when
    await expect {
      try await self.subject.parse(
        response: HTTPResponse(
          response: urlResponse,
          chunks: streamMocker.getStream()
        ),
        for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
        includeCacheRecords: false
      )
      .getStream()
      .getAllValues()
    }.to(
      throwError(
        JSONResponseParsingError.couldNotParseToJSON(data: invalidData)
      )
    )
  }
}
