import XCTest
@_spi(Execution) @testable import Apollo
import ApolloInternalTestHelpers

class DataLoaderTests: XCTestCase {
  func testSingleLoad() async throws {
    let loader = DataLoader<Int, String> { keys in
      return self.wordsForNumbers(keys)
    }
    let actual = try await loader[1].get()
    XCTAssertEqual(actual, "one")
  }
  
  func testMultipleLoads() async throws {
    var numberOfBatchLoads = 0
    
    let loader = DataLoader<Int, String> { keys in
      numberOfBatchLoads += 1
      return self.wordsForNumbers(keys)
    }
        
    let results = [loader[1], loader[2]]
    let values = try await results.asyncMap { try await $0.get() }

    XCTAssertEqual(values, ["one", "two"])
    XCTAssertEqual(numberOfBatchLoads, 1)
  }
  
  func testCoalescesIdenticalRequests() async throws {
    var batchLoads: [Set<Int>] = []
    
    let loader = DataLoader<Int, String> { keys in
      batchLoads.append(keys)
      return self.wordsForNumbers(keys)
    }
        
    let results = [loader[1], loader[1]]
    let values = try await results.asyncMap { try await $0.get() }

    XCTAssertEqual(values, ["one", "one"])
    XCTAssertEqual(batchLoads.count, 1)
    XCTAssertEqual(batchLoads[0], [1])
  }
  
  func testCachesRepeatedRequests() async throws {
    var batchLoads: [Set<Int>] = []
    
    let loader = DataLoader<Int, String> { keys in
      batchLoads.append(keys)
      return self.wordsForNumbers(keys)
    }
        
    let results1 = [loader[1], loader[2]]
    let values1 = try await results1.asyncMap { try await $0.get() }

    XCTAssertEqual(values1, ["one", "two"])
    XCTAssertEqual(batchLoads.count, 1)
    XCTAssertEqualUnordered(batchLoads[0], [1, 2])
        
    let results2 = [loader[1], loader[3]]
    let values2 = try await results2.asyncMap { try await $0.get() }

    XCTAssertEqual(values2, ["one", "three"])
    XCTAssertEqual(batchLoads.count, 2)
    XCTAssertEqual(batchLoads[1], [3])
    
    let results3 = [loader[1], loader[2], loader[3]]
    let values3 = try await results3.asyncMap { try await $0.get() }

    XCTAssertEqual(values3, ["one", "two", "three"])
    XCTAssertEqual(batchLoads.count, 2)
  }
  
  // - Helpers
  
  private func wordsForNumbers(_ keys: Set<Int>) -> [Int: String] {
    let formatter = NumberFormatter()
    formatter.numberStyle = .spellOut
    
    return keys.reduce(into: [:]) { result, key in
      result[key] = formatter.string(from: key as NSNumber)
    }
  }
}
