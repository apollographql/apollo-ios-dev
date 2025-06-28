import Apollo
import ApolloAPI
import Foundation

public final class MockNetworkTransport: NetworkTransport {
  let requestChainTransport: RequestChainNetworkTransport

  public init(
    server: MockGraphQLServer = MockGraphQLServer(),
    store: ApolloStore
  ) {
    let session = MockGraphQLServerSession(server: server)
    self.requestChainTransport = RequestChainNetworkTransport(
      interceptorProvider: DefaultInterceptorProvider(session: session, store: store),
      endpointURL: TestURL.mockServer.url
    )
  }

  public func send<Query>(
    query: Query,
    cachePolicy: CachePolicy,
  ) throws -> AsyncThrowingStream<GraphQLResult<Query.Data>, any Error> where Query: GraphQLQuery {
    try requestChainTransport.send(
      query: query,
      cachePolicy: cachePolicy
    )
  }

  public func send<Mutation>(
    mutation: Mutation,
    cachePolicy: CachePolicy,
  ) throws -> AsyncThrowingStream<GraphQLResult<Mutation.Data>, any Error> where Mutation: GraphQLMutation {
    try requestChainTransport.send(
      mutation: mutation,
      cachePolicy: cachePolicy
    )
  }

}
