@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import Nimble
import SQLite3
import StarWarsAPI
import XCTest

@testable import Apollo
@testable import ApolloSQLite

class CachePersistenceTests: XCTestCase {

  func testFetchAndPersist() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
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

    let query = MockQuery<GivenSelectionSet>()
    let sqliteFileURL = SQLiteTestCacheProvider.temporarySQLiteFileURL()

    let (cache, tearDown) = await SQLiteTestCacheProvider.makeNormalizedCache(fileURL: sqliteFileURL)
    if let tearDown { self.addTeardownBlock(tearDown) }
    let store = ApolloStore(cache: cache)

    let server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(mockServer: server, store: store)

    let client = ApolloClient(networkTransport: networkTransport, store: store)

    _ = await server.expect(MockQuery<GivenSelectionSet>.self) { request in
      [
        "data": [
          "hero": [
            "name": "Luke Skywalker",
            "__typename": "Human",
          ]
        ]
      ]
    }

    let graphQLResult1 = try await client.fetch(query: query, cachePolicy: .networkOnly)

    XCTAssertEqual(graphQLResult1.data?.hero?.name, "Luke Skywalker")

    // Do another fetch from cache to ensure that data is cached before creating new cache
    let _ = try await client.fetch(query: query, cachePolicy: .cacheOnly)

    let (newCache, _) = await SQLiteTestCacheProvider.makeNormalizedCache(fileURL: sqliteFileURL)
    let newStore = ApolloStore(cache: newCache)
    let newClient = ApolloClient(networkTransport: networkTransport, store: newStore)

    let newClientResult = try await newClient.fetch(query: query, cachePolicy: .cacheOnly)

    XCTAssertEqual(newClientResult?.data?.hero?.name, "Luke Skywalker")
  }

  func testFetchAndPersistWithPeriodArguments() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self, arguments: ["text": .variable("term")])
        ]
      }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("name", String.self)
          ]
        }
      }
    }

    let query = MockQuery<GivenSelectionSet>()
    query.__variables = ["term": "Luke.Skywalker"]

    let sqliteFileURL = SQLiteTestCacheProvider.temporarySQLiteFileURL()

    let (cache, tearDown) = await SQLiteTestCacheProvider.makeNormalizedCache(fileURL: sqliteFileURL)
    if let tearDown { self.addTeardownBlock(tearDown) }
    let store = ApolloStore(cache: cache)

    let server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(mockServer: server, store: store)

    let client = ApolloClient(networkTransport: networkTransport, store: store)

    _ = await server.expect(MockQuery<GivenSelectionSet>.self) { request in
      [
        "data": [
          "hero": [
            "name": "Luke Skywalker",
            "__typename": "Human",
          ]
        ]
      ]
    }

    let graphQLResult = try await client.fetch(query: query, cachePolicy: .networkOnly)

    XCTAssertEqual(graphQLResult.data?.hero?.name, "Luke Skywalker")

    // Do another fetch from cache to ensure that data is cached before creating new cache
    _ = try await client.fetch(query: query, cachePolicy: .cacheOnly)

    let (newCache, _) = await SQLiteTestCacheProvider.makeNormalizedCache(fileURL: sqliteFileURL)
    let newStore = ApolloStore(cache: newCache)
    let newClient = ApolloClient(networkTransport: networkTransport, store: newStore)

    let newClientResult = try await newClient.fetch(query: query, cachePolicy: .cacheOnly)
    XCTAssertEqual(newClientResult?.data?.hero?.name, "Luke Skywalker")
  }

  func testClearCache() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
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

    let query = MockQuery<GivenSelectionSet>()
    let sqliteFileURL = SQLiteTestCacheProvider.temporarySQLiteFileURL()

    let (cache, tearDown) = await SQLiteTestCacheProvider.makeNormalizedCache(fileURL: sqliteFileURL)
    if let tearDown { self.addTeardownBlock(tearDown) }
    let store = ApolloStore(cache: cache)

    let server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(mockServer: server, store: store)

    let client = ApolloClient(networkTransport: networkTransport, store: store)

    _ = await server.expect(MockQuery<GivenSelectionSet>.self) { request in
      [
        "data": [
          "hero": [
            "name": "Luke Skywalker",
            "__typename": "Human",
          ]
        ]
      ]
    }

    let firstResult = try await client.fetch(query: query, cachePolicy: .networkOnly)

    XCTAssertEqual(firstResult.data?.hero?.name, "Luke Skywalker")

    try await client.clearCache()

    await expect { try await client.fetch(query: query, cachePolicy: .cacheOnly) }
      .to(beNil())
  }

}
