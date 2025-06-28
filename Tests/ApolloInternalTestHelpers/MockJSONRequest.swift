import Apollo
import ApolloAPI

extension JSONRequest {
  public static func mock(
    operation: Operation,
    fetchBehavior: FetchBehavior
  ) -> JSONRequest<Operation> {
    return JSONRequest(
      operation: operation,
      graphQLEndpoint: TestURL.mockServer.url,
      fetchBehavior: fetchBehavior,
      writeResultsToCache: true,
      requestTimeout: nil
    )
  }
}
