import XCTest
import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

class GraphQLRequest_RequestTimeoutTests: XCTestCase {
  // MARK: JSONRequest tests

  func test__jsonRequest__givenRequestTimeout_nil_doesNotConfigureRequestTimeout() throws {
    let jsonRequest = JSONRequest(
      operation: MockQuery<MockSelectionSet>(),
      graphQLEndpoint: TestURL.mockServer.url,
      fetchBehavior: .NetworkOnly,
      writeResultsToCache: false,
      requestTimeout: nil
    )

    let urlRequest = try jsonRequest.toURLRequest()

    expect(urlRequest.timeoutInterval).to(equal(60))
  }

  func test__jsonRequest__givenRequestTimeout_shouldConfigureRequestTimeout() throws {
    let jsonRequest = JSONRequest(
      operation: MockQuery<MockSelectionSet>(),
      graphQLEndpoint: TestURL.mockServer.url,
      fetchBehavior: .NetworkOnly,
      writeResultsToCache: false,
      requestTimeout: 120
    )

    let urlRequest = try jsonRequest.toURLRequest()

    expect(urlRequest.timeoutInterval).to(equal(120))
  }

  // MARK: UploadRequest tests

  func test__uploadRequest__withoutRequestConfigurationContext_doesNotConfigureRequestTimeout() throws {
    let uploadRequest = UploadRequest(
      operation: MockQuery<MockSelectionSet>(),
      graphQLEndpoint: TestURL.mockServer.url,
      files: [GraphQLFile(fieldName: "x", originalName: "y", data: "z".data(using: .utf8)!)],
      writeResultsToCache: false
    )

    let urlRequest = try uploadRequest.toURLRequest()

    expect(urlRequest.timeoutInterval).to(equal(60))
  }

  func test__uploadRequest__givenRequestConfigurationContext_shouldConfigureRequestTimeout() throws {
    var uploadRequest = UploadRequest(
      operation: MockQuery<MockSelectionSet>(),
      graphQLEndpoint: TestURL.mockServer.url,
      files: [GraphQLFile(fieldName: "x", originalName: "y", data: "z".data(using: .utf8)!)],
      writeResultsToCache: false
    )
    
    uploadRequest.requestTimeout = 120

    let urlRequest = try uploadRequest.toURLRequest()

    expect(urlRequest.timeoutInterval).to(equal(120))
  }
}
