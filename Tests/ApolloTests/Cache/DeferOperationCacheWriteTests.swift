import XCTest
@testable import Apollo
@_spi(Unsafe) import ApolloAPI
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
            .deferred(DeferredFriendName.self, label: "deferredFriendName"),
          ]}

          struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) {
              __data = _dataDict
              _deferredFriendName = Deferred(_dataDict: _dataDict)
            }

            @Deferred var deferredFriendName: DeferredFriendName?
          }
        }
      }
    }
  }
}

fileprivate class DeferredFriendName: MockFragment, @unchecked Sendable {
  override class var __selections: [Selection] {[
    .field("name", String.self),
  ]}

  var name: String { __data["name"] }
}

class DeferOperationCacheWriteTests: XCTestCase, CacheDependentTesting, StoreLoading {
  static let defaultWaitTimeout: TimeInterval = 5.0

  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  var store: ApolloStore!

  override func setUp() async throws {
    try await super.setUp()

    store = try await makeTestStore()
  }

  override func tearDownWithError() throws {
    try super.tearDownWithError()
    
    store = nil
  }

  func test__write__givenOnlyPartialDataAsFulfilled_returnsAllDeferredFragmentsAsPending() async throws {
    // given
    let data = AnimalQuery.AnAnimal(_dataDict: DataDict(
      data: [
        "__typename": "Animal",
        "animal": DataDict(
          data: [
            "__typename": "Animal",
            "species": "Canis latrans",
          ],
          fulfilledFragments: [
            ObjectIdentifier(AnimalQuery.AnAnimal.Animal.self),
            // DeferredGenus not fulfilled
            // DeferredFriend not fulfilled
          ]
        )
      ],
      fulfilledFragments: [
        ObjectIdentifier(AnimalQuery.AnAnimal.self),
      ]
    ))

    // when
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.write(data: data, for: AnimalQuery())
    }

    // then
    try await store.withinReadTransaction { transaction in
      let data = try await transaction.read(query: AnimalQuery())

      expect(data.animal.__typename).to(equal("Animal"))
      expect(data.animal.species).to(equal("Canis latrans"))
      expect(data.animal.fragments.deferredGenus?.genus).to(beNil())
      expect(data.animal.fragments.deferredFriend?.friend.fragments.deferredFriendName?.name).to(beNil())

      expect(data.animal.fragments.$deferredGenus).to(equal(.pending))
      expect(data.animal.fragments.$deferredFriend).to(equal(.pending))
    }
  }

  func test__write__givenSingleDeferredFragmentAsFulfilled_returnsSingleDeferredFragmentAsFulfilled() async throws {
    // given
    let animalData = DataDict(
      data: [
        "__typename": "Animal",
        "species": "Canis latrans",
        "genus": "Canis",
      ],
      fulfilledFragments: [
        ObjectIdentifier(AnimalQuery.AnAnimal.Animal.self),
        ObjectIdentifier(AnimalQuery.AnAnimal.Animal.DeferredGenus.self),
        // DeferredFriend not fulfilled
      ]
    )

    let data = AnimalQuery.AnAnimal(_dataDict: DataDict(
      data: [
        "__typename": "Animal",
        "animal": animalData
      ],
      fulfilledFragments: [
        ObjectIdentifier(AnimalQuery.AnAnimal.self),
      ]
    ))

    // when
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.write(data: data, for: AnimalQuery())
    }

    // then
    try await store.withinReadTransaction { transaction in
      let data = try await transaction.read(query: AnimalQuery())

      expect(data.animal.__typename).to(equal("Animal"))
      expect(data.animal.species).to(equal("Canis latrans"))
      expect(data.animal.fragments.deferredGenus?.genus).to(equal("Canis"))
      expect(data.animal.fragments.deferredFriend?.friend.fragments.deferredFriendName?.name).to(beNil())

      expect(data.animal.fragments.$deferredGenus).to(equal(
        .fulfilled(AnimalQuery.AnAnimal.Animal.DeferredGenus(_dataDict: animalData))
      ))
      expect(data.animal.fragments.$deferredFriend).to(equal(.pending))
    }
  }

  func test__write__givenAllDeferredFragmentsAsFulfilled_returnsAllDeferredFragmentsAsFulfilled() async throws {
    // given
    let friendData = DataDict(
      data: [
        "name": "American Badger",
      ],
      fulfilledFragments: [
        ObjectIdentifier(DeferredFriendName.self),
      ]
    )

    let animalData = DataDict(
      data: [
        "__typename": "Animal",
        "species": "Canis latrans",
        "genus": "Canis",
        "friend": friendData
      ],
      fulfilledFragments: [
        ObjectIdentifier(AnimalQuery.AnAnimal.Animal.self),
        ObjectIdentifier(AnimalQuery.AnAnimal.Animal.DeferredGenus.self),
        ObjectIdentifier(AnimalQuery.AnAnimal.Animal.DeferredFriend.self),
      ]
    )

    let data = AnimalQuery.AnAnimal(_dataDict: DataDict(
      data: [
        "__typename": "Animal",
        "animal": animalData,
      ],
      fulfilledFragments: [
        ObjectIdentifier(AnimalQuery.AnAnimal.self),
      ]
    ))

    // when
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.write(data: data, for: AnimalQuery())
    }

    // then
    try await store.withinReadTransaction { transaction in
      let data = try await transaction.read(query: AnimalQuery())

      expect(data.animal.__typename).to(equal("Animal"))
      expect(data.animal.species).to(equal("Canis latrans"))
      expect(data.animal.fragments.deferredGenus?.genus).to(equal("Canis"))
      expect(data.animal.fragments.deferredFriend?.friend.fragments.deferredFriendName?.name).to(equal("American Badger"))

      expect(data.animal.fragments.$deferredGenus).to(equal(
        .fulfilled(AnimalQuery.AnAnimal.Animal.DeferredGenus(_dataDict: animalData))
      ))
      expect(data.animal.fragments.$deferredFriend).to(equal(
        .fulfilled(AnimalQuery.AnAnimal.Animal.DeferredFriend(_dataDict: animalData))
      ))
      expect(data.animal.fragments.deferredFriend?.friend.fragments.$deferredFriendName).to(equal(
        .fulfilled(DeferredFriendName(_dataDict: friendData))
      ))
    }
  }

  func test__write__givenDeferredData_withoutFragmentFulfilled_returnsDeferredFragmentAsPending() async throws {
    // given
    let animalData = DataDict(
      data: [
        "__typename": "Animal",
        "species": "Canis latrans",
        "genus": "Canis", // DeferredGenus fragment data
      ],
      fulfilledFragments: [
        ObjectIdentifier(AnimalQuery.AnAnimal.Animal.self),
        // DeferredGenus not fulfilled
      ]
    )

    let data = AnimalQuery.AnAnimal(_dataDict: DataDict(
      data: [
        "__typename": "Animal",
        "animal": animalData
      ],
      fulfilledFragments: [
        ObjectIdentifier(AnimalQuery.AnAnimal.self),
      ]
    ))

    // when
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.write(data: data, for: AnimalQuery())
    }

    // then
    try await store.withinReadTransaction { transaction in
      let data = try await transaction.read(query: AnimalQuery())

      expect(data.animal.__typename).to(equal("Animal"))
      expect(data.animal.species).to(equal("Canis latrans"))
      expect(data.animal.fragments.deferredGenus?.genus).to(beNil())
      expect(data.animal.fragments.deferredFriend?.friend.fragments.deferredFriendName?.name).to(beNil())

      expect(data.animal.fragments.$deferredGenus).to(equal(.pending))
      expect(data.animal.fragments.$deferredFriend).to(equal(.pending))
    }
  }

  func test__write__givenDeferredNamedFragment_returnsDeferredNamedFragmentAsFulfilled() async throws {
    // given
    let friendData = DataDict(
      data: [
        "name": "American Badger",
      ],
      fulfilledFragments: [
        ObjectIdentifier(DeferredFriendName.self),
      ]
    )

    let friendSelectionSet = DeferredFriendName(_dataDict: friendData)

    try await store.publish(records: [
      "QUERY_ROOT": [
        "animal": CacheReference("QUERY_ROOT.animal"),
      ],
      "QUERY_ROOT.animal": [
        "__typename": "Animal",
        "species": "Canis latrans",
        "genus": "Canis",
        "friend": CacheReference("QUERY_ROOT.animal.friend"),
      ]
    ])

    // when
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.write(selectionSet: friendSelectionSet, withKey: CacheKey("QUERY_ROOT.animal.friend"))
    }

    // then
    try await store.withinReadTransaction { transaction in
      let data = try await transaction.read(query: AnimalQuery())

      expect(data.animal.__typename).to(equal("Animal"))
      expect(data.animal.species).to(equal("Canis latrans"))
      expect(data.animal.fragments.deferredGenus?.genus).to(equal("Canis"))
      expect(data.animal.fragments.deferredFriend?.friend.fragments.deferredFriendName?.name).to(equal("American Badger"))

      expect(data.animal.fragments.deferredFriend?.friend.fragments.$deferredFriendName).to(equal(
        .fulfilled(DeferredFriendName(_dataDict: friendData))
      ))
    }
  }
}
