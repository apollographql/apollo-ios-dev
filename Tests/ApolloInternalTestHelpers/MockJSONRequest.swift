import Apollo
import ApolloAPI
import Foundation

extension JSONRequest {
  public static func mock(
    operation: Operation,
    fetchBehavior: FetchBehavior,
    graphQLEndpoint: URL = TestURL.mockServer.url
  ) -> JSONRequest<Operation> {
    return JSONRequest(
      operation: operation,
      graphQLEndpoint: graphQLEndpoint,
      fetchBehavior: fetchBehavior,
      writeResultsToCache: true,
      requestTimeout: nil
    )
  }
}
