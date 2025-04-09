import Foundation
import Combine
#if !COCOAPODS
import ApolloAPI
#endif

public struct InterceptorResult<Operation: GraphQLOperation>: Sendable {

  public let response: HTTPURLResponse

  /// This is the data for a single chunk of the response bondy.
  ///
  /// If this is not a multipart response, this will include the data for the entire response body.
  ///
  /// If this is a multipart response, the response chunk will only one chunk.
  /// The `InterceptorResultStream` will return multiple results – one for each multipart chunk.
  public let rawResponseChunk: Data

  public var parsedResult: ParsedResult?

  public struct ParsedResult: Sendable {
    public let result: GraphQLResult<Operation.Data>
    public let cacheRecords: RecordSet?
  }

}

#warning("TODO: Wrap RequestChain apis in SPI?")

/// A protocol to set up a chainable unit of networking work.
#warning("Rename to RequestInterceptor? Or like Apollo Link?")
#warning("TODO: Should this be Sendable or not?")
public protocol ApolloInterceptor: Sendable {

  typealias NextInterceptorFunction<Operation: GraphQLOperation> = @Sendable (HTTPRequest<Operation>) async throws -> InterceptorResultStream<Operation>

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

public struct InterceptorResultStream<Operation: GraphQLOperation>: Sendable, ~Copyable {

  private let stream: AsyncThrowingStream<InterceptorResult<Operation>, any Error>

  init(stream: AsyncThrowingStream<InterceptorResult<Operation>, any Error>) {
    self.stream = stream
  }

  public consuming func map(
    _ transform: @escaping @Sendable (InterceptorResult<Operation>) async throws -> InterceptorResult<Operation>
  ) async throws -> InterceptorResultStream<Operation> {
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
    return Self.init(stream: newStream)
  }

  public consuming func compactMap(
    _ transform: @escaping @Sendable (InterceptorResult<Operation>) async throws -> InterceptorResult<Operation>?
  ) async throws -> InterceptorResultStream<Operation> {
    let stream = self.stream

    let newStream = AsyncThrowingStream { continuation in
      let task = Task {
        for try await result in stream {
          try Task.checkCancellation()

          guard let newResult = try await transform(result) else {
            continue
          }

          continuation.yield(newResult)
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in task.cancel() }
    }
    return Self.init(stream: newStream)
  }

  public consuming func getResults() -> AsyncThrowingStream<InterceptorResult<Operation>, any Error> {
    return stream
  }

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
