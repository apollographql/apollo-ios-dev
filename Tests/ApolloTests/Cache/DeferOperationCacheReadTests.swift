import XCTest
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble

fileprivate class AnimalQuery: MockQuery<AnimalQuery.AnAnimal>, @unchecked Sendable {
  class AnAnimal: MockSelectionSet, @unchecked Sendable {
    typealias Schema = MockSchemaMetadata
    
    override class var __selections: [Selection] {[
      .field("animal", Animal.self),
    ]}
    
    var animal: Animal { __data["animal"] }
    
    class Animal: AbstractMockSelectionSet<Animal.Fragments, MockSchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("species", String.self),
        .deferred(DeferredGenus.self, label: "deferredGenus"),
        .deferred(DeferredFriend.self, label: "deferredFriend"),
      ]}
      
      var species: String { __data["species"] }
      
      struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) {
          __data = _dataDict
          _deferredGenus = Deferred(_dataDict: _dataDict)
          _deferredFriend = Deferred(_dataDict: _dataDict)
        }
        
        @Deferred var deferredGenus: DeferredGenus?
        @Deferred var deferredFriend: DeferredFriend?
      }
      
      class DeferredGenus: MockTypeCase, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("genus", String.self),
        ]}
        
        var genus: String { __data["genus"] }
      }
      
      class DeferredFriend: MockTypeCase, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("friend", Friend.self),
        ]}
        
        var friend: Friend { __data["friend"] }
        
        class Friend: AbstractMockSelectionSet<Friend.Fragments, MockSchemaMetadata>, @unchecked Sendable {
          override class var __selections: [Selection] {[
            .field("name", String.self),
            .deferred(DeferredFriendSpecies.self, label: "deferredFriendSpecies"),
          ]}
          
          var name: String { __data["name"] }

          struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) {
              __data = _dataDict
              _deferredFriendSpecies = Deferred(_dataDict: _dataDict)
            }

            @Deferred var deferredFriendSpecies: DeferredFriendSpecies?
          }

          class DeferredFriendSpecies: MockTypeCase, @unchecked Sendable {
            override class var __selections: [Selection] {[
              .field("species", String.self),
            ]}

            var species: String { __data["species"] }
          }
        }
      }
    }
  }
}

class DeferOperationCacheReadTests: XCTestCase, CacheDependentTesting {
  static let defaultWaitTimeout: TimeInterval = 0.5

  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

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
    try super.tearDownWithError()

    cache = nil
    server = nil
    client = nil
  }

  func test__fetch__givenPartialAndIncrementalDataIsCached_returnsAllDeferredFragmentsAsFulfilled() async throws {
    await mergeRecordsIntoCache([
      "QUERY_ROOT": [
        "animal": CacheReference("QUERY_ROOT.animal"),
      ],
      "QUERY_ROOT.animal": [
        "__typename": "animal",
        "species": "Canis latrans",
        "genus": "Canis",
        "friend": CacheReference("QUERY_ROOT.animal.friend"),
      ],
      "QUERY_ROOT.animal.friend": [
        "name": "American Badger",
        "species": "Taxidea taxus",
      ]
    ])

    let query = AnimalQuery()
    let resultObserver = makeResultObserver(for: query)

    let fetchResultFromCacheExpectation = resultObserver.expectation(
      description: "Received result from cache"
    ) { result in
      expect(result).to(beSuccess())

      let animal = try unwrap(try result.get().data?.animal)

      expect(animal.__typename).to(equal("animal"))
      expect(animal.species).to(equal("Canis latrans"))
      expect(animal.fragments.deferredGenus?.genus).to(equal("Canis"))
      expect(animal.fragments.deferredFriend?.friend.name).to(equal("American Badger"))
      expect(animal.fragments.deferredFriend?.friend.fragments.deferredFriendSpecies?.species).to(equal("Taxidea taxus"))
    }

    client.fetch(
      query: query,
      cachePolicy: .returnCacheDataDontFetch,
      resultHandler: resultObserver.handler
    )

    wait(for: [fetchResultFromCacheExpectation], timeout: Self.defaultWaitTimeout)
  }

  func test__fetch__givenOnlyPartialDataIsCached_returnsAllDeferredFragmentsAsPending() async throws {
    await mergeRecordsIntoCache([
      "QUERY_ROOT": [
        "animal": CacheReference("QUERY_ROOT.animal"),
      ],
      "QUERY_ROOT.animal": [
        "__typename": "animal",
        "species": "Canis latrans",
        // 'genus' not cached
        // 'friend' not cached
      ],
    ])

    let query = AnimalQuery()
    let resultObserver = makeResultObserver(for: query)

    let fetchResultFromCacheExpectation = resultObserver.expectation(
      description: "Received result from cache"
    ) { result in
      expect(result).to(beSuccess())

      let animal = try unwrap(try result.get().data?.animal)

      expect(animal.__typename).to(equal("animal"))
      expect(animal.species).to(equal("Canis latrans"))
      expect(animal.fragments.$deferredGenus).to(equal(.pending))
      expect(animal.fragments.$deferredFriend).to(equal(.pending))
    }

    client.fetch(
      query: query,
      cachePolicy: .returnCacheDataDontFetch,
      resultHandler: resultObserver.handler
    )

    wait(for: [fetchResultFromCacheExpectation], timeout: Self.defaultWaitTimeout)
  }

  func test__fetch__givenPartialAndSomeIncrementalDataIsCached_returnsCachedDeferredFragmentAsFulfilledAndUncachedDeferredFragmentsAsPending() async throws {
    await mergeRecordsIntoCache([
      "QUERY_ROOT": [
        "animal": CacheReference("QUERY_ROOT.animal"),
      ],
      "QUERY_ROOT.animal": [
        "__typename": "animal",
        "species": "Canis latrans",
        "genus": "Canis",
        // 'friend' not cached
      ],
    ])

    let query = AnimalQuery()
    let resultObserver = makeResultObserver(for: query)

    let fetchResultFromCacheExpectation = resultObserver.expectation(
      description: "Received result from cache"
    ) { result in
      expect(result).to(beSuccess())

      let animal = try unwrap(try result.get().data?.animal)

      expect(animal.__typename).to(equal("animal"))
      expect(animal.species).to(equal("Canis latrans"))
      expect(animal.fragments.deferredGenus?.genus).to(equal("Canis"))
      expect(animal.fragments.$deferredFriend).to(equal(.pending))
    }

    client.fetch(
      query: query,
      cachePolicy: .returnCacheDataDontFetch,
      resultHandler: resultObserver.handler
    )

    wait(for: [fetchResultFromCacheExpectation], timeout: Self.defaultWaitTimeout)
  }

  func test__fetch__givenNestedIncrementalDataIsNotCached_returnsNestedDeferredFragmentsAsPending_otherDeferredFragmentsAsFulfilled() async throws {
    await mergeRecordsIntoCache([
      "QUERY_ROOT": [
        "animal": CacheReference("QUERY_ROOT.animal"),
      ],
      "QUERY_ROOT.animal": [
        "__typename": "animal",
        "species": "Canis latrans",
        "genus": "Canis",
        "friend": CacheReference("QUERY_ROOT.animal.friend"),
      ],
      "QUERY_ROOT.animal.friend": [
        "name": "American Badger",
        // 'species' not cached
      ]
    ])

    let query = AnimalQuery()
    let resultObserver = makeResultObserver(for: query)

    let fetchResultFromCacheExpectation = resultObserver.expectation(
      description: "Received result from cache"
    ) { result in
      expect(result).to(beSuccess())

      let animal = try unwrap(try result.get().data?.animal)

      expect(animal.__typename).to(equal("animal"))
      expect(animal.species).to(equal("Canis latrans"))
      expect(animal.fragments.deferredGenus?.genus).to(equal("Canis"))
      expect(animal.fragments.deferredFriend?.friend.name).to(equal("American Badger"))
      expect(animal.fragments.deferredFriend?.friend.fragments.$deferredFriendSpecies).to(equal(.pending))
    }

    client.fetch(
      query: query,
      cachePolicy: .returnCacheDataDontFetch,
      resultHandler: resultObserver.handler
    )

    wait(for: [fetchResultFromCacheExpectation], timeout: Self.defaultWaitTimeout)
  }

  func test__fetch__givenMissingValueInDeferredFragment_returnsDeferredFragmentAsPending_otherDeferredFragmentsAsFulfilled() async throws {
    await mergeRecordsIntoCache([
      "QUERY_ROOT": [
        "animal": CacheReference("QUERY_ROOT.animal"),
      ],
      "QUERY_ROOT.animal": [
        "__typename": "animal",
        "species": "Canis latrans",
        "genus": "Canis",
        "friend": CacheReference("QUERY_ROOT.animal.friend"),
      ],
      "QUERY_ROOT.animal.friend": [
        // 'name' missing
        "species": "Taxidea taxus",
      ]
    ])

    let query = AnimalQuery()
    let resultObserver = makeResultObserver(for: query)

    let fetchResultFromCacheExpectation = resultObserver.expectation(
      description: "Received result from cache"
    ) { result in
      expect(result).to(beSuccess())

      let animal = try unwrap(try result.get().data?.animal)

      expect(animal.__typename).to(equal("animal"))
      expect(animal.species).to(equal("Canis latrans"))
      expect(animal.fragments.deferredGenus?.genus).to(equal("Canis"))
      expect(animal.fragments.$deferredFriend).to(equal(.pending))
    }

    client.fetch(
      query: query,
      cachePolicy: .returnCacheDataDontFetch,
      resultHandler: resultObserver.handler
    )

    wait(for: [fetchResultFromCacheExpectation], timeout: Self.defaultWaitTimeout)
  }

  func test__fetch__givenMissingValueInPartialData_shouldFailFetch() async throws {
    await mergeRecordsIntoCache([
      "QUERY_ROOT": [
        "animal": CacheReference("QUERY_ROOT.animal"),
      ],
      "QUERY_ROOT.animal": [
        "__typename": "animal",
        // 'species' missing
        "genus": "Canis",
        "friend": CacheReference("QUERY_ROOT.animal.friend"),
      ],
      "QUERY_ROOT.animal.friend": [
        "name": "American Badger",
        "species": "Taxidea taxus",
      ]
    ])

    let query = AnimalQuery()
    let resultObserver = makeResultObserver(for: query)

    let fetchResultFromCacheExpectation = resultObserver.expectation(
      description: "Received result from cache"
    ) { result in
      expect(result).to(beFailure { error in
        guard let error = error as? GraphQLExecutionError else {
          fail("Unexpected error - \(error)")
          return
        }

        expect(error.path).to(equal(["animal", "species"]))
        expect(error.underlying).to(matchError(JSONDecodingError.missingValue))
      })


    }

    client.fetch(
      query: query,
      cachePolicy: .returnCacheDataDontFetch,
      resultHandler: resultObserver.handler
    )

    wait(for: [fetchResultFromCacheExpectation], timeout: Self.defaultWaitTimeout)
  }
}
