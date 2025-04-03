import Foundation

public protocol ApolloURLSession: Sendable {
  func bytes(
    for request: URLRequest,
    delegate: (any URLSessionTaskDelegate)?
  ) async throws -> (URLSession.AsyncBytes, URLResponse)

  func invalidateAndCancel()
}

extension URLSession: ApolloURLSession { }
