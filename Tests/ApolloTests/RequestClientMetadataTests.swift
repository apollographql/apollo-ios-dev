import XCTest
import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

class RequestClientMetadataTests : XCTestCase {

  private class Hero: MockSelectionSet {
    typealias Schema = MockSchemaMetadata

    override class var __selections: [Selection] {[
      .field("__typename", String.self),
      .field("name", String.self)
    ]}

    var name: String { __data["name"] }
  }

  // MARK: JSONRequest

  func test__jsonRequest__usingDefaultInitializer_shouldAddClientHeadersAndExtension() throws {
    let jsonRequest = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version"
    )

    let urlRequest = try jsonRequest.toURLRequest()

    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
      fail("Missing HTTP header fields!")
      return
    }

    expect(httpHeaderFields["apollographql-client-version"]).to(equal("test-client-version"))
    expect(httpHeaderFields["apollographql-client-name"]).to(equal("test-client"))

    guard
      let httpBody = urlRequest.httpBody,
      let jsonBody = try? JSONSerialization.jsonObject(with: httpBody) as? JSONObject,
      let extensions = jsonBody["extensions"] as? JSONObject,
      let clientLibrary = extensions["clientLibrary"] as? JSONObject
    else {
      fail("Could not deserialize client library extension.")
      return
    }

    expect(clientLibrary["name"]).to(equal(Constants.ApolloClientName))
    expect(clientLibrary["version"]).to(equal(Constants.ApolloClientVersion))
  }

  func test__jsonRequest__usingInitializerEnablingClientExtension_shouldAddClientHeadersAndExtension() throws {
    let jsonRequest = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version",
      sendClientMetadataExtension: true
    )

    let urlRequest = try jsonRequest.toURLRequest()

    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
      fail("Missing HTTP header fields!")
      return
    }

    expect(httpHeaderFields["apollographql-client-version"]).to(equal("test-client-version"))
    expect(httpHeaderFields["apollographql-client-name"]).to(equal("test-client"))

    guard
      let httpBody = urlRequest.httpBody,
      let jsonBody = try? JSONSerialization.jsonObject(with: httpBody) as? JSONObject,
      let extensions = jsonBody["extensions"] as? JSONObject,
      let clientLibrary = extensions["clientLibrary"] as? JSONObject
    else {
      fail("Could not deserialize client library extension.")
      return
    }

    expect(clientLibrary["name"]).to(equal(Constants.ApolloClientName))
    expect(clientLibrary["version"]).to(equal(Constants.ApolloClientVersion))
  }

  func test__jsonRequest__usingInitializerDisablingClientExtension_shouldAddClientHeaders_doesNotAddClientExtension() throws {
    let jsonRequest = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version",
      sendClientMetadataExtension: false
    )

    let urlRequest = try jsonRequest.toURLRequest()

    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
      fail("Missing HTTP header fields!")
      return
    }

    expect(httpHeaderFields["apollographql-client-version"]).to(equal("test-client-version"))
    expect(httpHeaderFields["apollographql-client-name"]).to(equal("test-client"))

    guard
      let httpBody = urlRequest.httpBody,
      let jsonBody = try? JSONSerialization.jsonObject(with: httpBody) as? JSONObject
    else {
      fail("Could not deserialize client library extension.")
      return
    }

    expect(jsonBody["extensions"]).to(beNil())
  }

  // MARK: UploadRequest

  func test__uploadRequest__usingDefaultInitializer_shouldAddClientHeadersAndExtension() throws {
    let uploadRequest = UploadRequest(
      graphQLEndpoint: TestURL.mockServer.url,
      operation: MockQuery<Hero>(),
      clientName: "test-client",
      clientVersion: "test-client-version",
      files: [GraphQLFile(fieldName: "x", originalName: "y", data: "z".data(using: .utf8)!)]
    )

    let urlRequest = try uploadRequest.toURLRequest()

    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
      fail("Missing HTTP header fields!")
      return
    }

    expect(httpHeaderFields["apollographql-client-version"]).to(equal("test-client-version"))
    expect(httpHeaderFields["apollographql-client-name"]).to(equal("test-client"))

    guard
      let httpBody = urlRequest.httpBody,
      let multipartBody = String(data: httpBody, encoding: .utf8)
    else {
      fail("Could not deserialize client library extension.")
      return
    }

    expect(multipartBody).to(contain("{\"extensions\":{\"clientLibrary\":{\"name\":\"apollo-ios\",\"version\":\"\(Constants.ApolloClientVersion)\"}},\"operationName\":\"MockOperationName\",\"query\":\"Mock Operation Definition\",\"variables\":{\"x\":null}}"))
  }

  func test__uploadRequest__usingInitializerEnablingClientExtension_shouldAddClientHeadersAndExtension() throws {
    let uploadRequest = UploadRequest(
      graphQLEndpoint: TestURL.mockServer.url,
      operation: MockQuery<Hero>(),
      clientName: "test-client",
      clientVersion: "test-client-version",
      files: [GraphQLFile(fieldName: "x", originalName: "y", data: "z".data(using: .utf8)!)],
      sendClientMetadataExtension: true
    )

    let urlRequest = try uploadRequest.toURLRequest()

    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
      fail("Missing HTTP header fields!")
      return
    }

    expect(httpHeaderFields["apollographql-client-version"]).to(equal("test-client-version"))
    expect(httpHeaderFields["apollographql-client-name"]).to(equal("test-client"))

    guard
      let httpBody = urlRequest.httpBody,
      let multipartBody = String(data: httpBody, encoding: .utf8)
    else {
      fail("Could not deserialize client library extension.")
      return
    }

    expect(multipartBody).to(contain("{\"extensions\":{\"clientLibrary\":{\"name\":\"apollo-ios\",\"version\":\"\(Constants.ApolloClientVersion)\"}},\"operationName\":\"MockOperationName\",\"query\":\"Mock Operation Definition\",\"variables\":{\"x\":null}}"))
  }

  func test__uploadRequest__usingInitializerDisablingClientExtension_shouldAddClientHeaders_doesNotAddClientExtension() throws {
    let uploadRequest = UploadRequest(
      graphQLEndpoint: TestURL.mockServer.url,
      operation: MockQuery<Hero>(),
      clientName: "test-client",
      clientVersion: "test-client-version",
      files: [GraphQLFile(fieldName: "x", originalName: "y", data: "z".data(using: .utf8)!)],
      sendClientMetadataExtension: false
    )

    let urlRequest = try uploadRequest.toURLRequest()

    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
      fail("Missing HTTP header fields!")
      return
    }

    expect(httpHeaderFields["apollographql-client-version"]).to(equal("test-client-version"))
    expect(httpHeaderFields["apollographql-client-name"]).to(equal("test-client"))

    guard
      let httpBody = urlRequest.httpBody,
      let multipartBody = String(data: httpBody, encoding: .utf8)
    else {
      fail("Could not deserialize client library extension.")
      return
    }

    expect(multipartBody).notTo(contain("\"extensions\":{\"clientLibrary\":{\"name\":\"apollo-ios\",\"version\":\"\(Constants.ApolloClientVersion)\"}}"))
  }
}
