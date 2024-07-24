import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// An interceptor which actually fetches data from the network.
public class NetworkFetchInterceptor: ApolloInterceptor {
  let client: URLSessionClient

  public var id: String = UUID().uuidString
  
  /// Designated initializer.
  ///
  /// - Parameter client: The `URLSessionClient` to use to fetch data
  public init(client: URLSessionClient) {
    self.client = client
  }
  
  public func intercept<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    response: HTTPResponse<Operation>?
  ) async throws -> RequestChain.NextAction<Operation> {
    let urlRequest = try request.toURLRequest()
    let taskDescription = "\(Operation.operationType) \(Operation.operationName)"

    let (data, httpResponse) = try await self.client.send(
      urlRequest,
      taskDescription: taskDescription
    )

    try Task.checkCancellation()

    let response = HTTPResponse<Operation>(
      response: httpResponse,
      rawData: data,
      parsedResult: nil,
      cacheRecords: nil
    )

    return .proceed(request: request, response: response)
  }

}
