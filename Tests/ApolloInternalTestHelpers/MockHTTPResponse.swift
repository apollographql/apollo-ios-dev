import Apollo
import ApolloAPI
import Foundation

extension HTTPURLResponse {
  public static func mock(
    url: URL = TestURL.mockServer.url,
    statusCode: Int = 200,
    httpVersion: String? = nil,
    headerFields: [String: String]? = nil
  ) -> HTTPURLResponse {
    return HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: httpVersion,
      headerFields: headerFields
    )!
  }

  public static func deferResponseMock(
    url: URL = TestURL.mockServer.url,
    boundary: String = "graphql"
  ) -> HTTPURLResponse {
    .mock(
      url: url,
      headerFields: ["Content-Type": "multipart/mixed;boundary=\(boundary);deferSpec=20220824"]
    )
  }
}
