@testable import Apollo
import ApolloAPI
import Foundation

public final class InterceptorResponseMocker<Operation: GraphQLOperation>: Sendable {

  private let internalStream: AsyncThrowingStream<InterceptorResult<Operation>, any Error>
  private let continuation: AsyncThrowingStream<InterceptorResult<Operation>, any Error>.Continuation

  public init() {
    (self.internalStream, self.continuation) =
    AsyncThrowingStream<InterceptorResult<Operation>, any Error>.makeStream()
  }

  public func getStream() -> InterceptorResultStream<Operation> {
    InterceptorResultStream(stream: internalStream)
  }

  public func emit(response: InterceptorResult<Operation>) {
    continuation.yield(response)
  }

  public func emit(error: any Error) {
    continuation.finish(throwing: error)
  }

  public func finish() {
    continuation.finish()
  }

  deinit {
    continuation.finish()
  }  
}

extension InterceptorResult {
  public static func mock(
    response: HTTPURLResponse = .mock(),
    dataChunk: Data = Data(),
    parsedResult: ParsedResult? = nil
  ) -> Self {
    self.init(response: response, rawResponseChunk: dataChunk, parsedResult: parsedResult)
  }
}
