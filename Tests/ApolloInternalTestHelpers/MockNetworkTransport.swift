@_spi(Internal) import Apollo
import ApolloAPI
import Foundation

public final class MockNetworkTransport: NetworkTransport, UploadingNetworkTransport {
  public let mockServer: MockGraphQLServer
  public let requestChainTransport: RequestChainNetworkTransport

  public var url: URL { requestChainTransport.endpointURL }

  public init(
    mockServer: MockGraphQLServer = MockGraphQLServer(),
    store: ApolloStore
  ) {
    self.mockServer = mockServer
    let session = MockSession(server: mockServer)
    self.requestChainTransport = RequestChainNetworkTransport(
      urlSession: session,
      interceptorProvider: MockInterceptorProvider(),
      store: store,
      endpointURL: TestURL.mockServer.url
    )
  }

  public func send<Query: GraphQLQuery>(
    query: Query,
    fetchBehavior: FetchBehavior,
    requestConfiguration: RequestConfiguration
  ) throws -> AsyncThrowingStream<GraphQLResponse<Query>, any Error> {
    try requestChainTransport.send(
      query: query,
      fetchBehavior: fetchBehavior,
      requestConfiguration: requestConfiguration
    )
  }

  public func send<Mutation: GraphQLMutation>(
    mutation: Mutation,
    requestConfiguration: RequestConfiguration
  ) throws -> AsyncThrowingStream<GraphQLResponse<Mutation>, any Error> {
    try requestChainTransport.send(
      mutation: mutation,
      requestConfiguration: requestConfiguration
    )
  }

  public func upload<Operation>(
    operation: Operation,
    files: [GraphQLFile],
    requestConfiguration: RequestConfiguration
  ) throws -> AsyncThrowingStream<GraphQLResponse<Operation>, any Error> where Operation: GraphQLOperation {
    try requestChainTransport.upload(
      operation: operation,
      files: files,
      requestConfiguration: requestConfiguration
    )
  }

  private struct MockInterceptorProvider: InterceptorProvider {
    func graphQLInterceptors<Operation: GraphQLOperation>(for operation: Operation) -> [any GraphQLInterceptor] {
      return DefaultInterceptorProvider.shared.graphQLInterceptors(for: operation) + [TaskLocalRequestInterceptor()]
    }
  }

  fileprivate struct TaskLocalRequestInterceptor: GraphQLInterceptor {
    @TaskLocal static var currentRequest: (any GraphQLRequest)? = nil

    func intercept<Request>(
      request: Request,
      next: (Request) async -> InterceptorResultStream<Request>
    ) async throws -> InterceptorResultStream<Request> {
      return await TaskLocalRequestInterceptor.$currentRequest.withValue(request) {
        return await next(request)
      }
    }
  }

  fileprivate struct MockSession: ApolloURLSession {

    let server: MockGraphQLServer

    init(server: MockGraphQLServer) {
      self.server = server
    }

    func chunks(for request: URLRequest) async throws -> (any AsyncChunkSequence, URLResponse) {
      guard let graphQLRequest = TaskLocalRequestInterceptor.currentRequest else {
        throw MockGraphQLServer.ServerError.unexpectedRequest(request.description)
      }

      let (stream, continuation) = MockAsyncChunkSequence.makeStream()
      do {
        let body = try await server.serve(request: graphQLRequest)
        let data = try JSONSerializationFormat.serialize(value: body)
        continuation.yield(data)
        continuation.finish()

      } catch {
        continuation.finish(throwing: error)
      }

      let httpResponse = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (stream, httpResponse)
    }

  }

}

public struct MockAsyncChunkSequence: AsyncChunkSequence {
  public typealias UnderlyingStream = AsyncThrowingStream<Data, any Error>

  public typealias AsyncIterator = UnderlyingStream.AsyncIterator

  public typealias Element = Data

  let underlying: UnderlyingStream

  public func makeAsyncIterator() -> UnderlyingStream.AsyncIterator {
    underlying.makeAsyncIterator()
  }

  public static func makeStream() -> (
    stream: MockAsyncChunkSequence,
    continuation: UnderlyingStream.Continuation
  ) {
    let (s, c) = UnderlyingStream.makeStream(of: Data.self)
    return (Self.init(underlying: s), c)
  }
}
