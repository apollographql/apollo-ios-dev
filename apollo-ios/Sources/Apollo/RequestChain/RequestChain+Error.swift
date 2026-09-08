import Foundation

extension RequestChain {

  /// An error thrown by the ``RequestChain`` itself, rather than by one of its interceptors or the network.
  public enum Error: Swift.Error, LocalizedError {

    /// A ``GraphQLInterceptor`` emitted a result without calling its `next` closure, skipping the remaining steps of
    /// the ``RequestChain``.
    ///
    /// - Parameters:
    ///   - interceptor: The ``GraphQLInterceptor`` that did not call `next`, if it could be identified.
    ///   - operationName: The name of the operation the ``RequestChain`` was executing.
    case interceptorDidNotCallNext(interceptor: (any GraphQLInterceptor)?, operationName: String)

    public var errorDescription: String? {
      switch self {
      case let .interceptorDidNotCallNext(interceptor, operationName):
        let interceptorName = interceptor.map { "\(type(of: $0))" } ?? "A GraphQLInterceptor"

        return
          "\(interceptorName) emitted a result for operation \"\(operationName)\" without calling the `next` closure."
      }
    }

    public var recoverySuggestion: String? {
      switch self {
      case .interceptorDidNotCallNext:
        return """
          Every GraphQLInterceptor must call `next`. To supply a result without performing a network fetch, stub the \
          ApolloURLSession, or call `next` and recover from the error with `mapErrors`.
          """
      }
    }
  }
}
