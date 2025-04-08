import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// An interceptor to check the response code returned with a request.
public struct ResponseCodeInterceptor: ApolloInterceptor {

  public var id: String = UUID().uuidString
  
  public struct ResponseCodeError: Error, LocalizedError {
    let response: HTTPURLResponse

    public var errorDescription: String? {
      return "Received a \(response.statusCode) error."
    }
    
    public var graphQLError: GraphQLError? {
      switch self {
      case .invalidResponseCode(_, let rawData):
        if let jsonRawData = rawData,
           let jsonData = try? (JSONSerialization.jsonObject(with: jsonRawData, options: .allowFragments) as! JSONValue),
           let jsonObject = try? JSONObject(_jsonValue: jsonData)
        {
          return GraphQLError(jsonObject)
        }
        return nil
      }
    }
  }
  
  /// Designated initializer
  public init() {}
  
  public func intercept<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    next: NextInterceptorFunction<Operation>
  ) async throws -> InterceptorResult<Operation> {
    let result = try await next(request)

    guard result.response.isSuccessful == true else {
      throw ResponseCodeError.invalidResponseCode(
        response: result.response,
        rawData: response?.rawData
      )
    }

    return result
  }
}
