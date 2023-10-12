import Foundation

extension Collection {

    public func concurrentCompactMap<ElementOfResult>(
      task: @escaping (Element) async throws -> ElementOfResult?
    ) async throws -> [ElementOfResult] {
        try await withThrowingTaskGroup(
          of: (Int, ElementOfResult?).self,
          returning: [ElementOfResult].self
        ) { group in
            var outputArray: [ElementOfResult?] = Array(repeating: nil, count: count)
            for (index, inputItem) in enumerated() {
              group.addTask {
                try Task.checkCancellation()
                return (index, try await task(inputItem))
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
