import Apollo
import ApolloAPI

extension JSONRequest {
  public static func mock(operation: Operation) -> JSONRequest<Operation> {
    return JSONRequest(
      operation: operation,
      graphQLEndpoint: TestURL.mockServer.url,      
    )
  }
}
