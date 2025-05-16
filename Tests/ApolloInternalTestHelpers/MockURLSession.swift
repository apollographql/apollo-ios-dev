import Foundation
import Apollo
import ApolloAPI

public struct MockURLSession: ApolloURLSession {

  public let session: URLSession

  public init<T: MockResponseProvider>(responseProvider: T.Type) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol<T>.self]
    session = URLSession(configuration: configuration)
  }

  public func chunks(
    for request: some GraphQLRequest
  ) async throws -> (any AsyncChunkSequence, URLResponse) {
    try await session.chunks(for: request)
  }

  public func invalidateAndCancel() {	
    session.invalidateAndCancel()
  }
}
