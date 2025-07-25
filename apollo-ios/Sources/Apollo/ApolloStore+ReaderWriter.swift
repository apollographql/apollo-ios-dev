import Foundation
import Atomics


extension ApolloStore {
  final class ReaderWriter: @unchecked Sendable {

    /// Atomic counter for number of current readers.
    /// While writing, this will have a value of `WRITING`
    @Atomic private var readerCount = 0

    /// Value for `readerCount` while in writing state
    private static let WRITING = -1

    // MARK: - Read

    func read(_ body: () async throws -> Void) async rethrows {
      await beginReading()
      defer { finishReading() }

      try await body()
    }

    private func beginReading() async {
      while true {
        let currentReaderCount = readerCount

        guard currentReaderCount != Self.WRITING else {
          await Task.yield()
          continue
        }

        $readerCount.increment()
        return
      }
    }

    private func finishReading() {
      $readerCount.decrement()
    }

    // MARK: - Write
    func write(_ body: () async throws -> Void) async rethrows {
      await beginWriting()
      defer { finishWriting() }
      try await body()
    }

    private func beginWriting() async {
      while true {
        let currentReaderCount = readerCount
        guard currentReaderCount == 0 else {
          await Task.yield()
          continue
        }

        $readerCount.mutate { value in
          value = Self.WRITING
        }
        return
      }
    }

    func finishWriting() {
      $readerCount.mutate { value in
        value = 0
      }
    }
  }
}
