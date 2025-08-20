@_spi(Unsafe) import ApolloAPI
import ApolloInternalTestHelpers
import XCTest

@testable import Apollo

private final class MockBatchedNormalizedCache: NormalizedCache {
  private var records: RecordSet

  @Atomic var numberOfBatchLoads: Int32 = 0

  init(records: RecordSet) {
    self.records = records
  }

  public func loadRecords(forKeys keys: Set<CacheKey>) async throws -> [CacheKey: Record] {
    $numberOfBatchLoads.increment()

    try await Task.sleep(nanoseconds: 1_000_000)

    return keys.reduce(into: [:]) { results, key in
      results[key] = records[key]
    }
  }

  func removeRecord(for key: CacheKey) async throws {
    records.removeRecord(for: key)
  }

  func removeRecords(matching pattern: CacheKey) async throws {
    records.removeRecords(matching: pattern)
  }

  func merge(records: RecordSet) async throws -> Set<CacheKey> {
    try await Task.sleep(nanoseconds: 1_000_000)
    return self.records.merge(records: records)
  }

  func clear() async throws {
    try await Task.sleep(nanoseconds: 1_000_000)
    records.clear()
  }
}

class ApolloStore_BatchedLoadTests: XCTestCase {
  func testListsAreLoadedInASingleBatch() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("name", String.self),
            ]
          }

          var name: String { __data["name"] }
        }
      }
    }

    var records = RecordSet()
    let drones = (1...100).map { number in
      Record(key: "Drone_\(number)", ["__typename": "Droid", "name": "Droid #\(number)"])
    }

    records.insert(Record(key: "QUERY_ROOT", ["hero": CacheReference("2001")]))
    records.insert(
      Record(
        key: "2001",
        [
          "name": "R2-D2",
          "__typename": "Droid",
          "friends": drones.map { CacheReference($0.key) },
        ]
      )
    )
    records.insert(contentsOf: drones)

    let cache = MockBatchedNormalizedCache(records: records)
    let store = ApolloStore(cache: cache)

    let query = MockQuery<GivenSelectionSet>()

    // when
    let graphQLResult = try await store.load(query)

    XCTAssertNil(graphQLResult?.errors)

    guard let data = graphQLResult?.data else {
      XCTFail("No data returned with result!")
      return
    }

    XCTAssertEqual(data.hero?.name, "R2-D2")
    XCTAssertEqual(data.hero?.friends?.count, 100)

    // 3 loads: ROOT_QUERY.hero, hero.friends, list of friends
    XCTAssertEqual(cache.numberOfBatchLoads, 3)
  }

  func testParallelLoadsUseIndependentBatching() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      var hero: Hero? { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
            .field("friends", [Friend]?.self),
          ]
        }

        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("name", String.self),
            ]
          }

          var name: String { __data["name"] }
        }
      }
    }

    let records: RecordSet = [
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": [
          CacheReference("1000"),
          CacheReference("1002"),
          CacheReference("1003"),
        ],
      ],
      "1000": ["__typename": "Human", "name": "Luke Skywalker"],
      "1002": ["__typename": "Human", "name": "Han Solo"],
      "1003": ["__typename": "Human", "name": "Leia Organa"],
    ]

    let cache = MockBatchedNormalizedCache(records: records)
    let store = ApolloStore(cache: cache)

    let query = MockQuery<GivenSelectionSet>()

    try await withThrowingTaskGroup { group in
      for _ in (1...10) {
        group.addTask {
          let graphQLResult = try await store.load(query)

          XCTAssertNil(graphQLResult?.errors)

          guard let data = graphQLResult?.data else {
            XCTFail("No data returned with query!")
            return

          }
          XCTAssertEqual(data.hero?.name, "R2-D2")
          let friendsNames = data.hero?.friends?.compactMap { $0.name }
          XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
        }
      }
      try await group.waitForAll()
    }

    // then
    XCTAssertEqual(cache.numberOfBatchLoads, 30)
  }
}
