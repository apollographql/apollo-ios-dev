import Foundation

public protocol ApolloURLSession: Sendable {
  func chunks(
    for request: URLRequest
  ) async throws -> (any AsyncChunkSequence, URLResponse)

  func invalidateAndCancel()
}

extension URLSession: ApolloURLSession {
  public func chunks(for request: URLRequest) async throws -> (any AsyncChunkSequence, URLResponse) {
    let (bytes, response) = try await bytes(for: request, delegate: nil)
    return (bytes.chunks, response)
  }
}
