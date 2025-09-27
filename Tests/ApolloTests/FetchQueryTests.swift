@_spi(Execution) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable @_spi(Execution) import Apollo

class FetchQueryTests: XCTestCase, CacheDependentTesting {

  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  static let defaultWaitTimeout: TimeInterval = 1

  var store: ApolloStore!
  var server: MockGraphQLServer!
  var client: ApolloClient!

  override func setUp() async throws {
    try await super.setUp()

    store = try await makeTestStore()

    server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(mockServer: server, store: store)

    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  override func tearDownWithError() throws {
    store = nil
    server = nil
    client = nil

    try super.tearDownWithError()
  }

  func test__fetch__givenCachePolicy_networkOnly_onlyHitsNetwork() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()

    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ],
    ])

    let serverRequestExpectation =
      await server.expect(MockQuery<HeroNameSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "Luke Skywalker",
              "__typename": "Human",
            ]
          ]
        ]
      }

    let result = try await client.fetch(query: query, cachePolicy: .networkOnly)

    XCTAssertEqual(result.source, .server)
    XCTAssertNil(result.errors)

    let data = try XCTUnwrap(result.data)
    XCTAssertEqual(data.hero?.name, "Luke Skywalker")

    await fulfillment(of: [serverRequestExpectation], timeout: Self.defaultWaitTimeout)
  }

  func test__fetch__givenCachePolicy_cacheAndNetwork_hitsCacheFirstAndNetworkAfter() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()

    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ],
    ])

    let serverRequestExpectation =
      await server.expect(MockQuery<HeroNameSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "Luke Skywalker",
              "__typename": "Human",
            ]
          ]
        ]
      }

    let results = try await client.fetch(query: query, cachePolicy: .cacheAndNetwork).getAllValues()

    expect(results.count).to(equal(2))

    let cacheResult = results[0]
    XCTAssertEqual(cacheResult.source, .cache)
    XCTAssertNil(cacheResult.errors)

    let cacheResultData = try XCTUnwrap(cacheResult.data)
    XCTAssertEqual(cacheResultData.hero?.name, "R2-D2")

    let networkResult = results[1]
    XCTAssertEqual(networkResult.source, .server)
    XCTAssertNil(networkResult.errors)

    let networkResultData = try XCTUnwrap(networkResult.data)
    XCTAssertEqual(networkResultData.hero?.name, "Luke Skywalker")

    await fulfillment(
      of: [serverRequestExpectation],
      timeout: Self.defaultWaitTimeout
    )
  }

  func test__fetch__givenCachePolicy_cacheFirst_givenDataIsCached_doesntHitNetwork() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()

    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ],
    ])

    let result = try await client.fetch(query: query, cachePolicy: .cacheFirst)

    XCTAssertEqual(result.source, .cache)
    XCTAssertNil(result.errors)

    let data = try XCTUnwrap(result.data)
    XCTAssertEqual(data.hero?.name, "R2-D2")
  }

  func test__fetch__givenCachePolicy_cacheFirst_givenNotAllDataIsCached_hitsNetwork() async throws {
    class HeroNameAndAppearsInSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
            .field("appearsIn", [String]?.self),
          ]
        }
      }
    }

    let query = MockQuery<HeroNameAndAppearsInSelectionSet>()

    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ],
    ])

    let serverRequestExpectation =
      await server.expect(MockQuery<HeroNameAndAppearsInSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "R2-D2",
              "appearsIn": ["NEWHOPE", "EMPIRE", "JEDI"],
              "__typename": "Droid",
            ]
          ] as JSONValue
        ]
      }

    let result = try await client.fetch(query: query, cachePolicy: .cacheFirst)

    XCTAssertEqual(result.source, .server)
    XCTAssertNil(result.errors)

    let data = try XCTUnwrap(result.data)
    XCTAssertEqual(data.hero?.name, "R2-D2")
    XCTAssertEqual(data.hero?.appearsIn, ["NEWHOPE", "EMPIRE", "JEDI"])

    await fulfillment(
      of: [serverRequestExpectation],
      timeout: Self.defaultWaitTimeout
    )
  }

  func test__fetch__givenCachePolicy_returnCacheOnly_givenDataIsCached_doesntHitNetwork() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()

    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ],
    ])

    let result = try await client.fetch(query: query, cachePolicy: .cacheOnly)

    XCTAssertEqual(result?.source, .cache)
    XCTAssertNil(result?.errors)

    let data = try XCTUnwrap(result?.data)
    XCTAssertEqual(data.hero?.name, "R2-D2")
  }

  func test__fetch__givenCachePolicy_cacheOnly_givenNotAllDataIsCached_returnsNil() async throws {
    class HeroNameAndAppearsInSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
            .field("appearsIn", [String]?.self),
          ]
        }
      }
    }

    let query = MockQuery<HeroNameAndAppearsInSelectionSet>()

    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ],
    ])

    let result = try await client.fetch(query: query, cachePolicy: .cacheOnly)

    // cache miss
    expect(result).to(beNil())
  }

  func test__fetch_afterClearCache_givenCachePolicy_cacheOnly_returnsNil() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
          ]
        }
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()

    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ],
    ])

    let firstResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)

    XCTAssertEqual(firstResult?.source, .cache)
    XCTAssertNil(firstResult?.errors)

    let data = try XCTUnwrap(firstResult?.data)
    XCTAssertEqual(data.hero?.name, "R2-D2")

    // Clear the cache
    try await client.clearCache()

    // Fetch from cache and expect cache miss failure
    let cacheMissResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)

    expect(cacheMissResult).to(beNil())
  }

}
