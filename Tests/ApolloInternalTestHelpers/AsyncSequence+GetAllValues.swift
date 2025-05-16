import Foundation

public extension AsyncSequence {

  /// Waits for all values from an async sequence and then returns them as a single array.
  func getAllValues() async throws -> [Element] {
    var values = [Element]()
    for try await value in self {
      values.append(value)
    }
    return values
  }
}
