import XCTest
@testable import Apollo
import ApolloAPI
@testable import ApolloSQLite
import ApolloInternalTestHelpers
import SQLite3
import StarWarsAPI

class CachePersistenceTests: XCTestCase {

  func testFetchAndPersist() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<GivenSelectionSet>()
    let sqliteFileURL = SQLiteTestCacheProvider.temporarySQLiteFileURL()

    let (cache, tearDown) = await SQLiteTestCacheProvider.makeNormalizedCache(fileURL: sqliteFileURL)
    if let tearDown { self.addTeardownBlock(tearDown) }
    let store = ApolloStore(cache: cache)

    let server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(server: server, store: store)

    let client = ApolloClient(networkTransport: networkTransport, store: store)

    _ = server.expect(MockQuery<GivenSelectionSet>.self) { request in
      [
        "data": [
          "hero": [
            "name": "Luke Skywalker",
            "__typename": "Human"
          ]
        ]
      ]
    }

    let networkExpectation = self.expectation(description: "Fetching query from network")
    let newCacheExpectation = self.expectation(description: "Fetch query from new cache")

    client.fetch(query: query, cachePolicy: .fetchIgnoringCacheData) { outerResult in
      defer { networkExpectation.fulfill() }

      switch outerResult {
      case .failure(let error):
        XCTFail("Unexpected error: \(error)")
        return
      case .success(let graphQLResult):
        XCTAssertEqual(graphQLResult.data?.hero?.name, "Luke Skywalker")

        // Do another fetch from cache to ensure that data is cached before creating new cache
        client.fetch(query: query, cachePolicy: .returnCacheDataDontFetch) { innerResult in
          Task {
            let (cache, _) = await SQLiteTestCacheProvider.makeNormalizedCache(fileURL: sqliteFileURL)
            let newStore = ApolloStore(cache: cache)
            let newClient = ApolloClient(networkTransport: networkTransport, store: newStore)

            newClient.fetch(query: query, cachePolicy: .returnCacheDataDontFetch) { newClientResult in
              defer { newCacheExpectation.fulfill() }
              switch newClientResult {
              case .success(let newClientGraphQLResult):
                XCTAssertEqual(newClientGraphQLResult.data?.hero?.name, "Luke Skywalker")
              case .failure(let error):
                XCTFail("Unexpected error with new client: \(error)")
              }
              _ = newClient // Workaround for a bug - ensure that newClient is retained until this block is run
            }
          }

        }
      }
    }

    await fulfillment(of: [networkExpectation, newCacheExpectation], timeout: 2)
  }

  func testFetchAndPersistWithPeriodArguments() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["text": .variable("term")])
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<GivenSelectionSet>()
    query.__variables = ["term": "Luke.Skywalker"]

    let sqliteFileURL = SQLiteTestCacheProvider.temporarySQLiteFileURL()

    let (cache, tearDown) = await SQLiteTestCacheProvider.makeNormalizedCache(fileURL: sqliteFileURL)
    if let tearDown { self.addTeardownBlock(tearDown) }
    let store = ApolloStore(cache: cache)

    let server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(server: server, store: store)

    let client = ApolloClient(networkTransport: networkTransport, store: store)

    _ = server.expect(MockQuery<GivenSelectionSet>.self) { request in
      [
        "data": [
          "hero": [
            "name": "Luke Skywalker",
            "__typename": "Human"
          ]
        ]
      ]
    }

    let networkExpectation = self.expectation(description: "Fetching query from network")
    let newCacheExpectation = self.expectation(description: "Fetch query from new cache")

    client.fetch(query: query, cachePolicy: .fetchIgnoringCacheData) { outerResult in
      defer { networkExpectation.fulfill() }

      switch outerResult {
      case .failure(let error):
        XCTFail("Unexpected error: \(error)")
        return
      case .success(let graphQLResult):
        XCTAssertEqual(graphQLResult.data?.hero?.name, "Luke Skywalker")

        // Do another fetch from cache to ensure that data is cached before creating new cache
        client.fetch(query: query, cachePolicy: .returnCacheDataDontFetch) { innerResult in
          Task {
            let (cache, _) = await SQLiteTestCacheProvider.makeNormalizedCache(fileURL: sqliteFileURL)
            let newStore = ApolloStore(cache: cache)
            let newClient = ApolloClient(networkTransport: networkTransport, store: newStore)

            newClient.fetch(query: query, cachePolicy: .returnCacheDataDontFetch) { newClientResult in
              defer { newCacheExpectation.fulfill() }
              switch newClientResult {
              case .success(let newClientGraphQLResult):
                XCTAssertEqual(newClientGraphQLResult.data?.hero?.name, "Luke Skywalker")
              case .failure(let error):
                XCTFail("Unexpected error with new client: \(error)")
              }
              _ = newClient // Workaround for a bug - ensure that newClient is retained until this block is run
            }
          }
        }
      }
    }

    await fulfillment(of: [networkExpectation, newCacheExpectation], timeout: 2)
  }

  func testClearCache() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<GivenSelectionSet>()
    let sqliteFileURL = SQLiteTestCacheProvider.temporarySQLiteFileURL()

    let (cache, tearDown) = await SQLiteTestCacheProvider.makeNormalizedCache(fileURL: sqliteFileURL)
    if let tearDown { self.addTeardownBlock(tearDown) }
    let store = ApolloStore(cache: cache)

    let server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(server: server, store: store)

    let client = ApolloClient(networkTransport: networkTransport, store: store)

    _ = server.expect(MockQuery<GivenSelectionSet>.self) { request in
      [
        "data": [
          "hero": [
            "name": "Luke Skywalker",
            "__typename": "Human"
          ]
        ]
      ]
    }

    let networkExpectation = self.expectation(description: "Fetching query from network")
    let emptyCacheExpectation = self.expectation(description: "Fetch query from empty cache")
    let cacheClearExpectation = self.expectation(description: "cache cleared")

    client.fetch(query: query, cachePolicy: .fetchIgnoringCacheData) { outerResult in
      defer { networkExpectation.fulfill() }

      switch outerResult {
      case .failure(let error):
        XCTFail("Unexpected failure: \(error)")
      case .success(let graphQLResult):
        XCTAssertEqual(graphQLResult.data?.hero?.name, "Luke Skywalker")
      }

      client.clearCache(completion: { result in
        defer { cacheClearExpectation.fulfill() }
        switch result {
        case .success:
          break
        case .failure(let error):
          XCTFail("Error clearing cache: \(error)")
        }

        client.fetch(query: query, cachePolicy: .returnCacheDataDontFetch) { innerResult in
          defer { emptyCacheExpectation.fulfill() }

          switch innerResult {
          case .success:
            XCTFail("This should have returned an error")
          case .failure(let error):
            if let resultError = error as? GraphQLExecutionError {
              switch resultError.underlying {
              case .missingValue:
                // Correct error!
                break
              default:
                XCTFail("Unexpected JSON error: \(error)")
              }
            } else {
              XCTFail("Unexpected error: \(error)")
            }
          }
        }
      })
    }

    await fulfillment(
      of: [networkExpectation, emptyCacheExpectation, cacheClearExpectation],
      timeout: 2
    )
  }

}
