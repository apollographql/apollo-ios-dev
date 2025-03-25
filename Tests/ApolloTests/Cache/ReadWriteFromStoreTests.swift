import XCTest
import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

class ReadWriteFromStoreTests: XCTestCase, CacheDependentTesting, StoreLoading {

  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  static let defaultWaitTimeout: TimeInterval = 5.0

  var cache: (any NormalizedCache)!
  var store: ApolloStore!

  override func setUp() async throws {
    try await super.setUp()

    cache = try await makeNormalizedCache()
    store = ApolloStore(cache: cache)
  }

  override func tearDownWithError() throws {
    cache = nil
    store = nil

    try super.tearDownWithError()
  }

  // MARK: - Read Query Tests

  func test_readQuery_givenQueryDataInCache_returnsData() async throws {
    class HeroNameSelectionSet: MockSelectionSet {
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

    let query = MockQuery<HeroNameSelectionSet>()

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid", "name": "R2-D2"]
    ])

    try await store.withinReadTransaction { transaction in
      let data = try await transaction.read(query: query)

      expect(data.hero?.__typename).to(equal("Droid"))
      expect(data.hero?.name).to(equal("R2-D2"))
    }
  }

  func test_readQuery_givenQueryDataDoesNotExist_throwsMissingValueError() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("name", String.self)
      ]}
    }

    let query = MockQuery<GivenSelectionSet>()

    await mergeRecordsIntoCache([
      "QUERY_ROOT": [:],
    ])

    // when
    await expect {
      try await self.store.withinReadWriteTransaction { transaction in
        _ = try await transaction.read(query: query)
      }
    }.to(throwError(
      GraphQLExecutionError(path: ["name"], underlying: JSONDecodingError.missingValue)
    ))
  }

  func test_readQuery_givenQueryDataWithVariableInCache_readsQuery() async throws {
    // given
    enum Episode: String, EnumType {
      case JEDI
    }

    class HeroNameSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["episode": .variable("episode")])
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()
    query.__variables = ["episode": Episode.JEDI]

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero(episode:JEDI)": CacheReference("hero(episode:JEDI)")],
      "hero(episode:JEDI)": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // when
    try await store.withinReadTransaction { transaction in
      let data = try await transaction.read(query: query)

      // then
      expect(data.hero?.__typename).to(equal("Droid"))
      expect(data.hero?.name).to(equal("R2-D2"))

    }
  }

  func test_readQuery_givenQueryDataWithOtherVariableValueInCache_throwsMissingValueError() async throws {
    // given
    enum Episode: String, EnumType {
      case JEDI
      case PHANTOM_MENACE
    }

    class HeroNameSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["episode": .variable("episode")])
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()
    query.__variables = ["episode": Episode.PHANTOM_MENACE]

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero(episode:JEDI)": CacheReference("hero(episode:JEDI)")],
      "hero(episode:JEDI)": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // when
    await expect {
      try await self.store.withinReadWriteTransaction { transaction in
        _ = try await transaction.read(query: query)
      }
    }.to(throwError(
      GraphQLExecutionError(path: ["hero"], underlying: JSONDecodingError.missingValue)
    ))
  }

  func test_readQuery_withCacheReferencesByCustomKey_resolvesReferences() async throws {
    // given
    class HeroFriendsSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("id", String.self),
          .field("name", String.self),
          .field("friends", [Friend].self)
        ]}

        var friends: [Friend] { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
          ]}
        }
      }
    }

    let query = MockQuery<HeroFriendsSelectionSet>()
    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "id": "2001",
        "__typename": "Droid",
        "friends": [
          CacheReference("1000"),
          CacheReference("1002"),
          CacheReference("1003")
        ]
      ],
      "1000": ["__typename": "Human", "name": "Luke Skywalker", "id": "1000"],
      "1002": ["__typename": "Human", "name": "Han Solo", "id": "1002"],
      "1003": ["__typename": "Human", "name": "Leia Organa", "id": "1003"],
    ])

    // when
    try await store.withinReadTransaction { transaction in
      let data = try await transaction.read(query: query)

      XCTAssertEqual(data.hero.name, "R2-D2")
      let friendsNames: [String] = data.hero.friends.compactMap { $0.name }
      XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
    }
  }

  @MainActor
  func test_readObject_givenFragmentWithTypeSpecificProperty() async throws {
    // given
    struct Types {
      static let Droid = Object(typename: "Droid", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({ typename in
      switch typename {
      case "Droid": return Types.Droid
      default: return nil
      }
    })

    class GivenSelectionSet: MockFragment {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
        .inlineFragment(AsDroid.self),
      ]}

      var asDroid: AsDroid? { _asInlineFragment() }

      class AsDroid: MockTypeCase {
        typealias Schema = MockSchemaMetadata
        override class var __parentType: any ParentType { Types.Droid }

        override class var __selections: [Selection] { [
          .field("primaryFunction", String.self),
        ]}
      }
    }

    await mergeRecordsIntoCache([
      "2001": ["name": "R2-D2", "__typename": "Droid", "primaryFunction": "Protocol"]
    ])

    // when
    try await store.withinReadTransaction { transaction in
      let r2d2 = try await transaction.readObject(
        ofType: GivenSelectionSet.self,
        withKey: "2001"
      )

      XCTAssertEqual(r2d2.name, "R2-D2")
      XCTAssertEqual(r2d2.asDroid?.primaryFunction, "Protocol")
    }
  }

  @MainActor
  func test_readObject_givenFragmentWithMissingTypeSpecificProperty() async throws {
    // given
    struct Types {
      static let Droid = Object(typename: "Droid", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({ typename in
      switch typename {
      case "Droid": return Types.Droid
      default: return nil
      }
    })

    class GivenSelectionSet: MockFragment {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
        .inlineFragment(AsDroid.self),
      ]}

      var asDroid: AsDroid? { _asInlineFragment() }

      class AsDroid: MockTypeCase {
        typealias Schema = MockSchemaMetadata
        override class var __parentType: any ParentType { Types.Droid }

        override class var __selections: [Selection] { [
          .field("primaryFunction", String.self),
        ]}
      }
    }

    await mergeRecordsIntoCache([
      "2001": ["name": "R2-D2", "__typename": "Droid"]
    ])

    // when
    _ = try await store.withinReadTransaction { transaction in
      await expect {
        _ = try await transaction.readObject(
          ofType: GivenSelectionSet.self,
          withKey: "2001"
        )
      }.to(throwError(
        GraphQLExecutionError(path: ["primaryFunction"], underlying: JSONDecodingError.missingValue)
      ))
    }
  }

  // MARK: - Write Local Cache Mutation Tests

  func test_updateCacheMutation_updateNestedField_updatesObjects() async throws {
    // given
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
          .field("name", String.self)
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // when

    // Update Mutation
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.update(cacheMutation) { data in
        data.hero.name = "Artoo"
      }
    }

    // Load Query
    let query = MockQuery<GivenSelectionSet>()
    let graphQLResult = try await store.load(query)

    // then
    XCTAssertEqual(graphQLResult.source, .cache)
    XCTAssertNil(graphQLResult.errors)

    let data = try XCTUnwrap(graphQLResult.data)
    XCTAssertEqual(data.hero.name, "Artoo")
  }

  func test_updateCacheMutationWithOptionalField_containingNull_updateNestedField_updatesObjectsMaintainingNullValue() async throws {
    // given
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
          .field("name", String.self),
          .field("nickname", String?.self)
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        var nickname: String? {
          get { __data["nickname"] }
          set { __data["nickname"] = newValue }
        }
      }
    }

    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2", "nickname": NSNull()]
    ])

    // Update Mutation
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.update(cacheMutation) { data in
        data.hero.name = "Artoo"
      }
    }

    let record = try! await self.cache.loadRecords(forKeys: ["QUERY_ROOT.hero"]).first?.value
    expect(record?["nickname"]).to(equal(NSNull()))

    let query = MockQuery<GivenSelectionSet>()

    loadFromStore(operation: query) { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero.name, "Artoo")
        expect(data.hero.nickname).to(beNil())
        expect(data.hero.hasNullValue(forKey: "nickname")).to(beTrue())
      }
    }
  }

  /// This test ensures the fix for issue [#2861](https://github.com/apollographql/apollo-ios/issues/2861)
  func test_updateCacheMutationWithOptionalField_containiningNull_retrievingOptionalField_returns_nil() async throws {
    // given
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
          .field("name", String.self),
          .field("nickname", String?.self)
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        var nickname: String? {
          get { __data["nickname"] }
          set { __data["nickname"] = newValue }
        }
      }
    }

    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2", "nickname": NSNull()]
    ])

    // Update Mutation
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.update(cacheMutation) { data in
        // doing a nil-coalescing to replace nil with <not-populated>
        let nickname = data.hero.nickname
        expect(nickname).to(beNil())
      }
    }
  }

  /// The 'nickname' field is currently a cache miss, as it has never been fetched. We want to be able
  /// to successfully mutate the 'name' field, but the 'nickname' field should still be a cache miss.
  /// While reading an optional field to execute a cache mutation, this is fine, but while reading the
  /// omitted optional field to execute a fetch from the cache onto a immutable selection set for a
  /// operation, this should throw a missing value error, indicating the cache miss.
  func test_updateCacheMutationWithOptionalField_omittingOptionalField_updateNestedField_updatesObjectsMaintainingNilValue_throwsMissingValueErrorOnRead() async throws {
    // given
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
          .field("name", String.self),
          .field("nickname", String?.self)
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        var nickname: String? {
          get { __data["nickname"] }
          set { __data["nickname"] = newValue }
        }
      }
    }

    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // Update Mutation
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.update(cacheMutation) { data in
        data.hero.name = "Artoo"
      }
    }

    let query = MockQuery<GivenSelectionSet>()

    await expect {
      try await self.store.load(query)
    }.to(throwError(
      GraphQLExecutionError(path: ["hero", "nickname"], underlying: JSONDecodingError.missingValue)
    ))
  }

  func test_updateCacheMutationWithNonNullField_withNilValue_updateNestedField_throwsMissingValueOnInitialReadForUpdate() async throws {
    // given
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
          .field("name", String.self),
          .field("nickname", String.self)
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        var nickname: String {
          get { __data["nickname"] }
          set { __data["nickname"] = newValue }
        }
      }
    }

    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // Update Mutation
    await expect {
      try await self.store.withinReadWriteTransaction { transaction in
        try await transaction.update(cacheMutation) { data in
          data.hero.name = "Artoo"
        }
      }
    }.to(throwError(
      GraphQLExecutionError(path: ["hero", "nickname"], underlying: JSONDecodingError.missingValue)
    ))
  }

  func test_updateCacheMutation_givenMutationOperation_updateNestedField_updatesObjectAtMutationRoot() async throws {
    // given
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
          .field("name", String.self)
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

    let cacheMutation = MockLocalCacheMutationFromMutation<GivenSelectionSet>()

    await mergeRecordsIntoCache([
      "MUTATION_ROOT": ["hero": CacheReference("MUTATION_ROOT.hero")],
      "MUTATION_ROOT.hero": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // Update Mutation
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.update(cacheMutation) { data in
        data.hero.name = "Artoo"
      }
    }

    // Load Mutation
    let mutation = MockMutation<GivenSelectionSet>()

    let graphQLResult = try await self.store.load(mutation)
    XCTAssertEqual(graphQLResult.source, .cache)
    XCTAssertNil(graphQLResult.errors)

    let data = try XCTUnwrap(graphQLResult.data)
    XCTAssertEqual(data.hero.name, "Artoo")
  }

  func test_updateCacheMutation_givenQueryWithVariables_updateNestedField_updatesObjectsOnlyForQueryWithMatchingVariables() async throws {
    // given
    enum Episode: String, EnumType {
      case JEDI
      case PHANTOM_MENACE
    }

    struct GivenSelectionSet: MockMutableRootSelectionSet {
      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["episode": .variable("episode")])
      ]}

      var hero: Hero {
        get { __data["hero"] }
        set { __data["hero"] = newValue }
      }

      struct Hero: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] { [
          .field("name", String.self)
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": [
        "hero(episode:JEDI)": CacheReference("hero(episode:JEDI)"),
        "hero(episode:PHANTOM_MENACE)": CacheReference("hero(episode:PHANTOM_MENACE)")
      ],
      "hero(episode:JEDI)": ["__typename": "Droid", "name": "R2-D2"],
      "hero(episode:PHANTOM_MENACE)": ["__typename": "Human", "name": "Qui-Gon Jinn"]
    ])

    // Update Mutation
    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()
    cacheMutation.__variables = ["episode": Episode.JEDI]

    try await store.withinReadWriteTransaction { transaction in
      try await transaction.update(cacheMutation) { data in
        data.hero.name = "Artoo"
      }
    }

    // Read Queries
    let query = MockQuery<GivenSelectionSet>()
    query.__variables = ["episode": Episode.JEDI]

    let graphQLResult1 = try await self.store.load(query)

    XCTAssertEqual(graphQLResult1.source, .cache)
    XCTAssertNil(graphQLResult1.errors)

    let data1 = try XCTUnwrap(graphQLResult1.data)
    XCTAssertEqual(data1.hero.name, "Artoo")

    query.__variables = ["episode": Episode.PHANTOM_MENACE]
    let graphQLResult2 = try await self.store.load(query)

    XCTAssertEqual(graphQLResult2.source, .cache)
    XCTAssertNil(graphQLResult2.errors)

    let data2 = try XCTUnwrap(graphQLResult2.data)
    XCTAssertEqual(data2.hero.name, "Qui-Gon Jinn")
  }

  @MainActor
  func test_updateCacheMutation_updateNestedFieldOnTypeCase_updatesObjects() async throws {
    // given
    struct Types {
      static let Droid = Object(typename: "Droid", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({ typename in
      switch typename {
      case "Droid": return Types.Droid
      default: return nil
      }
    })

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
          .field("__typename", String.self),
          .field("name", String.self),
          .inlineFragment(AsDroid.self),
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        var asDroid: AsDroid? {
          get { _asInlineFragment() }
          set { if let newData = newValue?.__data._data { __data._data = newData }}
        }

        struct AsDroid: MockMutableInlineFragment {
          public var __data: DataDict = .empty()

          public typealias RootEntityType = Hero
          static let __parentType: any ParentType = Types.Droid
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __selections: [Selection] { [
            .field("primaryFunction", String.self),
          ]}

          var primaryFunction: String {
            get { __data["primaryFunction"] }
            set { __data["primaryFunction"] = newValue }
          }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2", "primaryFunction": "Protocol"]
    ])

    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()

    // Update Mutation
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.update(cacheMutation) { data in
        data.hero.asDroid?.primaryFunction = "Combat"
      }
    }

    // Load Query
    let query = MockQuery<GivenSelectionSet>()

    let graphQLResult = try await self.store.load(query)
    XCTAssertEqual(graphQLResult.source, .cache)
    XCTAssertNil(graphQLResult.errors)

    let data = try XCTUnwrap(graphQLResult.data)
    XCTAssertEqual(data.hero.asDroid?.primaryFunction, "Combat")
  }

  @MainActor
  func test_updateCacheMutation_updateNestedFieldOnNamedFragment_updatesObjects() async throws {
    // given
    struct Types {
      static let Droid = Object(typename: "Droid", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({ typename in
      switch typename {
      case "Droid": return Types.Droid
      default: return nil
      }
    })

    struct GivenFragment: MockMutableRootSelectionSet, Fragment {
      typealias Schema = MockSchemaMetadata
      static let fragmentDefinition: StaticString = ""

      var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
        .inlineFragment(AsDroid.self),
      ]}

      var name: String {
        get { __data["name"] }
        set { __data["name"] = newValue }
      }

      var asDroid: AsDroid? {
        get { _asInlineFragment() }
        set { if let newData = newValue?.__data._data { __data._data = newData }}
      }

      struct AsDroid: MockMutableInlineFragment {
        public var __data: DataDict = .empty()
        public typealias RootEntityType = GivenFragment
        static let __parentType: any ParentType = Types.Droid
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] { [
          .field("primaryFunction", String.self),
        ]}

        var primaryFunction: String {
          get { __data["primaryFunction"] }
          set { __data["primaryFunction"] = newValue }
        }
      }
    }

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
          .field("__typename", String.self),
          .field("name", String.self),
          .fragment(GivenFragment.self),
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        struct Fragments: FragmentContainer {
          var __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          var givenFragment: GivenFragment {
            get { _toFragment() }
            _modify { var f = givenFragment; yield &f; __data = f.__data }
          }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2", "primaryFunction": "Protocol"]
    ])

    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()

    // Update Mutation
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.update(cacheMutation) { data in
        data.hero.fragments.givenFragment.name = "Artoo"
        data.hero.fragments.givenFragment.asDroid?.primaryFunction = "Combat"
      }
    }

    // Load Query
    let query = MockQuery<GivenSelectionSet>()

    let graphQLResult = try await self.store.load(query)
    XCTAssertEqual(graphQLResult.source, .cache)
    XCTAssertNil(graphQLResult.errors)

    let data = try XCTUnwrap(graphQLResult.data)
    XCTAssertEqual(data.hero.name, "Artoo")
    XCTAssertEqual(data.hero.fragments.givenFragment.asDroid?.primaryFunction, "Combat")
  }

  @MainActor
  func test_updateCacheMutation_updateNestedFieldOnOptionalNamedFragment_updatesObjects() async throws {
    // given
    struct Types {
      static let Droid = Object(typename: "Droid", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({ typename in
      switch typename {
      case "Droid": return Types.Droid
      default: return nil
      }
    })

    struct GivenFragment: MockMutableRootSelectionSet, Fragment {
      typealias Schema = MockSchemaMetadata
      static let fragmentDefinition: StaticString = ""

      var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
        .inlineFragment(AsDroid.self),
      ]}

      var name: String {
        get { __data["name"] }
        set { __data["name"] = newValue }
      }

      var asDroid: AsDroid? {
        get { _asInlineFragment() }
        set { if let newData = newValue?.__data._data { __data._data = newData }}
      }

      struct AsDroid: MockMutableInlineFragment {
        public var __data: DataDict = .empty()
        public typealias RootEntityType = GivenFragment
        static let __parentType: any ParentType = Types.Droid
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] { [
          .field("primaryFunction", String.self),
        ]}

        var primaryFunction: String {
          get { __data["primaryFunction"] }
          set { __data["primaryFunction"] = newValue }
        }
      }
    }

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
          .field("__typename", String.self),
          .field("name", String.self),
          .fragment(GivenFragment.self),
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }

        var asDroid: AsDroid? {
          get { _asInlineFragment() }
          set { if let newData = newValue?.__data._data { __data._data = newData }}
        }

        struct AsDroid: MockMutableInlineFragment {
          public var __data: DataDict = .empty()
          public typealias RootEntityType = GivenFragment
          static let __parentType: any ParentType = Types.Droid
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __selections: [Selection] { [
            .field("primaryFunction", String.self),
          ]}

          var primaryFunction: String {
            get { __data["primaryFunction"] }
            set { __data["primaryFunction"] = newValue }
          }
        }

        struct Fragments: FragmentContainer {
          var __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          var givenFragment: GivenFragment? {
            get { _toFragment() }
            _modify { var f = givenFragment; yield &f; if let newData = f?.__data { __data = newData } }
          }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2", "primaryFunction": "Protocol"]
    ])

    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()

    // Update Mutation
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.update(cacheMutation) { data in
        data.hero.fragments.givenFragment?.name = "Artoo"
        data.hero.fragments.givenFragment?.asDroid?.primaryFunction = "Combat"
      }
    }

    // Load Query
    let query = MockQuery<GivenSelectionSet>()

    let graphQLResult = try await self.store.load(query)

    XCTAssertEqual(graphQLResult.source, .cache)
    XCTAssertNil(graphQLResult.errors)

    let data = try XCTUnwrap(graphQLResult.data)
    XCTAssertEqual(data.hero.name, "Artoo")
    XCTAssertEqual(data.hero.fragments.givenFragment?.asDroid?.primaryFunction, "Combat")
  }

  func test_updateCacheMutation_givenAddNewReferencedEntity_entityIsIncludedOnRead() async throws {
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

        var name: String {
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

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "id": "2001",
        "__typename": "Droid",
        "friends": [
          CacheReference("1000"),
          CacheReference("1002"),
          CacheReference("1003")
        ]
      ],
      "1000": ["__typename": "Human", "name": "Luke Skywalker", "id": "1000"],
      "1002": ["__typename": "Human", "name": "Han Solo", "id": "1002"],
      "1003": ["__typename": "Human", "name": "Leia Organa", "id": "1003"],
    ])

    // "Add C-3PO Entity and Reference"
    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()

    try await store.withinReadWriteTransaction { transaction in
      try await transaction.update(cacheMutation) { data in
        var c3po = GivenSelectionSet.Hero.Friend()
        c3po.__typename = "Droid"
        c3po.id = "1004"
        c3po.name = "C-3PO"

        data.hero.friends.append(c3po)
      }
    }

    // Read Query
    let query = MockQuery<GivenSelectionSet>()

    let graphQLResult = try await self.store.load(query)

    XCTAssertEqual(graphQLResult.source, .cache)
    XCTAssertNil(graphQLResult.errors)

    let data = try XCTUnwrap(graphQLResult.data)
    XCTAssertEqual(data.hero.name, "R2-D2")
    let friendsNames = data.hero.friends.compactMap { $0.name }
    XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa", "C-3PO"])
  }

  func test_updateCacheMutation_givenEnumField_enumFieldIsSerializedAndCanBeRead() async throws {
    // given
    enum HeroType: String, EnumType {
      case droid
    }

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
          .field("type", GraphQLEnum<HeroType>.self)
        ]}

        var type: GraphQLEnum<HeroType> {
          get { __data["type"] }
          set { __data["type"] = newValue }
        }
      }
    }

    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "type": "droid"]
    ])

    // Update Mutation
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.update(cacheMutation) { data in
        // noop
      }
    }

    let query = MockQuery<GivenSelectionSet>()

    let graphQLResult = try await self.store.load(query)
    XCTAssertEqual(graphQLResult.source, .cache)
    XCTAssertNil(graphQLResult.errors)

    let data = try XCTUnwrap(graphQLResult.data)
    XCTAssertEqual(data.hero.type, .case(.droid))
  }

  func test_writeDataForCacheMutation_givenMutationOperation_updateNestedField_updatesObjectAtMutationRoot() async throws {
    // given
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
          .field("name", String.self)
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

    // Update Mutation
    try await store.withinReadWriteTransaction { transaction in
      let data = try! await GivenSelectionSet(
        data:
          ["hero": [
            "__typename": "Droid",
            "name": "Artoo"
          ]],
        variables: nil
      )
      let cacheMutation = MockLocalCacheMutationFromMutation<GivenSelectionSet>()

      try await transaction.write(data: data, for: cacheMutation)
    }

    let mutation = MockMutation<GivenSelectionSet>()
    let graphQLResult = try await self.store.load(mutation)

    XCTAssertEqual(graphQLResult.source, .cache)
    XCTAssertNil(graphQLResult.errors)

    let data = try XCTUnwrap(graphQLResult.data)
    XCTAssertEqual(data.hero.name, "Artoo")
  }

  func test_writeDataForCacheMutation_givenInvalidData_throwsError() async throws {
    // given
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
          .field("name", String?.self)
        ]}

        var name: String? {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

    // when
    await expect {
      try await self.store.withinReadWriteTransaction { transaction in
        let data = GivenSelectionSet(
          _dataDict: .init(
            data: [
              "hero": "name"
            ],
            fulfilledFragments: [ObjectIdentifier(GivenSelectionSet.Hero.self)]
          ))
        let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()
        try await transaction.write(data: data, for: cacheMutation)
      }
    }.to(throwError(
      GraphQLExecutionError(path: ["hero"], underlying: JSONDecodingError.wrongType)
    ))
  }

  func test_writeDataForCacheMutation_givenNilValueForOptionalField_writesFieldWithNullValue() async throws {
    // given
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
          .field("name", String?.self)
        ]}

        var name: String? {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

    // when
    try await store.withinReadWriteTransaction { transaction in
      let data = GivenSelectionSet(
        _dataDict: .init(
          data: [
            "hero": DataDict(
              data: [
                "__typename": "Hero",
                "name": Optional<String>.none,
              ],
              fulfilledFragments: [ObjectIdentifier(GivenSelectionSet.Hero.self)]),

          ],
          fulfilledFragments: [ObjectIdentifier(GivenSelectionSet.self)]))
      let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()
      try await transaction.write(data: data, for: cacheMutation)
    }

    // then
    try await store.withinReadTransaction { transaction in
      let query = MockQuery<GivenSelectionSet>()
      let resultData = try await transaction.read(query: query)

      expect(resultData.hero.name).to(beNil())
    }
  }

  func test_writeDataForSelectionSet_givenFragment_updateNestedField_updatesObject() async throws {
    // given
    struct GivenFragment: MockMutableRootSelectionSet, Fragment {
      static var fragmentDefinition: StaticString { "" }

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
          .field("name", String.self)
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

    // Update Fragment
    try await store.withinReadWriteTransaction { transaction in
      let fragment = try! await GivenFragment(
        data:
          ["hero": [
            "__typename": "Droid",
            "name": "Artoo"
          ]],
        variables: nil
      )

      try await transaction.write(selectionSet: fragment, withKey: CacheReference.RootQuery.key)
    }

    let query = MockQuery<GivenFragment>()
    let graphQLResult = try await self.store.load(query)

    XCTAssertEqual(graphQLResult.source, .cache)
    XCTAssertNil(graphQLResult.errors)

    let data = try XCTUnwrap(graphQLResult.data)
    XCTAssertEqual(data.hero.name, "Artoo")
  }

  // MARK: - Write w/Selection Set Initializers

  @MainActor func test_writeDataForOperation_givenSelectionSetManuallyInitialized_withNullValueForField_fieldHasNullValue() async throws {
    // given
    struct Types {
      static let Query = Object(typename: "Query", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Query": return Types.Query
      default: XCTFail(); return nil
      }
    })

    class Data: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Query }
      override class var __selections: [Selection] {[
        .field("name", String?.self)
      ]}

      public var name: String? { __data["name"] }

      convenience init(
        name: String? = nil
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": Types.Query.typename,
          "name": name
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    try await store.withinReadWriteTransaction { transaction in
      let data = Data(name: nil)
      let query = MockQuery<Data>()
      try await transaction.write(data: data, for: query)
    }

    try await store.withinReadTransaction { transaction in
      let query = MockQuery<Data>()
      let resultData = try await transaction.read(query: query)

      expect(resultData.name).to(beNil())
      expect(resultData.hasNullValue(forKey: "name")).to(beTrue())
    }
  }

  @MainActor func test_writeDataForOperation_givenSelectionSetManuallyInitializedWithInclusionConditions_writesFieldsForInclusionConditions() async throws {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
      static let Query = Object(typename: "Query", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Data: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Query }
      override class var __selections: [Selection] {[
        .field("hero", Hero.self)
      ]}

      public var hero: Hero { __data["hero"] }

      convenience init(
        hero: Hero
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": Types.Query.typename,
          "hero": hero._fieldData,
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }

      class Hero: MockSelectionSet {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Human }
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .include(if: "a", .inlineFragment(IfA.self)),
          .include(if: "b", .inlineFragment(IfB.self))
        ]}

        var ifA: IfA? { _asInlineFragment() }
        var ifB: IfB? { _asInlineFragment() }

        class IfA: ConcreteMockTypeCase<Hero> {
          typealias Schema = MockSchemaMetadata
          override class var __parentType: any ParentType { Types.Human }
          override class var __selections: [Selection] {[
            .field("name", String.self),
            .include(if: !"c", .field("friend", Friend.self)),
            .include(if: !"d", .field("other", String?.self))
          ]}
          var name: String { __data["name"] }
          var friend: Friend? { __data["friend"] }
          var other: String? { __data["other"] }

          convenience init(
            name: String,
            friend: Friend? = nil,
            other: String? = nil
          ) {
            self.init(_dataDict: DataDict(data: [
              "__typename": Types.Human.typename,
              "name": name,
              "friend": friend._fieldData,
              "other": other
            ], fulfilledFragments: [
              ObjectIdentifier(Hero.self),
              ObjectIdentifier(Self.self)
            ]))
          }

          class Friend: MockSelectionSet {
            typealias Schema = MockSchemaMetadata

            override class var __parentType: any ParentType { Types.Human }
            override class var __selections: [Selection] {[
              .field("__typename", String.self),
              .field("name", String.self)
            ]}

            var name: String { __data["name"] }

            convenience init(
              name: String
            ) {
              self.init(_dataDict: DataDict(data: [
                "__typename": Types.Human.typename,
                "name": name,
              ], fulfilledFragments: [ObjectIdentifier(Friend.self)]))
            }

          }
        }

        class IfB: ConcreteMockTypeCase<Hero> {
          typealias Schema = MockSchemaMetadata
          override class var __parentType: any ParentType { Types.Human }
          override class var __selections: [Selection] {[
          ]}
          convenience init() {
            self.init(_dataDict: DataDict(data: [
              "__typename": Types.Human.typename,
            ], fulfilledFragments: [
              ObjectIdentifier(Hero.self),
              ObjectIdentifier(Self.self)
            ]))
          }
        }
      }
    }

    // when
    try await store.withinReadWriteTransaction { transaction in
      let data = Data(
        hero: .IfA(
          name: "Han Solo",
          friend: Data.Hero.IfA.Friend(name: "Leia Organa")
        ).asRootEntityType
      )
      let query = MockQuery<Data>()
      try await transaction.write(data: data, for: query)
    }

    try await store.withinReadTransaction { transaction in
      let query = MockQuery<Data>()
      query.__variables = ["a": true, "b": false, "c": false, "d": true]
      let resultData = try await transaction.read(query: query)

      expect(resultData.hero.ifA?.name).to(equal("Han Solo"))
      expect(resultData.hero.ifB).to(beNil())
      expect(resultData.hero.ifA?.friend?.name).to(equal("Leia Organa"))
      expect(resultData.hero.ifA?.friend?.other).to(beNil())

    }
  }

  @MainActor func test_writeDataForOperation_givenSelectionSetManuallyInitializedWithTypeCases_writesFieldForTypeCasesWithManuallyProvidedImplementedInterfaces() async throws {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
      static let Query = Object(typename: "Query", implementedInterfaces: [])
      static let Character = Interface(name: "Character", implementingObjects: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: return nil
      }
    })

    class GivenQuery: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Query }
      override class var __selections: [Selection] {[
        .field("hero", Hero.self)
      ]}

      public var hero: Hero { __data["hero"] }

      convenience init(
        hero: Hero
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": Types.Query.typename,
          "hero": hero._fieldData,
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }

      class Hero: MockSelectionSet {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Human }
        override class var __selections: [Selection] {[
          .inlineFragment(AsCharacter.self)
        ]}

        var asCharacter: AsCharacter? { _asInlineFragment() }

        class AsCharacter: ConcreteMockTypeCase<Hero> {
          typealias Schema = MockSchemaMetadata
          override class var __parentType: any ParentType { Types.Character }
          override class var __selections: [Selection] {[
            .field("name", String.self)
          ]}

          var name: String { __data["name"] }

          convenience init(
            __typename: String,
            name: String
          ) {
            self.init(_dataDict: DataDict(data: [
              "__typename": __typename,
              "name": name
            ], fulfilledFragments: [
              ObjectIdentifier(Self.self),
              ObjectIdentifier(Hero.self)
            ]))
          }
        }
      }
    }

    // when
    try await store.withinReadWriteTransaction { transaction in
      let data = GivenQuery(
        hero: .AsCharacter(
          __typename: "Person",
          name: "Han Solo"
        ).asRootEntityType
      )
      let query = MockQuery<GivenQuery>()
      try await transaction.write(data: data, for: query)
    }

    // then
    let heroKey = "QUERY_ROOT.hero"
    let records = try await self.cache.loadRecords(forKeys: [heroKey])
    let heroRecord = records[heroKey]

    expect(heroRecord?.fields["name"] as? String).to(equal("Han Solo"))
  }

  @MainActor func test_writeDataForOperation_givenSelectionSetManuallyInitializedWithNamedFragmentInInclusionConditionIsFulfilled_writesFieldsForNamedFragment() async throws {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
      static let Query = Object(typename: "Query", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Query": return Types.Query
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    struct GivenFragment: MockMutableRootSelectionSet, Fragment {
      static var fragmentDefinition: StaticString { "" }

      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ParentType { Types.Query }
      static var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      init(
        hero: Hero
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": Types.Query.typename,
          "hero": hero._fieldData
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }

      var hero: Hero {
        get { __data["hero"] }
        set { __data["hero"] = newValue }
      }

      struct Hero: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ParentType { Types.Human }
        static var __selections: [Selection] { [
          .field("name", String.self)
        ]}

        init(
          name: String
        ) {
          self.init(_dataDict: DataDict(data: [
            "__typename": Types.Human.typename,
            "name": name
          ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
        }

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

    class GivenQuery: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Query }
      override class var __selections: [Selection] {[
        .include(if: "a", [.inlineFragment(IfA.self)])
      ]}

      var ifA: IfA? { _asInlineFragment() }

      convenience init() {
        self.init(_dataDict: DataDict(data: [
          "__typename": Types.Query.typename,
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }

      class IfA: ConcreteMockTypeCase<GivenQuery> {
        typealias Schema = MockSchemaMetadata
        override class var __parentType: any ParentType { Types.Query }
        override class var __selections: [Selection] {[
          .fragment(GivenFragment.self)
        ]}

        public var hero: GivenFragment.Hero { __data["hero"] }

        convenience init(
          hero: GivenFragment.Hero
        ) {
          self.init(_dataDict: DataDict(data: [
            "__typename": Types.Query.typename,
            "hero": hero._fieldData,
          ], fulfilledFragments: [
            ObjectIdentifier(Self.self),
            ObjectIdentifier(GivenQuery.self),
            ObjectIdentifier(GivenFragment.self)
          ]))
        }
      }
    }

    // when
    try await store.withinReadWriteTransaction { transaction in
      let data = GivenQuery.IfA(
        hero: .init(name: "Han Solo")
      ).asRootEntityType
      let query = MockQuery<GivenQuery>()
      try await transaction.write(data: data, for: query)

    }

    try await store.withinReadTransaction { transaction in
      let query = MockQuery<GivenQuery>()
      query.__variables = ["a": true]
      let resultData = try await transaction.read(query: query)

      expect(resultData.ifA?.hero.name).to(equal("Han Solo"))

    }
  }

  @MainActor func test_writeDataForOperation_givenSelectionSetManuallyInitializedWithNamedFragmentInInclusionConditionNotFulfilled_doesNotAttemptToWriteFieldsForNamedFragment() async throws {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
      static let Query = Object(typename: "Query", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Query": return Types.Query
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    struct GivenFragment: MockMutableRootSelectionSet, Fragment {
      static var fragmentDefinition: StaticString { "" }

      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      init(
        hero: Hero
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": Types.Query.typename,
          "hero": hero._fieldData,
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }

      var hero: Hero {
        get { __data["hero"] }
        set { __data["hero"] = newValue }
      }

      struct Hero: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] { [
          .field("name", String.self)
        ]}

        init(
          name: String
        ) {
          self.init(_dataDict: DataDict(data: [
            "__typename": Types.Human.typename,
            "name": name,
          ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
        }

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

    class GivenQuery: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Query }
      override class var __selections: [Selection] {[
        .include(if: "a", [.inlineFragment(IfA.self)])
      ]}

      var ifA: IfA? { _asInlineFragment() }

      convenience init() {
        self.init(_dataDict: DataDict(data: [
          "__typename": Types.Query.typename
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }

      class IfA: ConcreteMockTypeCase<GivenQuery> {
        typealias Schema = MockSchemaMetadata
        override class var __parentType: any ParentType { Types.Query }
        override class var __selections: [Selection] {[
          .fragment(GivenFragment.self)
        ]}

        public var hero: GivenFragment.Hero { __data["hero"] }

        convenience init(
          hero: GivenFragment.Hero
        ) {
          self.init(_dataDict: DataDict(data: [
            "__typename": Types.Query.typename,
            "hero": hero._fieldData,
          ], fulfilledFragments: [
            ObjectIdentifier(Self.self),
            ObjectIdentifier(GivenQuery.self),
            ObjectIdentifier(GivenFragment.self)
          ]))
        }
      }
    }

    // when
    try await store.withinReadWriteTransaction { transaction in
      let data = GivenQuery()
      let query = MockQuery<GivenQuery>()
      try await transaction.write(data: data, for: query)
    }
  }

  // MARK: - Update Object With Key Tests

  func test_updateObjectWithKey_readAfterUpdateWithinSameTransaction_hasUpdatedValue() async throws {
    // given
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
          .field("name", String.self)
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("QUERY_ROOT.hero")],
      "QUERY_ROOT.hero": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // then
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.updateObject(
        ofType: GivenSelectionSet.self,
        withKey: "QUERY_ROOT", { data in
          data.hero.name = "Artoo"
        })

      let data = try await transaction.readObject(
        ofType: GivenSelectionSet.self,
        withKey: "QUERY_ROOT"
      )

      XCTAssertEqual(data.hero.name, "Artoo")
    }
  }

  func testUpdateObjectWithKey_givenFragment_updatesObject() async throws {
    /// given
    struct GivenFragment: MockMutableRootSelectionSet, Fragment {
      static var fragmentDefinition: StaticString { "" }

      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] { [
        .field("__typename", String.self),
        .field("id", String.self),
        .field("friends", [Friend].self),
      ]}

      var friends: [Friend] {
        get { __data["friends"] }
        set { __data["friends"] = newValue }
      }

      struct Friend: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] { [
          .field("__typename", String.self),
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

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "id": "2001",
        "__typename": "Droid",
        "friends": [
          CacheReference("1000"),
          CacheReference("1002"),
          CacheReference("1003")
        ]
      ],
      "1000": ["__typename": "Human", "name": "Luke Skywalker", "id": "1000"],
      "1002": ["__typename": "Human", "name": "Han Solo", "id": "1002"],
      "1003": ["__typename": "Human", "name": "Leia Organa", "id": "1003"],
    ])

    try await store.withinReadWriteTransaction { transaction in
      try await transaction.updateObject(
        ofType: GivenFragment.self,
        withKey: "2001"
      ) { friendsNamesFragment in
        var c3po = GivenFragment.Friend()
        c3po.__typename = "Droid"
        c3po.id = "1004"
        c3po.name = "C-3PO"

        friendsNamesFragment.friends.append(c3po)
      }
    }

    class HeroFriendsSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("id", String.self),
          .field("name", String.self),
          .field("friends", [Friend].self)
        ]}

        var friends: [Friend] { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
          ]}
        }
      }
    }

    let query = MockQuery<HeroFriendsSelectionSet>()
    let graphQLResult = try await self.store.load(query)
    XCTAssertEqual(graphQLResult.source, .cache)
    XCTAssertNil(graphQLResult.errors)

    let data = try XCTUnwrap(graphQLResult.data)
    XCTAssertEqual(data.hero.name, "R2-D2")
    let friendsNames: [String] = data.hero.friends.compactMap { $0.name }
    XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa", "C-3PO"])
  }

  // MARK: - Remove Object

  func test_removeObject_givenReferencedByOtherRecord_thenReadQueryReferencingRemovedRecord_throwsError() async throws {
    /// given
    struct GivenSelectionSet: MockMutableRootSelectionSet {
      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      var hero: Hero? {
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

          var name: String {
            get { __data["name"] }
            set { __data["name"] = newValue }
          }
        }
      }
    }

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "id": "2001",
        "__typename": "Droid",
        "friends": [
          CacheReference("1000"),
          CacheReference("1002"),
          CacheReference("1003")
        ]
      ],
      "1000": ["__typename": "Human", "name": "Luke Skywalker", "id": "1000"],
      "1002": ["__typename": "Human", "name": "Han Solo", "id": "1002"],
      "1003": ["__typename": "Human", "name": "Leia Organa", "id": "1003"],
    ])

    // Delete record for Leia Organa
    try await store.withinReadWriteTransaction { transaction in
      try await transaction.removeObject(for: "1003")
    }

    // Read query with deleted record reference
    let query = MockQuery<GivenSelectionSet>()

    await expect{
      try await self.store.withinReadTransaction { transaction in
        _ = try await transaction.read(query: query)
      }
    }.to(throwError(
      GraphQLExecutionError(path: ["hero", "friends", "2"], underlying: JSONDecodingError.missingValue)
    ))
  }

  func test_removeObjectsMatchingPattern_givenPatternNotMatchingKeyCase_deletesCaseInsensitiveMatchingRecords() async throws {
    // given
    class HeroNameSelectionSet: MockSelectionSet {
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

    let query = MockQuery<HeroNameSelectionSet>()

    // then
    let heroKey = "hero"

    //
    // 1. Merge all required records into the cache with lowercase key
    //

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["\(heroKey.lowercased())": CacheReference("QUERY_ROOT.\(heroKey.lowercased())")],
      "QUERY_ROOT.\(heroKey.lowercased())": ["__typename": "Droid", "name": "R2-D2"]
    ])

    //
    // 2. Remove object matching case insensitive (uppercase) key
    // - This should remove `QUERY_ROOT.hero` using pattern `QUERY_ROOT.HERO`
    //

    try await store.withinReadWriteTransaction { transaction in
      try await transaction.removeObjects(matching: "\(heroKey.uppercased())")
    }

    //
    // 3. Attempt to read records after pattern removal - expected FAIL
    //

    await expect {
      try await self.store.withinReadTransaction { transaction in
        _ = try await transaction.read(query: query)
      }
    }.to(throwError(
      GraphQLExecutionError(path: ["hero"], underlying: JSONDecodingError.missingValue)
    ))
  }

  func test_removeObjectsMatchingPattern_givenKeyMatchingSubrangePattern_deletesMultipleRecords() async throws {
    // given
    enum Episode: String, EnumType {
      case NEWHOPE
      case JEDI
      case EMPIRE
    }

    class HeroFriendsSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["episode": .variable("episode")])
      ]}

      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("id", String.self),
          .field("name", String.self),
          .field("friends", [Friend].self)
        ]}

        var friends: [Friend] { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("id", String.self),
            .field("name", String.self),
          ]}
        }
      }
    }

    //
    // 1. Merge all required records into the cache
    //
    await mergeRecordsIntoCache([
      "QUERY_ROOT": [
        "hero(episode:NEWHOPE)": CacheReference("1002"),
        "hero(episode:JEDI)": CacheReference("1101"),
        "hero(episode:EMPIRE)": CacheReference("2001")
      ],
      "2001": [
        "id": "2001",
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": [
          CacheReference("1101"),
          CacheReference("1003")
        ]
      ],
      "1101": [
        "__typename": "Human", "name": "Luke Skywalker", "id": "1101", "friends": [] as JSONValue
      ],
      "1002": [
        "__typename": "Human", "name": "Han Solo", "id": "1002", "friends": [] as JSONValue
      ],
      "1003": [
        "__typename": "Human", "name": "Leia Organa", "id": "1003", "friends": [] as JSONValue
      ],
    ])

    //
    // 2. Remove all objects matching the pattern `100`
    // - This will remove `1002` (Han Solo, hero for the .newhope episode)
    // - This will remove `1003` (Leia Organa, friend of the hero in .empire episode)
    //

    try await store.withinReadWriteTransaction { transaction in
      try await transaction.removeObjects(matching: "100")
    }

    //
    // 3. Attempt to read records after pattern removal
    // - .newhope episode query expected to FAIL on the `hero` path
    // - .jedi episdoe query expected to SUCCEED
    // - .empire episode query expected to FAIL on the `hero.friends` path
    //

    await expect {
      try await self.store.withinReadTransaction{ transaction in
        let query = MockQuery<HeroFriendsSelectionSet>()
        query.__variables = ["episode": "NEWHOPE"]
        _ = try await transaction.read(query: query)

      }
    }.to(throwError(
      GraphQLExecutionError(path: ["hero"], underlying: JSONDecodingError.missingValue)
    ))

    try await store.withinReadTransaction { transaction in
      let query = MockQuery<HeroFriendsSelectionSet>()
      query.__variables = ["episode": "JEDI"]
      let data = try await transaction.read(query: query)

      XCTAssertEqual(data.hero.__typename, "Human")
      XCTAssertEqual(data.hero.name, "Luke Skywalker")

    }

    await expect {
      try await self.store.withinReadTransaction { transaction in
        let query = MockQuery<HeroFriendsSelectionSet>()
        query.__variables = ["episode": "EMPIRE"]
        _ = try await transaction.read(query: query)

      }
    }.to(throwError(
      GraphQLExecutionError(path: ["hero", "friends", "1"], underlying: JSONDecodingError.missingValue)
    ))
  }

  // MARK: Memory Leak Tests

  func test_readTransaction_readQuery_afterTransaction_releasesReadTransaction() async throws {
    // given
    class HeroNameSelectionSet: MockSelectionSet {
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

    let query = MockQuery<HeroNameSelectionSet>()

    await mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // when
    nonisolated(unsafe) weak var readTransaction: ApolloStore.ReadTransaction?

    try await store.withinReadTransaction { transaction in
      readTransaction = transaction

      let data = try await transaction.read(query: query)

      expect(data.hero?.__typename).to(equal("Droid"))
      expect(data.hero?.name).to(equal("R2-D2"))
    }

    expect(readTransaction).to(beNil())
  }
}
