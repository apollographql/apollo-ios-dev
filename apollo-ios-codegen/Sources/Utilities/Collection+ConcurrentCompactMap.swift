import Foundation

extension Collection where Element: Sendable {

  /// Returns an array containing the non-nil results of calling the given transformation
  /// asynchronously with each element of this collection.
  ///
  /// Calls to the `transform` block will be made in a task group within the current task.
  ///
  /// Though the transformations will be called concurrently, the returned array is guaranteed to
  /// retain the order of the initial sequence.
  public func concurrentCompactMap<ElementOfResult: Sendable>(
    _ transform: @Sendable @escaping (Element) async throws -> ElementOfResult?
  ) async throws -> [ElementOfResult] {
    try await withThrowingTaskGroup(
      of: (Int, ElementOfResult?).self,
      returning: [ElementOfResult].self
    ) { group in
      var outputArray: [ElementOfResult?] = Array(repeating: nil, count: self.count)

      for (index, inputItem) in enumerated() {
        group.addTask {
          try Task.checkCancellation()
          return (index, try await transform(inputItem))
        }
      }

      for try await (index, outputItem) in group {
        outputArray[index] = outputItem
      }

      // Order preserved, optionals removed
      return outputArray.compactMap { $0 }
    }
  }

}
