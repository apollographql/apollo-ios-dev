@testable import ApolloCodegenLib
import Foundation

public final class MockNetworkSession: NetworkSession {
  let statusCode: Int
  let data: Data?
  let error: (any Error)?
  let abandon: Bool

  public init(statusCode: Int, data: Data? = nil, error: (any Error)? = nil, abandon: Bool = false) {
    self.statusCode = statusCode
    self.data = data
    self.error = error
    self.abandon = abandon
  }

  public func loadData(with urlRequest: URLRequest, completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) async -> Void) -> URLSessionDataTask? {
    guard !abandon else { return nil }

    let response = HTTPURLResponse(url: urlRequest.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)
    Task { [data, error] in
      await completionHandler(data, response, error)
    }

    return nil
  }
}
