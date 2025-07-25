import Atomics
import Foundation

actor AsyncReadWriteLock {
  private final class ReadTask: Sendable {
    let task: Task<Void, any Swift.Error>

    init(_ body: @Sendable @escaping () async throws -> Void) {
      task = Task {
        try await body()
      }
    }
  }

  private var currentReadTasks: [ObjectIdentifier: ReadTask] = [:]
  private var currentWriteTask: Task<Void, any Swift.Error>?

  func write(_ body: @Sendable @escaping () async throws -> Void) async throws {
    while currentWriteTask != nil || !currentReadTasks.isEmpty {
      await Task.yield()
      continue
    }

    defer { currentWriteTask = nil }
    let writeTask = Task {
      try await body()
    }
    currentWriteTask = writeTask

    try await writeTask.value
  }

  func read(_ body: @Sendable @escaping () async throws -> Void) async throws {
    while currentWriteTask != nil {
      await Task.yield()
      continue
    }

    let readTask = ReadTask(body)
    let taskID = ObjectIdentifier(readTask)
    defer {
      currentReadTasks[taskID] = nil
    }
    currentReadTasks[taskID] = readTask

    try await readTask.task.value
  }

}
