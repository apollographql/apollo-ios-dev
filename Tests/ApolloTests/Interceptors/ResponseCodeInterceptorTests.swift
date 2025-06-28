import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

class ResponseCodeInterceptorTests: XCTestCase, MockResponseProvider {

  override func tearDown() async throws {
    await Self.cleanUpRequestHandlers()
    try await super.tearDown()
  }

  func testResponseCodeInterceptorLetsAnyDataThroughWithValidResponseCode() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: MockURLSession(responseProvider: Self.self),
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: .mock(),
      endpointURL: TestURL.mockServer.url
    )

    let query = MockQuery.mock()

    await Self.registerRequestHandler(for: TestURL.mockServer.url) { _ in
      return (
        HTTPURLResponse(
          url: TestURL.mockServer.url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!,
            """
            "invalid": {}            
            """.data(using: .utf8)!
      )
    }

    let responseStream = try network.send(
      query: query,
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration()
    )
    var responseIterator = responseStream.makeAsyncIterator()

    await expect {
      try await responseIterator.next()
    }.to(
      throwError(
        errorType: JSONResponseParsingError.self,
        closure: { error in
          guard case .couldNotParseToJSON = error else {
            fail("wrong error")
            return
          }
        }
      )
    )
  }

  func testResponseCodeInterceptorDoesNotLetDataThroughWithInvalidResponseCode() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: MockURLSession(responseProvider: Self.self),
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: .mock(),
      endpointURL: TestURL.mockServer.url
    )

    await Self.registerRequestHandler(for: TestURL.mockServer.url) { _ in
      let json = [
        "data": [
          "hero": [
            "name": "Luke Skywalker",
            "__typename": "Human",
          ]
        ]
      ]
      let data = try! JSONSerializationFormat.serialize(value: json)

      return (
        HTTPURLResponse(
          url: TestURL.mockServer.url,
          statusCode: 401,
          httpVersion: nil,
          headerFields: nil
        )!,
        data
      )
    }

    let responseStream = try network.send(
      query: MockQuery.mock(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration()
    )
    var responseIterator = responseStream.makeAsyncIterator()

    await expect {
      try await responseIterator.next()
    }.to(
      throwError(
        errorType: ResponseCodeInterceptor.ResponseCodeError.self,
        closure: { error in
          guard let dataString = String(bytes: error.chunk, encoding: .utf8) else {
            XCTFail("Incorrect data returned with error")
            return
          }

          guard
            let dataEntry = error.graphQLError?["data"] as? JSONObject,
            let heroEntry = dataEntry["hero"] as? JSONObject,
            let typeName = heroEntry["__typename"] as? String,
            let heroName = heroEntry["name"] as? String
          else {
            XCTFail("Invalid GraphQL Error")
            return
          }
          XCTAssertEqual("GraphQL Error", error.graphQLError?.description)
          XCTAssertEqual("Human", typeName)
          XCTAssertEqual("Luke Skywalker", heroName)

          XCTAssertEqual(dataString, "{\"data\":{\"hero\":{\"__typename\":\"Human\",\"name\":\"Luke Skywalker\"}}}")
        }
      )
    )
  }

  func testResponseCodeInterceptorDoesNotHaveGraphQLError() async throws {
    let network = RequestChainNetworkTransport(
      urlSession: MockURLSession(responseProvider: Self.self),
      interceptorProvider: DefaultInterceptorProvider.shared,
      store: .mock(),
      endpointURL: TestURL.mockServer.url
    )

    await Self.registerRequestHandler(for: TestURL.mockServer.url) { _ in
      return (
        HTTPURLResponse(
          url: TestURL.mockServer.url,
          statusCode: 401,
          httpVersion: nil,
          headerFields: nil
        )!,
        "Not a GraphQL Error".data(using: .utf8)
      )
    }

    let responseStream = try network.send(
      query: MockQuery.mock(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration()
    )
    var responseIterator = responseStream.makeAsyncIterator()

    await expect {
      try await responseIterator.next()
    }.to(
      throwError(
        errorType: ResponseCodeInterceptor.ResponseCodeError.self,
        closure: { error in
          XCTAssertEqual(error.response.statusCode, 401)

          guard let dataString = String(bytes: error.chunk, encoding: .utf8) else {
            XCTFail("Incorrect data returned with error")
            return
          }

          XCTAssertNil(error.graphQLError)

          XCTAssertEqual(dataString, "Not a GraphQL Error")
        }
      )
    )
  }
}
