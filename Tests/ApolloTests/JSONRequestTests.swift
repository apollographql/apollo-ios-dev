import Apollo
import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

class JSONRequestTests: XCTestCase {

  func test__init__givenSubscription_shouldAddMultipartAcceptHeader() {
    let subject = JSONRequest.mock(
      operation: MockSubscription.mock(),
      fetchBehavior: .NetworkOnly,
      graphQLEndpoint: TestURL.mockServer.url,
    )

    expect(try subject.toURLRequest().allHTTPHeaderFields?["Accept"])
      .to(
        equal(
          "multipart/mixed;\(MultipartResponseSubscriptionParser.protocolSpec),application/graphql-response+json,application/json"
        )
      )
  }

  func test__init__givenQuery_shouldAddMultipartAcceptHeader() {
    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .NetworkOnly,
      graphQLEndpoint: TestURL.mockServer.url,
    )

    expect(try subject.toURLRequest().allHTTPHeaderFields?["Accept"])
      .to(
        equal(
          "multipart/mixed;\(MultipartResponseDeferParser.protocolSpec),application/graphql-response+json,application/json"
        )
      )
  }

  func test__init__givenMutation_shouldAddMultipartAcceptHeader() {
    let subject = JSONRequest.mock(
      operation: MockQuery.mock(),
      fetchBehavior: .NetworkOnly,
      graphQLEndpoint: TestURL.mockServer.url,
    )

    expect(try subject.toURLRequest().allHTTPHeaderFields?["Accept"])
      .to(
        equal(
          "multipart/mixed;\(MultipartResponseDeferParser.protocolSpec),application/graphql-response+json,application/json"
        )
      )
  }

}
