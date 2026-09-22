@_spi(Execution) import Apollo
@_spi(Execution) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import Foundation
import XCTest

/// Tier 1 — `ApolloClient.fetch` end-to-end benchmarks. See
/// `apollo-ios/Design/cache-rewrite-phase1-perf.md` §2.1 for scenario definitions.
///
/// Drives a single small query (`HeroNameQuery`) through each cache policy and
/// measures wall-clock latency from call to result delivery. The mock server's
/// random delay is zeroed so the measurement reflects cache + executor cost,
/// not artificial network jitter.
final class Tier1FetchBenchmarks: XCTestCase {

  static let measuredIterations = 50

  /// Shared selection set for all Tier 1 scenarios — keeps the comparison
  /// clean by holding query shape constant across cache policies.
  final class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
    override class var __selections: [Selection] {
      [.field("hero", Hero.self)]
    }

    final class Hero: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("name", String.self),
        ]
      }
    }
  }

  /// Build a fresh store + client + mock server for one benchmark scenario.
  private func makeTestRig() async -> (store: ApolloStore, server: MockGraphQLServer, client: ApolloClient) {
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    let server = MockGraphQLServer()
    await server.setDelay(milliseconds: 0)
    let transport = MockNetworkTransport(mockServer: server, store: store)
    let client = ApolloClient(networkTransport: transport, store: store)
    return (store, server, client)
  }

  /// Standard fixture response — identical shape across scenarios so the
  /// network/parse cost is comparable.
  private static let fixtureResponse: JSONObject = [
    "data": [
      "hero": [
        "__typename": "Droid",
        "name": "R2-D2",
      ]
    ]
  ]

  /// Pre-populated cache records that satisfy `HeroNameSelectionSet`.
  private static let fixtureRecords: RecordSet = [
    "QUERY_ROOT": ["hero": CacheReference("hero")],
    "hero": [
      "__typename": "Droid",
      "name": "R2-D2",
    ],
  ]

  // MARK: - Scenario 1: cold cache, network only

  func test__tier1__cold_cache_network_only() async throws {
    let (_, server, client) = await makeTestRig()

    let harness = BenchmarkHarness(
      scenario: "tier1.cold_cache_network_only",
      tier: 1,
      measuredIterations: Self.measuredIterations
    )
    let expectation = await server.expect(MockQuery<HeroNameSelectionSet>.self) { @Sendable _ in
      Self.fixtureResponse
    }
    expectation.expectedFulfillmentCount = harness.warmupIterations + harness.measuredIterations
    expectation.assertForOverFulfill = false

    _ = try await harness.measure { _ in
      let query = MockQuery<HeroNameSelectionSet>()
      _ = try await client.fetch(query: query, cachePolicy: .networkOnly)
    }
  }

  // MARK: - Scenario 2: warm cache, cache-first hit

  func test__tier1__warm_cache_first_hit() async throws {
    let (store, _, client) = await makeTestRig()
    try await store.publish(records: Self.fixtureRecords)

    let harness = BenchmarkHarness(
      scenario: "tier1.warm_cache_first_hit",
      tier: 1,
      measuredIterations: Self.measuredIterations
    )
    _ = try await harness.measure { _ in
      let query = MockQuery<HeroNameSelectionSet>()
      _ = try await client.fetch(query: query, cachePolicy: .cacheFirst)
    }
  }

  // MARK: - Scenario 3: cache-first miss falling back to network

  func test__tier1__cache_first_miss_falls_back_to_network() async throws {
    let (store, server, client) = await makeTestRig()

    // Pre-populate the cache *without* the requested field so every iteration
    // hits the cache, misses, falls back to network, and writes the new value.
    let partialRecords: RecordSet = [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      // `hero` record exists but lacks `name` — the executor will treat
      // `name` as a missing-field cache miss.
      "hero": ["__typename": "Droid"],
    ]
    try await store.publish(records: partialRecords)

    let harness = BenchmarkHarness(
      scenario: "tier1.cache_first_miss_network_fallback",
      tier: 1,
      measuredIterations: Self.measuredIterations
    )
    let expectation = await server.expect(MockQuery<HeroNameSelectionSet>.self) { @Sendable _ in
      Self.fixtureResponse
    }
    expectation.expectedFulfillmentCount = harness.warmupIterations + harness.measuredIterations
    expectation.assertForOverFulfill = false
    _ = try await harness.measure(
      setup: { _ in
        // Restore the partial-record state each iteration: the previous
        // iteration's network fallback wrote the full record back, so we
        // need to clear and re-seed to keep the scenario consistent.
        try await store.clearCache()
        try await store.publish(records: partialRecords)
      },
      body: { _ in
        let query = MockQuery<HeroNameSelectionSet>()
        _ = try await client.fetch(query: query, cachePolicy: .cacheFirst)
      }
    )
  }

  // MARK: - Scenario 4: cacheAndNetwork — stream both responses

  func test__tier1__cache_and_network() async throws {
    let (store, server, client) = await makeTestRig()
    try await store.publish(records: Self.fixtureRecords)

    let harness = BenchmarkHarness(
      scenario: "tier1.cache_and_network",
      tier: 1,
      measuredIterations: Self.measuredIterations
    )
    let expectation = await server.expect(MockQuery<HeroNameSelectionSet>.self) { @Sendable _ in
      Self.fixtureResponse
    }
    expectation.expectedFulfillmentCount = harness.warmupIterations + harness.measuredIterations
    expectation.assertForOverFulfill = false
    _ = try await harness.measure { _ in
      let query = MockQuery<HeroNameSelectionSet>()
      var deliveries = 0
      for try await _ in try client.fetch(query: query, cachePolicy: .cacheAndNetwork) {
        deliveries += 1
      }
      // Both responses (cache + network) must arrive for this scenario to
      // be measured correctly. Assert as a guard, not a perf assertion.
      XCTAssertEqual(deliveries, 2, "cacheAndNetwork must yield exactly two responses")
    }
  }

  // MARK: - Scenario 5: warm cache, single ref hop (nested object)
  //
  // Exercises CacheReference resolution: QUERY_ROOT → hero → bestFriend.
  // Two cache records resolved across two batched loads (one for hero,
  // one for the single bestFriend reference). Compares against the flat
  // `warm_cache_first_hit` scenario to surface the cost of one ref hop.

  final class NestedHeroSelectionSet: MockSelectionSet, @unchecked Sendable {
    override class var __selections: [Selection] {
      [.field("hero", Hero.self)]
    }

    final class Hero: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("name", String.self),
          .field("bestFriend", BestFriend.self),
        ]
      }

      final class BestFriend: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }
  }

  private static let nestedFixtureRecords: RecordSet = [
    "QUERY_ROOT": ["hero": CacheReference("hero")],
    "hero": [
      "__typename": "Droid",
      "name": "R2-D2",
      "bestFriend": CacheReference("bestFriend"),
    ],
    "bestFriend": [
      "__typename": "Human",
      "name": "Luke Skywalker",
    ],
  ]

  func test__tier1__warm_cache_first_hit_nested_object() async throws {
    let (store, _, client) = await makeTestRig()
    try await store.publish(records: Self.nestedFixtureRecords)

    let harness = BenchmarkHarness(
      scenario: "tier1.warm_cache_first_hit_nested_object",
      tier: 1,
      measuredIterations: Self.measuredIterations
    )
    _ = try await harness.measure { _ in
      let query = MockQuery<NestedHeroSelectionSet>()
      _ = try await client.fetch(query: query, cachePolicy: .cacheFirst)
    }
  }

  // MARK: - Scenario 6: warm cache, 1:N array of refs
  //
  // Exercises the batched-load path: hero.friends is an array of 20
  // CacheReferences, all resolved in a single batched loadRecords call.
  // Realistic shape for paginated list queries.

  static let friendsCount = 20

  final class HeroWithFriendsSelectionSet: MockSelectionSet, @unchecked Sendable {
    override class var __selections: [Selection] {
      [.field("hero", Hero.self)]
    }

    final class Hero: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend]?.self),
        ]
      }

      final class Friend: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }
  }

  private static func arrayOfRefsFixture() -> RecordSet {
    var records: RecordSet = [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "__typename": "Droid",
        "name": "R2-D2",
        "friends": (0..<friendsCount).map { CacheReference("friend_\($0)") },
      ],
    ]
    for i in 0..<friendsCount {
      records.insert(Record(key: "friend_\(i)", [
        "__typename": "Human",
        "name": "Friend \(i)",
      ]))
    }
    return records
  }

  func test__tier1__warm_cache_first_hit_array_of_refs() async throws {
    let (store, _, client) = await makeTestRig()
    try await store.publish(records: Self.arrayOfRefsFixture())

    let harness = BenchmarkHarness(
      scenario: "tier1.warm_cache_first_hit_array_of_refs_20",
      tier: 1,
      measuredIterations: Self.measuredIterations
    )
    _ = try await harness.measure { _ in
      let query = MockQuery<HeroWithFriendsSelectionSet>()
      _ = try await client.fetch(query: query, cachePolicy: .cacheFirst)
    }
  }

  // MARK: - Scenario 7: warm cache, N:M shared records (dedup payoff)
  //
  // 20 friends each reference one of 3 shared homeworlds. The executor's
  // ref-resolution dedup should batch-load 3 unique homeworld records
  // rather than 20 — this is THE normalization payoff Apollo's cache
  // exists for, and it's worth measuring against a 3.0 baseline.

  static let homeworldKeys = ["tatooine", "alderaan", "naboo"]

  final class HeroWithFriendsAndHomeworldSelectionSet: MockSelectionSet, @unchecked Sendable {
    override class var __selections: [Selection] {
      [.field("hero", Hero.self)]
    }

    final class Hero: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend]?.self),
        ]
      }

      final class Friend: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
            .field("homeworld", Homeworld.self),
          ]
        }

        final class Homeworld: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("name", String.self),
            ]
          }
        }
      }
    }
  }

  private static func sharedRecordsFixture() -> RecordSet {
    var records: RecordSet = [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "__typename": "Droid",
        "name": "R2-D2",
        "friends": (0..<friendsCount).map { CacheReference("friend_\($0)") },
      ],
    ]
    for i in 0..<friendsCount {
      let homeworldKey = "homeworld_\(homeworldKeys[i % homeworldKeys.count])"
      records.insert(Record(key: "friend_\(i)", [
        "__typename": "Human",
        "name": "Friend \(i)",
        "homeworld": CacheReference(homeworldKey),
      ]))
    }
    let planetNames = ["Tatooine", "Alderaan", "Naboo"]
    for (i, key) in homeworldKeys.enumerated() {
      records.insert(Record(key: "homeworld_\(key)", [
        "__typename": "Planet",
        "name": planetNames[i],
      ]))
    }
    return records
  }

  func test__tier1__warm_cache_first_hit_shared_records() async throws {
    let (store, _, client) = await makeTestRig()
    try await store.publish(records: Self.sharedRecordsFixture())

    let harness = BenchmarkHarness(
      scenario: "tier1.warm_cache_first_hit_shared_records_20_friends_3_homeworlds",
      tier: 1,
      measuredIterations: Self.measuredIterations
    )
    _ = try await harness.measure { _ in
      let query = MockQuery<HeroWithFriendsAndHomeworldSelectionSet>()
      _ = try await client.fetch(query: query, cachePolicy: .cacheFirst)
    }
  }
}

