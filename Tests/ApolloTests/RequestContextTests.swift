import XCTest
import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

class RequestContextTests: XCTestCase {
  private class Hero: MockSelectionSet {
    typealias Schema = MockSchemaMetadata

    override class var __selections: [Selection] {[
      .field("__typename", String.self),
      .field("name", String.self)
    ]}

    var name: String { __data["name"] }
  }

  private struct TwoMinuteTimeoutContext: RequestContextTimeoutConfigurable {
    let requestTimeout: TimeInterval

    init(requestTimeout: TimeInterval) {
      self.requestTimeout = requestTimeout
    }
  }

  private let twoMinuteTimeout = TwoMinuteTimeoutContext(requestTimeout: 120)

  // MARK: JSONRequest tests

  func test__jsonRequest__withoutRequestConfigurationContext_doesNotConfigureRequestTimeout() throws {
    let jsonRequest = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version"
    )

    let urlRequest = try jsonRequest.toURLRequest()

    expect(urlRequest.timeoutInterval).to(equal(60))
  }

  func test__jsonRequest__givenRequestConfigurationContext_shouldConfigureRequestTimeout() throws {
    let jsonRequest = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version",
      context: twoMinuteTimeout
    )

    let urlRequest = try jsonRequest.toURLRequest()

    expect(urlRequest.timeoutInterval).to(equal(120))
  }

  // MARK: UploadRequest tests

  func test__uploadRequest__withoutRequestConfigurationContext_doesNotConfigureRequestTimeout() throws {
    let uploadRequest = UploadRequest(
      graphQLEndpoint: TestURL.mockServer.url,
      operation: MockQuery<Hero>(),
      clientName: "test-client",
      clientVersion: "test-client-version",
      files: [GraphQLFile(fieldName: "x", originalName: "y", data: "z".data(using: .utf8)!)]
    )

    let urlRequest = try uploadRequest.toURLRequest()

    expect(urlRequest.timeoutInterval).to(equal(60))
  }

  func test__uploadRequest__givenRequestConfigurationContext_shouldConfigureRequestTimeout() throws {
    let uploadRequest = UploadRequest(
      graphQLEndpoint: TestURL.mockServer.url,
      operation: MockQuery<Hero>(),
      clientName: "test-client",
      clientVersion: "test-client-version",
      files: [GraphQLFile(fieldName: "x", originalName: "y", data: "z".data(using: .utf8)!)],
      context: twoMinuteTimeout
    )

    let urlRequest = try uploadRequest.toURLRequest()

    expect(urlRequest.timeoutInterval).to(equal(120))
  }
}
