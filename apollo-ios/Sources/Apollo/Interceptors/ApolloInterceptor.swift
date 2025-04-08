import Foundation
import Combine
#if !COCOAPODS
import ApolloAPI
#endif

public struct InterceptorResult<Operation: GraphQLOperation>: Sendable, ~Copyable {
  public let response: HTTPURLResponse
  public internal(set) var parsedResults: ParsedResultStream?

  public struct ParsedResult: Sendable {
    public var result: GraphQLResult<Operation.Data>
    public var cacheRecords: RecordSet?
  }

  public struct ParsedResultStream: Sendable, ~Copyable {

    private let stream: AsyncThrowingStream<ParsedResult, any Error>

    init(stream: AsyncThrowingStream<ParsedResult, any Error>) {
      self.stream = stream
    }

    public mutating func map(
      _ transform: @escaping @Sendable (ParsedResult) async throws -> ParsedResult
    ) async throws {
      let stream = self.stream

      let newStream = AsyncThrowingStream { continuation in
        let task = Task {
          for try await result in stream {
            try Task.checkCancellation()

            try await continuation.yield(transform(result))
          }
          continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }
      }
      self = Self.init(stream: newStream)
    }

    public consuming func getResults() -> AsyncThrowingStream<ParsedResult, any Error> {
      return stream
    }

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

  typealias NextInterceptorFunction<Operation: GraphQLOperation> = @Sendable (HTTPRequest<Operation>) async throws -> InterceptorResult<Operation>

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
//#warning("TODO: Move to new file; rename??")
//public protocol AnyAsyncSequence<Element>: AsyncSequence, Sendable {
//  associatedtype Iterator: AsyncIteratorProtocol where Iterator.Element == Element
//
//  func map<T>(_ transform: @escaping @Sendable (Self.Element) async throws -> T) -> any AnyAsyncSequence<T>
//}
//
//extension AsyncThrowingStream: AnyAsyncSequence {
//
//  public func map<T>(
//    _ transform: @escaping @Sendable (Element) async throws -> T
//  ) -> any AnyAsyncSequence<T> {
//    self.map(transform) as AsyncThrowingMapSequence<Self, T>
//  }
//}
//
//extension AsyncThrowingMapSequence: AnyAsyncSequence {
//  public func map<T>(
//    _ transform: @escaping @Sendable (Element) async throws -> T
//  ) -> any AnyAsyncSequence<T> {
//    self.map(transform) as AsyncThrowingMapSequence<Self, T>
//  }
//}
