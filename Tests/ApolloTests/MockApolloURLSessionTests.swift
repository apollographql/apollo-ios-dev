@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import ApolloTestSupport
import Nimble
import XCTest

@testable @_spi(Execution) import Apollo

/// Tests for the `MockApolloURLSession` shipped in `ApolloTestSupport`.
///
/// These exercise it the way a consumer would: as the `urlSession` of a real `RequestChainNetworkTransport`, so the
/// interceptors, response parsing, and cache writes all run normally.
class MockApolloURLSessionTests: XCTestCase {

  private let serverUrl = TestURL.mockServer.url

  private class Hero: MockSelectionSet, @unchecked Sendable {
    typealias Schema = MockSchemaMetadata

    override class var __selections: [Selection] {
      [
        .field("__typename", String.self),
        .field("name", String.self),
      ]
    }

    var name: String { __data["name"] }
  }

  private func makeTransport(
    session: MockApolloURLSession,
    store: ApolloStore = .mock()
  ) -> RequestChainNetworkTransport {
    RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: store,
      endpointURL: serverUrl
    )
  }

  // MARK: - Single Responses

  func test__respondWith__givenJSONResponse__shouldParseTypedData() async throws {
    let session = MockApolloURLSession()
    session.respond(
      with: .json("""
        {"data": {"__typename": "Hero", "name": "R2-D2"}}
        """)
    )

    let results = try await makeTransport(session: session).send(
      query: MockQuery<Hero>(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    expect(results).to(haveCount(1))
    expect(results.first?.source).to(equal(.server))
    expect(results.first?.data?.name).to(equal("R2-D2"))
  }

  func test__receivedRequests__givenRequestSent__shouldRecordRequest() async throws {
    let session = MockApolloURLSession()
    session.respond(
      with: .json("""
        {"data": {"__typename": "Hero", "name": "R2-D2"}}
        """)
    )

    _ = try await makeTransport(session: session).send(
      query: MockQuery<Hero>(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    expect(session.receivedRequests).to(haveCount(1))
    expect(session.receivedRequests.first?.url).to(equal(serverUrl))
    expect(session.receivedRequests.first?.httpMethod).to(equal("POST"))
  }

  func test__respondWithHandler__givenRequest__shouldBeCalledWithTheOutgoingRequest() async throws {
    let session = MockApolloURLSession()
    session.respond { request in
      let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
      let name = body.contains(MockQuery<Hero>.operationName) ? "R2-D2" : "Unexpected"

      return .response(
        .json("""
          {"data": {"__typename": "Hero", "name": "\(name)"}}
          """)
      )
    }

    let results = try await makeTransport(session: session).send(
      query: MockQuery<Hero>(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    expect(results.first?.data?.name).to(equal("R2-D2"))
  }

  // MARK: - Errors

  func test__failWith__givenError__shouldThrowFromResultStream() async throws {
    let session = MockApolloURLSession()
    session.fail(with: URLError(.notConnectedToInternet))

    await expect {
      try await self.makeTransport(session: session).send(
        query: MockQuery<Hero>(),
        fetchBehavior: .NetworkOnly,
        requestConfiguration: RequestConfiguration(writeResultsToCache: false)
      ).getAllValues()
    }.to(throwError(URLError(.notConnectedToInternet)))
  }

  func test__chunks__givenNoStubRegistered__shouldThrowNoStubRegistered() async throws {
    let session = MockApolloURLSession()

    await expect {
      try await self.makeTransport(session: session).send(
        query: MockQuery<Hero>(),
        fetchBehavior: .NetworkOnly,
        requestConfiguration: RequestConfiguration(writeResultsToCache: false)
      ).getAllValues()
    }.to(throwError { error in
      guard
        let mockError = error as? MockApolloURLSession.Error,
        case .noStubRegistered(_) = mockError
      else {
        return fail("Expected noStubRegistered, got \(error)")
      }
    })
  }

  func test__respondWith__givenErrorStatusCode__shouldThrowResponseCodeError() async throws {
    let session = MockApolloURLSession()
    session.respond(with: .json("""
      {"errors": [{"message": "Unauthorized"}]}
      """, statusCode: 401))

    await expect {
      try await self.makeTransport(session: session).send(
        query: MockQuery<Hero>(),
        fetchBehavior: .NetworkOnly,
        requestConfiguration: RequestConfiguration(writeResultsToCache: false)
      ).getAllValues()
    }.to(throwError())
  }

  // MARK: - Queued Responses

  func test__enqueue__givenMultipleStubs__shouldReturnThemInOrder() async throws {
    let session = MockApolloURLSession()
    session.enqueue(
      .response(.json("""
        {"data": {"__typename": "Hero", "name": "First"}}
        """)),
      .response(.json("""
        {"data": {"__typename": "Hero", "name": "Second"}}
        """))
    )

    let transport = makeTransport(session: session)

    let first = try await transport.send(
      query: MockQuery<Hero>(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    let second = try await transport.send(
      query: MockQuery<Hero>(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    expect(first.first?.data?.name).to(equal("First"))
    expect(second.first?.data?.name).to(equal("Second"))
  }

  // MARK: - Multipart Responses

  func test__respondWithMultipart__givenSubscriptionParts__shouldEmitOneResultPerPart() async throws {
    let session = MockApolloURLSession()
    session.respond(
      with: .multipart(parts: [
        #"{"payload":{"data":{"__typename":"Hero","name":"R2-D2"}}}"#,
        #"{"payload":{"data":{"__typename":"Hero","name":"C-3PO"}}}"#,
      ])
    )

    let results = try await makeTransport(session: session).send(
      subscription: MockSubscription<Hero>(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    expect(results).to(haveCount(2))
    expect(results[0].data?.name).to(equal("R2-D2"))
    expect(results[1].data?.name).to(equal("C-3PO"))
  }

  // MARK: - Cache Integration

  func test__respondWith__givenWriteResultsToCache__shouldWriteThroughToStore() async throws {
    let session = MockApolloURLSession()
    session.respond(
      with: .json("""
        {"data": {"__typename": "Hero", "name": "R2-D2"}}
        """)
    )

    // A real in-memory cache — `ApolloStore.mock()` is backed by `NoCache` and would drop the write.
    let store = ApolloStore()
    let transport = makeTransport(session: session, store: store)

    _ = try await transport.send(
      query: MockQuery<Hero>(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: true)
    ).getAllValues()

    // Reading back from the store proves the stubbed response went through the real parsing and cache-write path.
    let cached = try await store.load(MockQuery<Hero>())

    expect(cached?.data?.name).to(equal("R2-D2"))
  }

  // MARK: - Reset

  func test__reset__givenPreviousStubsAndRequests__shouldClearThem() async throws {
    let session = MockApolloURLSession()
    session.respond(
      with: .json("""
        {"data": {"__typename": "Hero", "name": "R2-D2"}}
        """)
    )

    _ = try await makeTransport(session: session).send(
      query: MockQuery<Hero>(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    ).getAllValues()

    expect(session.receivedRequests).to(haveCount(1))

    session.reset()

    expect(session.receivedRequests).to(beEmpty())

    await expect {
      try await self.makeTransport(session: session).send(
        query: MockQuery<Hero>(),
        fetchBehavior: .NetworkOnly,
        requestConfiguration: RequestConfiguration(writeResultsToCache: false)
      ).getAllValues()
    }.to(throwError { error in
      guard
        let mockError = error as? MockApolloURLSession.Error,
        case .noStubRegistered(_) = mockError
      else {
        return fail("Expected noStubRegistered, got \(error)")
      }
    })
  }
}
