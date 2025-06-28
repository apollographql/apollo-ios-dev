import XCTest
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

class FetchQueryTests: XCTestCase, CacheDependentTesting {
  
  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }
  
  static let defaultWaitTimeout: TimeInterval = 1
  
  var cache: (any NormalizedCache)!
  var server: MockGraphQLServer!
  var client: ApolloClient!
  
  override func setUp() async throws {
    try await super.setUp()

    cache = try await makeNormalizedCache()
    let store = ApolloStore(cache: cache)
    
    server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(mockServer: server, store: store)

    client = ApolloClient(networkTransport: networkTransport, store: store)
  }
  
  override func tearDownWithError() throws {
    cache = nil
    server = nil
    client = nil
    
    try super.tearDownWithError()
  }
  
  func test__fetch__givenCachePolicy_fetchIgnoringCacheData_onlyHitsNetwork() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()
    
    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ]
    ])
    
    let serverRequestExpectation =
    await server.expect(MockQuery<HeroNameSelectionSet>.self) { request in
      [
        "data": [
          "hero": [
            "name": "Luke Skywalker",
            "__typename": "Human"
          ]
        ]
      ]
    }
    
    let resultObserver = makeResultObserver(for: query)
    
    let fetchResultFromServerExpectation = resultObserver.expectation(
      description: "Received result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "Luke Skywalker")
      }
    }
    
    client.fetch(query: query, cachePolicy: .fetchIgnoringCacheData, resultHandler: resultObserver.handler)
    
    await fulfillment(of: [serverRequestExpectation, fetchResultFromServerExpectation], timeout: Self.defaultWaitTimeout)
  }
  
  func test__fetch__givenCachePolicy_returnCacheDataAndFetch_hitsCacheFirstAndNetworkAfter() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()
    
    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ]
    ])
    
    let serverRequestExpectation =
    await server.expect(MockQuery<HeroNameSelectionSet>.self) { request in
      [
        "data": [
          "hero": [
            "name": "Luke Skywalker",
            "__typename": "Human"
          ]
        ]
      ]
    }
    
    let resultObserver = makeResultObserver(for: query)
    
    let fetchResultFromCacheExpectation = resultObserver.expectation(
      description: "Received result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }
    
    let fetchResultFromServerExpectation = resultObserver.expectation(
      description: "Received result from server"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "Luke Skywalker")
      }
    }
    
    client.fetch(query: query, cachePolicy: .returnCacheDataAndFetch, resultHandler: resultObserver.handler)
    
    await fulfillment(of: [fetchResultFromCacheExpectation, serverRequestExpectation, fetchResultFromServerExpectation], timeout: Self.defaultWaitTimeout)
  }
  
  func test__fetch__givenCachePolicy_returnCacheDataElseFetch_givenDataIsCached_doesntHitNetwork() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()
    
    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ]
    ])
    
    let resultObserver = makeResultObserver(for: query)
    
    let fetchResultFromCacheExpectation = resultObserver.expectation(
      description: "Received result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }
    
    client.fetch(query: query,
                 cachePolicy: .returnCacheDataElseFetch,
                 resultHandler: resultObserver.handler)
    
    await fulfillment(of: [fetchResultFromCacheExpectation], timeout: Self.defaultWaitTimeout)
  }
  
  func test__fetch__givenCachePolicy_returnCacheDataElseFetch_givenNotAllDataIsCached_hitsNetwork() async throws {
    class HeroNameAndAppearsInSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("appearsIn", [String]?.self)
        ]}
      }
    }

    let query = MockQuery<HeroNameAndAppearsInSelectionSet>()
    
    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid"
      ]
    ])
    
    let serverRequestExpectation =
    await server.expect(MockQuery<HeroNameAndAppearsInSelectionSet>.self) { request in
      [
        "data": [
          "hero": [
            "name": "R2-D2",
            "appearsIn": ["NEWHOPE", "EMPIRE", "JEDI"],
            "__typename": "Droid"
          ]
        ] as JSONValue
      ]
    }
    
    let resultObserver = makeResultObserver(for: query)
    
    let fetchResultFromServerExpectation = resultObserver.expectation(description: "Received result from server") { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .server)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
        XCTAssertEqual(data.hero?.appearsIn, ["NEWHOPE", "EMPIRE", "JEDI"])
      }
    }
    
    client.fetch(query: query, cachePolicy: .returnCacheDataAndFetch, resultHandler: resultObserver.handler)
    
    await fulfillment(of: [serverRequestExpectation, fetchResultFromServerExpectation], timeout: Self.defaultWaitTimeout)
  }
  
  func test__fetch__givenCachePolicy_returnCacheDataDontFetch_givenDataIsCached_doesntHitNetwork() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()
    
    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ]
    ])
    
    let resultObserver = makeResultObserver(for: query)
    
    let fetchResultFromCacheExpectation = resultObserver.expectation(description: "Received result from cache") { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }
    
    client.fetch(query: query, cachePolicy: .returnCacheDataDontFetch, resultHandler: resultObserver.handler)
    
    await fulfillment(of: [fetchResultFromCacheExpectation], timeout: Self.defaultWaitTimeout)
  }
  
  func test__fetch__givenCachePolicy_returnCacheDataDontFetch_givenNotAllDataIsCached_returnsError() async throws {
    class HeroNameAndAppearsInSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("appearsIn", [String]?.self)
        ]}
      }
    }

    let query = MockQuery<HeroNameAndAppearsInSelectionSet>()
    
    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid"
      ]
    ])
    
    let resultObserver = makeResultObserver(for: query)
    
    let cacheMissResultExpectation = resultObserver.expectation(description: "Received cache miss error") { result in
      // TODO: We should check for a specific error type once we've defined a cache miss error.
      XCTAssertThrowsError(try result.get())
    }
    
    client.fetch(query: query,
                 cachePolicy: .returnCacheDataDontFetch,
                 resultHandler: resultObserver.handler)

    await fulfillment(of: [cacheMissResultExpectation], timeout: Self.defaultWaitTimeout)
  }
  
  func test__fetch_afterClearCache_givenCachePolicy_returnCacheDataDontFetch_throwsCacheMissError() async throws {
    class HeroNameSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()
    
    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
      ]
    ])
    
    let resultObserver = makeResultObserver(for: query)
    
    let fetchResultFromCacheExpectation = resultObserver.expectation(
      description: "Received result from cache"
    ) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }
    
    client.fetch(query: query, cachePolicy: .returnCacheDataDontFetch, resultHandler: resultObserver.handler)
    
    await fulfillment(of: [fetchResultFromCacheExpectation], timeout: Self.defaultWaitTimeout)

    // Clear the cache
    let cacheClearedExpectation = expectation(description: "Cache cleared")
    client.clearCache { result in
      XCTAssertSuccessResult(result)
      cacheClearedExpectation.fulfill()
    }

    await fulfillment(of: [cacheClearedExpectation], timeout: Self.defaultWaitTimeout)

    // Fetch from cache and expect cache miss failure
    let cacheMissResultExpectation = resultObserver.expectation(description: "Received cache miss error") { result in
      // TODO: We should check for a specific error type once we've defined a cache miss error.
      XCTAssertThrowsError(try result.get())
    }

    client.fetch(query: query, cachePolicy: .returnCacheDataDontFetch, resultHandler: resultObserver.handler)

    await fulfillment(of: [cacheMissResultExpectation], timeout: Self.defaultWaitTimeout)
  }
  
  func testCompletionHandlerIsCalledOnTheSpecifiedQueue() async {
    let queue = DispatchQueue(label: "label")
    
    let key = DispatchSpecificKey<Void>()
    queue.setSpecific(key: key, value: ())
    
    let query = MockQuery.mock()

    let serverRequestExpectation = await server.expect(MockQuery<MockSelectionSet>.self) { request in
      ["data": [:] as JSONValue]
    }
    
    let resultObserver = makeResultObserver(for: query)
    
    let fetchResultExpectation = resultObserver.expectation(
      description: "Received fetch result"
    ) { result in
      XCTAssertNotNil(DispatchQueue.getSpecific(key: key))
    }
    
    client.fetch(query: query,
                 cachePolicy: .fetchIgnoringCacheData,
                 queue: queue, resultHandler: resultObserver.handler)
    
    await fulfillment(of: [serverRequestExpectation, fetchResultExpectation], timeout: Self.defaultWaitTimeout)
  }
}
