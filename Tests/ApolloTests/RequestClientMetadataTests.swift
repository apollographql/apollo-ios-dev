import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

#warning(
"""
TODO: These tests need to be rewritten to call an actual ApolloClient and verify that
- The ClientContext is passed through to the request creation properly
- The GraphQLRequest.toURLRequest() retrieves the value and uses it properly
- The RequestBodyCreator retrieves the value and uses it properly
""")
class ClientAwarenessMetadataTests: XCTestCase {

//  private final class Hero: MockSelectionSet, @unchecked Sendable {
//    typealias Schema = MockSchemaMetadata
//
//    override class var __selections: [Selection] {
//      [
//        .field("__typename", String.self),
//        .field("name", String.self),
//      ]
//    }
//
//    var name: String { __data["name"] }
//  }
//
//  // MARK: JSONRequest
//
//  func
//    test__jsonRequest__usingDefaultInitializer_shouldAddClientLibraryExtensionToBody_shouldNotIncludeClientApplicationHeaders()
//    throws
//  {
//    let jsonRequest = JSONRequest.mock(
//      operation: MockQuery<Hero>(),
//      fetchBehavior: .NetworkOnly,
//      graphQLEndpoint: TestURL.mockServer.url
//    )
//
//    let urlRequest = try jsonRequest.toURLRequest()
//
//    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
//      fail("Missing HTTP header fields!")
//      return
//    }
//
//    expect(httpHeaderFields["apollographql-client-version"]).to(beNil())
//    expect(httpHeaderFields["apollographql-client-name"]).to(beNil())
//
//    guard
//      let httpBody = urlRequest.httpBody,
//      let jsonBody = try? JSONSerializationFormat.deserialize(data: httpBody) as JSONObject,
//      let extensions = jsonBody["extensions"] as? JSONObject,
//      let clientLibrary = extensions["clientLibrary"] as? JSONObject
//    else {
//      fail("Could not deserialize client library extension.")
//      return
//    }
//
//    expect(clientLibrary["name"]).to(equal(Constants.ApolloClientName))
//    expect(clientLibrary["version"]).to(equal(Constants.ApolloClientVersion))
//  }
//
//  func test__jsonRequest__given_includeApolloSDKAwareness_true_shouldAddClientLibraryExtensionToBody() throws {
//    let jsonRequest = JSONRequest.mock(
//      operation: MockQuery<Hero>(),
//      fetchBehavior: .NetworkOnly,
//      graphQLEndpoint: TestURL.mockServer.url,
//      clientAwarenessMetadata: ClientAwarenessMetadata(includeApolloLibraryAwareness: true)
//    )
//
//    let urlRequest = try jsonRequest.toURLRequest()
//
//    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
//      fail("Missing HTTP header fields!")
//      return
//    }
//
//    expect(httpHeaderFields["apollographql-client-version"]).to(beNil())
//    expect(httpHeaderFields["apollographql-client-name"]).to(beNil())
//
//    guard
//      let httpBody = urlRequest.httpBody,
//      let jsonBody = try? JSONSerializationFormat.deserialize(data: httpBody) as JSONObject,
//      let extensions = jsonBody["extensions"] as? JSONObject,
//      let clientLibrary = extensions["clientLibrary"] as? JSONObject
//    else {
//      fail("Could not deserialize client library extension.")
//      return
//    }
//
//    expect(clientLibrary["name"]).to(equal(Constants.ApolloClientName))
//    expect(clientLibrary["version"]).to(equal(Constants.ApolloClientVersion))
//  }
//
//  func
//    test__jsonRequest__given_applicationNameAndVersion_shouldAddClientApplicationHeaders_shouldNotAddClientLibraryExtension()
//    throws
//  {
//    let jsonRequest = JSONRequest(
//      operation: MockQuery<Hero>(),
//      graphQLEndpoint: TestURL.mockServer.url,
//      clientAwarenessMetadata: ClientAwarenessMetadata(
//        clientApplicationName: "test-client",
//        clientApplicationVersion: "test-client-version",
//        includeApolloLibraryAwareness: false
//      )
//    )
//
//    let urlRequest = try jsonRequest.toURLRequest()
//
//    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
//      fail("Missing HTTP header fields!")
//      return
//    }
//
//    expect(httpHeaderFields["apollographql-client-version"]).to(equal("test-client-version"))
//    expect(httpHeaderFields["apollographql-client-name"]).to(equal("test-client"))
//
//    guard
//      let httpBody = urlRequest.httpBody,
//      let jsonBody = try? JSONSerializationFormat.deserialize(data: httpBody) as JSONObject
//    else {
//      fail("Could not deserialize extensions.")
//      return
//    }
//
//    expect(jsonBody["extensions"]).to(beNil())
//  }
//
//  // MARK: UploadRequest
//
//  func
//    test__uploadRequest__usingDefaultInitializer_shouldAddClientLibraryExtensionToBody_shouldNotIncludeClientApplicationHeaders()
//    throws
//  {
//    let uploadRequest = UploadRequest(
//      operation: MockQuery<Hero>(),
//      graphQLEndpoint: TestURL.mockServer.url,
//      files: [GraphQLFile(fieldName: "x", originalName: "y", data: "z".data(using: .utf8)!)]
//    )
//
//    let urlRequest = try uploadRequest.toURLRequest()
//
//    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
//      fail("Missing HTTP header fields!")
//      return
//    }
//
//    expect(httpHeaderFields["apollographql-client-version"]).to(beNil())
//    expect(httpHeaderFields["apollographql-client-name"]).to(beNil())
//
//    guard
//      let httpBody = urlRequest.httpBody,
//      let multipartBody = String(data: httpBody, encoding: .utf8)
//    else {
//      fail("Could not deserialize client library extension.")
//      return
//    }
//
//    expect(multipartBody).to(
//      contain(
//        "{\"extensions\":{\"clientLibrary\":{\"name\":\"apollo-ios\",\"version\":\"\(Constants.ApolloClientVersion)\"}},\"operationName\":\"MockOperationName\",\"query\":\"Mock Operation Definition\",\"variables\":{\"x\":null}}"
//      )
//    )
//  }
//
//  func test__uploadRequest__given_includeApolloSDKAwareness_true_shouldAddClientLibraryExtensionToBody() throws {
//    let uploadRequest = UploadRequest(
//      operation: MockQuery<Hero>(),
//      graphQLEndpoint: TestURL.mockServer.url,
//      files: [GraphQLFile(fieldName: "x", originalName: "y", data: "z".data(using: .utf8)!)],
//      clientAwarenessMetadata: ClientAwarenessMetadata(
//        includeApolloLibraryAwareness: true
//      )
//    )
//
//    let urlRequest = try uploadRequest.toURLRequest()
//
//    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
//      fail("Missing HTTP header fields!")
//      return
//    }
//
//    expect(httpHeaderFields["apollographql-client-version"]).to(beNil())
//    expect(httpHeaderFields["apollographql-client-name"]).to(beNil())
//
//    guard
//      let httpBody = urlRequest.httpBody,
//      let multipartBody = String(data: httpBody, encoding: .utf8)
//    else {
//      fail("Could not deserialize client library extension.")
//      return
//    }
//
//    expect(multipartBody).to(
//      contain(
//        "{\"extensions\":{\"clientLibrary\":{\"name\":\"apollo-ios\",\"version\":\"\(Constants.ApolloClientVersion)\"}},\"operationName\":\"MockOperationName\",\"query\":\"Mock Operation Definition\",\"variables\":{\"x\":null}}"
//      )
//    )
//  }
//
//  func
//    test__uploadRequest__given_applicationNameAndVersion_shouldAddClientApplicationHeaders_shouldNotAddClientLibraryExtension()
//    throws
//  {
//    let uploadRequest = UploadRequest(
//      operation: MockQuery<Hero>(),
//      graphQLEndpoint: TestURL.mockServer.url,
//      files: [GraphQLFile(fieldName: "x", originalName: "y", data: "z".data(using: .utf8)!)],
//      clientAwarenessMetadata: ClientAwarenessMetadata(
//        clientApplicationName: "test-client",
//        clientApplicationVersion: "test-client-version",
//        includeApolloLibraryAwareness: false
//      )
//    )
//
//    let urlRequest = try uploadRequest.toURLRequest()
//
//    guard let httpHeaderFields = urlRequest.allHTTPHeaderFields else {
//      fail("Missing HTTP header fields!")
//      return
//    }
//
//    expect(httpHeaderFields["apollographql-client-version"]).to(equal("test-client-version"))
//    expect(httpHeaderFields["apollographql-client-name"]).to(equal("test-client"))
//
//    guard
//      let httpBody = urlRequest.httpBody,
//      let multipartBody = String(data: httpBody, encoding: .utf8)
//    else {
//      fail("Could not deserialize extensions.")
//      return
//    }
//
//    expect(multipartBody).notTo(
//      contain(
//        "\"extensions\":{\"clientLibrary\":{\"name\":\"apollo-ios\",\"version\":\"\(Constants.ApolloClientVersion)\"}}"
//      )
//    )
//  }
}
