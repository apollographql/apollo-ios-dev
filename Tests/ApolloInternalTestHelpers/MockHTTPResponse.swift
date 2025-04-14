import Apollo
import ApolloAPI
import Foundation

extension HTTPURLResponse {
  public static func mock(
    url: URL = TestURL.mockServer.url,
    statusCode: Int = 200,
    httpVersion: String? = nil,
    headerFields: [String : String]? = nil
  ) -> HTTPURLResponse {
    return HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: httpVersion,
      headerFields: headerFields
    )!
  }
}
