import XCTest
@testable @_spi(Execution) import Apollo
@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloInternalTestHelpers

class StoreConcurrencyTests: XCTestCase, CacheDependentTesting {
  
  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }
  
  var defaultWaitTimeout: TimeInterval = 60

  var store: ApolloStore!
  
  override func setUp() async throws {
    try await super.setUp()

    store = try await makeTestStore()
  }
  
  override func tearDownWithError() throws {    
    store = nil
    
    try super.tearDownWithError()
  }

  // MARK: - Mocks

  class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
    override class var __selections: [Selection] {[
      .field("hero", Hero?.self)
    ]}

    var hero: Hero? { __data["hero"] }

    class Hero: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("name", String.self),
        .field("friends", [Friend]?.self),
      ]}

      var friends: [Friend]? { __data["friends"] }

      class Friend: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
        ]}

        var name: String { __data["name"] }
      }
    }
  }

  // MARK - Tests

  func testMultipleReadsInitiatedFromMainThread() async throws {
    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": [
          CacheReference("1000"),
          CacheReference("1002"),
          CacheReference("1003")
        ]
      ],
      "1000": ["__typename": "Human", "name": "Luke Skywalker"],
      "1002": ["__typename": "Human", "name": "Han Solo"],
      "1003": ["__typename": "Human", "name": "Leia Organa"],
    ])
    
    let query = MockQuery<GivenSelectionSet>()
    
    let numberOfReads = 1000
    
    let allReadsCompletedExpectation = XCTestExpectation(description: "All reads completed")
    allReadsCompletedExpectation.expectedFulfillmentCount = numberOfReads

    for _ in 0..<numberOfReads {
      Task { @MainActor [store = store!] in
        defer { allReadsCompletedExpectation.fulfill() }
        try await store.withinReadTransaction { transaction in
          let data = try await transaction.read(query: query)

          XCTAssertEqual(data.hero?.name, "R2-D2")
          let friendsNames = data.hero?.friends?.map { $0.name }
          XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
        }
      }
    }

    await fulfillment(of: [allReadsCompletedExpectation], timeout: defaultWaitTimeout)
  }
  
  func testConcurrentReadsInitiatedFromBackgroundTasks() async throws {
    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": [
          CacheReference("1000"),
          CacheReference("1002"),
          CacheReference("1003")
        ]
      ],
      "1000": ["__typename": "Human", "name": "Luke Skywalker"],
      "1002": ["__typename": "Human", "name": "Han Solo"],
      "1003": ["__typename": "Human", "name": "Leia Organa"],
    ])
    
    let query = MockQuery<GivenSelectionSet>()
    
    let numberOfReads = 1000
    
    let allReadsCompletedExpectation = XCTestExpectation(description: "All reads completed")
    allReadsCompletedExpectation.expectedFulfillmentCount = numberOfReads

    for _ in 0..<numberOfReads {
      Task(priority: .background) { [store = store!] in
        defer { allReadsCompletedExpectation.fulfill() }
        try await store.withinReadTransaction { transaction in
          let data = try await transaction.read(query: query)

          XCTAssertEqual(data.hero?.name, "R2-D2")
          let friendsNames = data.hero?.friends?.map { $0.name }
          XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
        }
      }
    }

    await fulfillment(of: [allReadsCompletedExpectation], timeout: defaultWaitTimeout)
  }

  func testMultipleUpdatesInitiatedFromMainThread() async throws {
    /// given
    struct GivenSelectionSet: MockMutableRootSelectionSet {
      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      var hero: Hero {
        get { __data["hero"] }
        set { __data["hero"] = newValue }
      }

      struct Hero: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] { [
          .field("id", String.self),
          .field("name", String.self),
          .field("friends", [Friend].self),
        ]}

        var id: String {
          get { __data["id"] }
          set { __data["id"] = newValue }
        }

        var name: String? {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        var friends: [Friend] {
          get { __data["friends"] }
          set { __data["friends"] = newValue }
        }

        struct Friend: MockMutableRootSelectionSet {
          public var __data: DataDict = .empty()
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __selections: [Selection] { [
            .field("id", String.self),
            .field("name", String.self),
          ]}

          var id: String {
            get { __data["id"] }
            set { __data["id"] = newValue }
          }

          var name: String {
            get { __data["name"] }
            set { __data["name"] = newValue }
          }
        }
      }
    }

    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "id": "2001",
        "__typename": "Droid",
        "friends": [] as JSONValue
      ]
    ])

    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()
    let query = MockQuery<GivenSelectionSet>()

    let numberOfUpdates = 100

    for i in 0..<numberOfUpdates {
      try await store.withinReadWriteTransaction { transaction in
        try await transaction.update(cacheMutation) { data in
          data.hero.name = "Artoo"

          var newDroid = GivenSelectionSet.Hero.Friend()
          newDroid.__typename = "Droid"
          newDroid.id = "\(i)"
          newDroid.name = "Droid #\(i)"
          data.hero.friends.append(newDroid)
        }

        let data = try await transaction.read(query: query)

        XCTAssertEqual(data.hero.name, "Artoo")
        XCTAssertEqual(data.hero.friends.last?.name, "Droid #\(i)")
      }
    }

    try await store.withinReadTransaction { transaction in
      let data = try await transaction.read(query: query)

      XCTAssertEqual(data.hero.name, "Artoo")

      let friendsNames: [String] = try XCTUnwrap(
        data.hero.friends.compactMap { $0.name }
      )
      let expectedFriendsNames = (0..<numberOfUpdates).map { "Droid #\($0)" }
      XCTAssertEqualUnordered(friendsNames, expectedFriendsNames)
    }
  }
  
  func testUpdatesInitiatedConcurrentlyFromBackgroundTasks_preventsConcurrentWriteTransactions() async throws {
    /// given
    struct GivenSelectionSet: MockMutableRootSelectionSet {
      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      var hero: Hero {
        get { __data["hero"] }
        set { __data["hero"] = newValue }
      }

      struct Hero: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] { [
          .field("id", String.self),
          .field("name", String.self),
          .field("friends", [Friend].self),
        ]}

        var id: String {
          get { __data["id"] }
          set { __data["id"] = newValue }
        }

        var name: String? {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        var friends: [Friend] {
          get { __data["friends"] }
          set { __data["friends"] = newValue }
        }

        struct Friend: MockMutableRootSelectionSet {
          public var __data: DataDict = .empty()
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __selections: [Selection] { [
            .field("id", String.self),
            .field("name", String.self),
          ]}

          var id: String {
            get { __data["id"] }
            set { __data["id"] = newValue }
          }

          var name: String {
            get { __data["name"] }
            set { __data["name"] = newValue }
          }
        }
      }
    }

    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "id": "2001",
        "__typename": "Droid",
        "friends": [] as JSONValue
      ]
    ])

    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()
    let query = MockQuery<GivenSelectionSet>()

    let numberOfUpdates = 100

    try await withThrowingTaskGroup { [store = store!] group in
      for i in 0..<numberOfUpdates {
        _ = group.addTaskUnlessCancelled {
          try await store.withinReadWriteTransaction { transaction in
            try await transaction.update(cacheMutation) { data in
              data.hero.name = "Artoo"

              var newDroid = GivenSelectionSet.Hero.Friend()
              newDroid.__typename = "Droid"
              newDroid.id = "\(i)"
              newDroid.name = "Droid #\(i)"
              data.hero.friends.append(newDroid)
            }

            let data = try await transaction.read(query: query)

            XCTAssertEqual(data.hero.name, "Artoo")
            XCTAssertEqual(data.hero.friends.last?.name, "Droid #\(i)")
          }
        }
      }

      try await group.waitForAll()
    }

    try await store.withinReadTransaction { transaction in
      let data = try await transaction.read(query: query)

      XCTAssertEqual(data.hero.name, "Artoo")

      let friendsNames: [String] = try XCTUnwrap(
        data.hero.friends.compactMap { $0.name }
      )

      let expectedFriendsNames = (0..<numberOfUpdates).map { "Droid #\($0)" }
      XCTAssertEqualUnordered(friendsNames, expectedFriendsNames)
    }
  }
}
