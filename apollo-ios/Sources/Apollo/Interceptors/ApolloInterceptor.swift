import Foundation
import Combine
#if !COCOAPODS
import ApolloAPI
#endif

public struct InterceptorResult<Operation: GraphQLOperation>: Sendable {
  public let response: HTTPURLResponse
//  public var parsedResult: ParsedResult?
  public var parsedResultStream: (any AnyAsyncSequence<ParsedResult>)?

  public struct ParsedResult: Sendable {
    public var result: GraphQLResult<Operation.Data>
    public var cacheRecords: RecordSet?
  }

  // MARK: - Internal
  
  /// The `AsyncBytes` stream for the response data of the network request.
  ///
  /// This must stay internal to ensure it is only accessed by the `JSONResponseParsingInterceptor`.
  /// Because `AsyncSequence` elements are consumed when read, any external access to this stream
  /// will result in data loss.
  internal let responseAsyncBytes: URLSession.AsyncBytes

}

#warning("TODO: Wrap RequestChain apis in SPI?")

/// A protocol to set up a chainable unit of networking work.
#warning("Rename to RequestInterceptor? Or like Apollo Link?")
#warning("TODO: Should this be Sendable or not?")
public protocol ApolloInterceptor: Sendable {

  /// Used to uniquely identify this interceptor from other interceptors in a request chain.
  ///
  /// Each operation request has it's own interceptor request chain so the interceptors do not
  /// need to be uniquely identifiable between each and every request, only unique between the
  /// list of interceptors in a single request.
#warning("Get rid of?")
//  var id: String { get }

  typealias NextInterceptorFunction<Operation: GraphQLOperation> = @Sendable () async throws -> InterceptorResult<Operation>

//  typealias InterceptorResultStream<Operation: GraphQLOperation> = any AnyAsyncSequence<InterceptorResult<Operation>>

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
  ) async throws -> InterceptorResult<Operation>

}

//
//public struct InterceptorResultStream<Operation: GraphQLOperation>: Sendable {
//
////  public let result: InterceptorResult<Operation>
//
//  private let stream: AsyncThrowingStream<InterceptorResult<Operation>, any Error>
//
//  init(stream: AsyncThrowingStream<InterceptorResult<Operation>, any Error>) {
//    self.stream = stream
//  }
//
//  consuming func mapResults(
//    _ transform: @escaping @Sendable (InterceptorResult<Operation>) async throws -> InterceptorResult<Operation>
//  ) async throws -> Self {
//    let stream = self.stream
//
//    let newStream = AsyncThrowingStream { continuation in
//      let task = Task {
//        for try await result in stream {
//          try Task.checkCancellation()
//
//          try await continuation.yield(transform(result))
//        }
//        continuation.finish()
//      }
//
//      continuation.onTermination = { _ in task.cancel() }
//    }
//    return Self.init(stream: newStream)
//  }
//
//  consuming func getResults() -> AsyncThrowingStream<InterceptorResult<Operation>, any Error> {
//    return stream
//  }
//
//}

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
