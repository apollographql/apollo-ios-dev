import Apollo
import ApolloAPI
import Foundation

/// Use this interceptor tester to isolate a single `ApolloInterceptor` vs. having to create an
/// `InterceptorRequestChain` and end the interceptor list with `JSONResponseParsingInterceptor`
/// to get a parsed `GraphQLResult` for the standard request chain callback.
public class InterceptorTester {
  let interceptor: any ApolloInterceptor

  public init(interceptor: any ApolloInterceptor) {
    self.interceptor = interceptor
  }

  public func intercept<Operation>(
    request: Apollo.HTTPRequest<Operation>,
    response: Apollo.HTTPResponse<Operation>? = nil,
    completion: @escaping @Sendable (Result<HTTPResponse<Operation>?, any Error>) -> Void
  ) {
    let requestChain = ResponseCaptureRequestChain<Operation>({ result in
      completion(result)
    })

    self.interceptor.interceptAsync(
      chain: requestChain,
      request: request,
      response: response) { _ in }
  }
}

fileprivate class ResponseCaptureRequestChain<T: GraphQLOperation>: RequestChain {
  var isCancelled: Bool = false
  let completion: (Result<HTTPResponse<T>?, any Error>) -> Void

  init(_ completion: @escaping (Result<HTTPResponse<T>?, any Error>) -> Void) {
    self.completion = completion
  }

  func kickoff<Operation>(
    request: Apollo.HTTPRequest<Operation>,
    completion: @escaping GraphQLResultHandler<Operation.Data>
  ) {}

  func proceedAsync<Operation>(
    request: Apollo.HTTPRequest<Operation>,
    response: Apollo.HTTPResponse<Operation>?,
    completion: @escaping GraphQLResultHandler<Operation.Data>
  ) {
    self.completion(.success(response as? HTTPResponse<T>))
  }

  func proceedAsync<Operation>(
    request: HTTPRequest<Operation>,
    response: HTTPResponse<Operation>?,
    interceptor: any ApolloInterceptor,
    completion: @escaping GraphQLResultHandler<Operation.Data>
  ) {
    self.completion(.success(response as? HTTPResponse<T>))
  }

  func cancel() {}

  func retry<Operation>(
    request: Apollo.HTTPRequest<Operation>,
    completion: @escaping GraphQLResultHandler<Operation.Data>
  ) {}

  func handleErrorAsync<Operation>(
    _ error: any Error,
    request: Apollo.HTTPRequest<Operation>,
    response: Apollo.HTTPResponse<Operation>?,
    completion: @escaping GraphQLResultHandler<Operation.Data>
  ) {
    self.completion(.failure(error))
  }

  func returnValueAsync<Operation>(
    for request: Apollo.HTTPRequest<Operation>,
    value: Apollo.GraphQLResult<Operation.Data>,
    completion: @escaping GraphQLResultHandler<Operation.Data>
  ) {}
}
