import Foundation
import Nimble
import XCTest
@testable import Apollo

final class AsyncReadWriteLockTests: XCTestCase {

  func testWakingReadBatch__withMixedPriorityReaders__writesDoNotOverlapReadsOrWrites() async throws {
    let tracker = AccessTracker()

    for _ in 0..<50 {
      let lock = AsyncReadWriteLock()
      var tasks: [Task<Void, Never>] = []

      // Hold the write lock so the readers below queue together in one batch.
      tasks.append(Task.detached(priority: .high) {
        try? await lock.write { tracker.write { usleep(5_000) } }
      })
      try await Task.sleep(nanoseconds: 1_000_000)

      tasks.append(Task.detached(priority: .background) {
        try? await lock.read { tracker.read { usleep(2_000) } }
      })
      tasks.append(Task.detached(priority: .userInitiated) {
        try? await lock.read { tracker.read {} }
      })
      try await Task.sleep(nanoseconds: 500_000)

      for _ in 0..<2 {
        tasks.append(Task.detached(priority: .high) {
          try? await lock.write { tracker.write { usleep(2_000) } }
        })
      }
      try await Task.sleep(nanoseconds: 500_000)

      // Keep the actor busy so the background reader resumes after the high priority reader finishes.
      for _ in 0..<50 {
        tasks.append(Task.detached(priority: .userInitiated) {
          try? await lock.read { tracker.read {} }
        })
      }

      for task in tasks {
        await task.value
      }
    }

    expect(tracker.overlapCount).to(equal(0))
  }

}

private final class AccessTracker: @unchecked Sendable {
  private let lock = NSLock()
  private var readers = 0
  private var writers = 0
  private var overlaps = 0

  var overlapCount: Int {
    lock.withLock { overlaps }
  }

  func read(_ body: () -> Void) {
    lock.withLock {
      if writers > 0 { overlaps += 1 }
      readers += 1
    }
    body()
    lock.withLock { readers -= 1 }
  }

  func write(_ body: () -> Void) {
    lock.withLock {
      if writers > 0 || readers > 0 { overlaps += 1 }
      writers += 1
    }
    body()
    lock.withLock { writers -= 1 }
  }
}
