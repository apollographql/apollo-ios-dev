import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

public struct InterceptorResult<Operation: GraphQLOperation>: Sendable {
  let response: HTTPResponse
  var parsedResult: ParsedResult?

  struct ParsedResult {
    var result: GraphQLResult<Operation.Data>
    var cacheRecords: RecordSet?
  }
}

#warning("TODO: Wrap RequestChain apis in SPI?")

/// A protocol to set up a chainable unit of networking work.
#warning("Rename to RequestChainInterceptor?")
#warning("TODO: Should this be Sendable or not?")
public protocol ApolloInterceptor: Sendable {

  /// Used to uniquely identify this interceptor from other interceptors in a request chain.
  ///
  /// Each operation request has it's own interceptor request chain so the interceptors do not
  /// need to be uniquely identifiable between each and every request, only unique between the
  /// list of interceptors in a single request.
#warning("Get rid of?")
//  var id: String { get }

  typealias NextInterceptorFunction<Operation: GraphQLOperation> = @Sendable () async throws -> InterceptorResultStream<Operation>

  typealias InterceptorResultStream<Operation: GraphQLOperation> = any AnyAsyncSequence<InterceptorResult<Operation>>

  /// Called when this interceptor should do its work.
  ///
  /// - Parameters:
  ///   - chain: The chain the interceptor is a part of.
  ///   - request: The request, as far as it has been constructed
  ///   - response: [optional] The response, if received
  ///   - completion: The completion block to fire when data needs to be returned to the UI.
  func intercept<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    next: NextInterceptorFunction<Operation>
  ) async throws -> InterceptorResultStream<Operation>

}

#warning("TODO: Implement retrying based on catching error")
struct RequestChainRetryError: Swift.Error { }

#warning("TODO: Move to new file; rename??")
public protocol AnyAsyncSequence<Element>: AsyncSequence, Sendable {
  associatedtype Iterator: AsyncIteratorProtocol where Iterator.Element == Element

  func map<T>(_ transform: @escaping @Sendable (Self.Element) async throws -> T) -> any AnyAsyncSequence<T>
}

extension AsyncThrowingStream: AnyAsyncSequence {

  public func map<T>(
    _ transform: @escaping @Sendable (Element) async throws -> T
  ) -> any AnyAsyncSequence<T> {
    self.map(transform) as AsyncThrowingMapSequence<Self, T>
  }
}

extension AsyncThrowingMapSequence: AnyAsyncSequence {
  public func map<T>(
    _ transform: @escaping @Sendable (Element) async throws -> T
  ) -> any AnyAsyncSequence<T> {
    self.map(transform) as AsyncThrowingMapSequence<Self, T>
  }
}
