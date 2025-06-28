@testable import Apollo
import ApolloAPI
import Foundation

public final class AsyncStreamMocker<T: Sendable>: Sendable {

  private let internalStream: AsyncThrowingStream<T, any Error>
  private let continuation: AsyncThrowingStream<T, any Error>.Continuation

  public init() {
    (self.internalStream, self.continuation) =
    AsyncThrowingStream<T, any Error>.makeStream()
  }

  public func getStream() -> NonCopyableAsyncThrowingStream<T> {
    NonCopyableAsyncThrowingStream(stream: internalStream)
  }

  public func emit(_ element: T) {
    continuation.yield(element)
  }

  public func `throw`(_ error: any Error) {
    continuation.finish(throwing: error)
  }

  public func finish() {
    continuation.finish()
  }

  deinit {
    continuation.finish()
  }  
}
