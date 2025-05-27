import ApolloAPI

@testable import Apollo

/// A protocol mock InterceptorProviders can conform to which provides default mock implementations of the url session.
public protocol MockInterceptorProvider: InterceptorProvider {

  var store: ApolloStore { get }

  var urlSession: MockURLSession { get }

}

extension MockInterceptorProvider {

  public var store: ApolloStore {
    .mock()
  }

  public var urlSession: MockURLSession {
    MockURLSession(responseProvider: MockNoOpResponseProvider.self)
  }

  public func cacheInterceptor<Operation>(for operation: Operation) -> any CacheInterceptor
  where Operation: GraphQLOperation {
    DefaultCacheInterceptor(store: store)
  }

  public func urlSession<Operation>(for operation: Operation) -> any ApolloURLSession
  where Operation: GraphQLOperation {
    urlSession
  }

}

private struct MockNoOpResponseProvider: MockResponseProvider {

}

final class DefaultMockInterceptorProvider<T: MockResponseProvider>: MockInterceptorProvider {
  let urlSession: MockURLSession = MockURLSession(responseProvider: T.self)

  func interceptors<Operation: GraphQLOperation>(
    for operation: Operation
  ) -> [any ApolloInterceptor] {
    [
      JSONResponseParsingInterceptor(),
      ResponseCodeInterceptor(),
    ]
  }
}

public extension MockResponseProvider {

  static func TestInterceptorProvider() -> some MockInterceptorProvider {
    DefaultMockInterceptorProvider<Self>()
  }

}
