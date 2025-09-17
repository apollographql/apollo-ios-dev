import XCTest
@_spi(Execution)
@testable import Apollo

@_spi(Execution)
@_spi(Internal)
@_spi(Unsafe)
import ApolloAPI

@_spi(Execution)
@_spi(Unsafe)
import ApolloInternalTestHelpers

import Nimble

final class FieldPolicyTests: XCTestCase, CacheDependentTesting, @unchecked Sendable {
  var store: Apollo.ApolloStore!

  var cacheType: any TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }
  
  static let defaultWaitTimeout: TimeInterval = 1.0
  
  var cache: (any NormalizedCache)!
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
    cache = nil
    server = nil
    client = nil
    
    try super.tearDownWithError()
  }
  
  // MARK: - Single Key Argument Tests
  
  func test_fieldPolicy_withStringKeyArgument_resolvesCorrectCacheKey() async throws {
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["name": .variable("name")], fieldPolicy: .init(keyArgs: ["name"]))
      ]}
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["name": "Luke"]
    
    try await store.publish(records: [
      "QUERY_ROOT": ["Hero:Luke": CacheReference("Hero:Luke")],
      "Hero:Luke": [
        "age": 19,
        "isJedi": true,
        "name": "Luke",
        "weight": 175.2,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)

    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)

    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.hero?.name, "Luke")
    XCTAssertEqual(data.hero?.age, 19)
    XCTAssertEqual(data.hero?.isJedi, true)
    XCTAssertEqual(data.hero?.weight, 175.2)
  }
  
  func test_fieldPolicy_withIntKeyArgument_resolvesCorrectCacheKey() async throws {
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["age": .variable("age")], fieldPolicy: .init(keyArgs: ["age"]))
      ]}
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["age": 19]
    
    try await store.publish(records: [
      "QUERY_ROOT": ["Hero:19": CacheReference("Hero:19")],
      "Hero:19": [
        "age": 19,
        "isJedi": true,
        "name": "Luke",
        "weight": 175.2,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.hero?.name, "Luke")
    XCTAssertEqual(data.hero?.age, 19)
    XCTAssertEqual(data.hero?.isJedi, true)
    XCTAssertEqual(data.hero?.weight, 175.2)
  }
  
  func test_fieldPolicy_withDoubleKeyArgument_resolvesCorrectCacheKey() async throws {
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["weight": .variable("weight")], fieldPolicy: .init(keyArgs: ["weight"]))
      ]}
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["weight": 175.2]
    
    try await store.publish(records: [
      "QUERY_ROOT": ["Hero:175.2": CacheReference("Hero:175.2")],
      "Hero:175.2": [
        "age": 19,
        "isJedi": true,
        "name": "Luke",
        "weight": 175.2,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.hero?.name, "Luke")
    XCTAssertEqual(data.hero?.age, 19)
    XCTAssertEqual(data.hero?.isJedi, true)
    XCTAssertEqual(data.hero?.weight, 175.2)
  }
  
  func test_fieldPolicy_withBoolKeyArgument_resolvesCorrectCacheKey() async throws {
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["isJedi": .variable("isJedi")], fieldPolicy: .init(keyArgs: ["isJedi"]))
      ]}
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["isJedi": true]
    
    try await store.publish(records: [
      "QUERY_ROOT": ["Hero:true": CacheReference("Hero:true")],
      "Hero:true": [
        "age": 19,
        "isJedi": true,
        "name": "Luke",
        "weight": 175.2,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.hero?.name, "Luke")
    XCTAssertEqual(data.hero?.age, 19)
    XCTAssertEqual(data.hero?.isJedi, true)
    XCTAssertEqual(data.hero?.weight, 175.2)
  }
  
  func test_fieldPolicy_withListKeyArgument_resolvesCorrectCacheKey() async throws {
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("heroes", [Hero].self, arguments: ["names": .variable("names")], fieldPolicy: .init(keyArgs: ["names"]))
      ]}
      var heroes: [Hero] { __data["heroes"] }
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["names": ["Anakin", "Obi-Wan", "Ahsoka"]]
    
    try await store.publish(records: [
      "QUERY_ROOT": [
        "Hero:Anakin": CacheReference("Hero:Anakin"),
        "Hero:Obi-Wan": CacheReference("Hero:Obi-Wan"),
        "Hero:Ahsoka": CacheReference("Hero:Ahsoka")
      ],
      "Hero:Anakin": [
        "age": 23,
        "isJedi": true,
        "name": "Anakin",
        "weight": 185.3,
        "__typename": "Hero",
      ],
      "Hero:Obi-Wan": [
        "age": 30,
        "isJedi": true,
        "name": "Obi-Wan",
        "weight": 179.7,
        "__typename": "Hero",
      ],
      "Hero:Ahsoka": [
        "age": 17,
        "isJedi": true,
        "name": "Ahsoka",
        "weight": 138.5,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.heroes[0].name, "Anakin")
    XCTAssertEqual(data.heroes[0].age, 23)
    XCTAssertEqual(data.heroes[0].isJedi, true)
    XCTAssertEqual(data.heroes[0].weight, 185.3)
    
    XCTAssertEqual(data.heroes[1].name, "Obi-Wan")
    XCTAssertEqual(data.heroes[1].age, 30)
    XCTAssertEqual(data.heroes[1].isJedi, true)
    XCTAssertEqual(data.heroes[1].weight, 179.7)
    
    XCTAssertEqual(data.heroes[2].name, "Ahsoka")
    XCTAssertEqual(data.heroes[2].age, 17)
    XCTAssertEqual(data.heroes[2].isJedi, true)
    XCTAssertEqual(data.heroes[2].weight, 138.5)
  }
  
  func test_fieldPolicy_withObjectKeyArgument_resolvesCorrectCacheKey() async throws {
    struct HeroSearchInput: InputObject {
      public private(set) var __data: InputDict
      
      public init(_ data: InputDict) {
        __data = data
      }
      
      public init(name: String) {
        __data = InputDict([
          "name": name
        ])
      }
      
      public var name: String {
        get { __data["name"] }
        set { __data["name"] = newValue }
      }
    }
    
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["input": .variable("input")], fieldPolicy: .init(keyArgs: ["input.name"]))
      ]}
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["input": HeroSearchInput(name: "Luke")]
    
    try await store.publish(records: [
      "QUERY_ROOT": ["Hero:Luke": CacheReference("Hero:Luke")],
      "Hero:Luke": [
        "age": 19,
        "isJedi": true,
        "name": "Luke",
        "weight": 175.2,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.hero?.name, "Luke")
    XCTAssertEqual(data.hero?.age, 19)
    XCTAssertEqual(data.hero?.isJedi, true)
    XCTAssertEqual(data.hero?.weight, 175.2)
  }
  
  func test_fieldPolicy_withNestedObjectKeyArgument_resolvesCorrectCacheKey() async throws {
    struct NameInput: InputObject {
      public private(set) var __data: InputDict
      
      public init(_ data: InputDict) {
        __data = data
      }
      
      public init (name: String) {
        __data = InputDict([
          "name": name
        ])
      }
      
      public var name: String {
        get { __data["name"] }
        set { __data["name"] = newValue }
      }
    }
    
    struct HeroSearchInput: InputObject {
      public private(set) var __data: InputDict
      
      public init(_ data: InputDict) {
        __data = data
      }
      
      public init(nameInput: NameInput) {
        __data = InputDict([
          "nameInput": nameInput
        ])
      }
      
      public var nameInput: NameInput {
        get { __data["nameInput"] }
        set { __data["nameInput"] = newValue }
      }
    }
    
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["input": .variable("input")], fieldPolicy: .init(keyArgs: ["input.nameInput.name"]))
      ]}
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["input": HeroSearchInput(nameInput: NameInput(name: "Luke"))]
    
    try await store.publish(records: [
      "QUERY_ROOT": ["Hero:Luke": CacheReference("Hero:Luke")],
      "Hero:Luke": [
        "age": 19,
        "isJedi": true,
        "name": "Luke",
        "weight": 175.2,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.hero?.name, "Luke")
    XCTAssertEqual(data.hero?.age, 19)
    XCTAssertEqual(data.hero?.isJedi, true)
    XCTAssertEqual(data.hero?.weight, 175.2)
  }
  
  func test_fieldPolicy_withNestedObjectListKeyArgument_resolvesCorrectCacheKey() async throws {
    struct NameInput: InputObject {
      public private(set) var __data: InputDict
      
      public init(_ data: InputDict) {
        __data = data
      }
      
      public init (names: [String]) {
        __data = InputDict([
          "names": names
        ])
      }
      
      public var names: [String] {
        get { __data["names"] }
        set { __data["names"] = newValue }
      }
    }
    
    struct HeroSearchInput: InputObject {
      public private(set) var __data: InputDict
      
      public init(_ data: InputDict) {
        __data = data
      }
      
      public init(nameInput: NameInput) {
        __data = InputDict([
          "nameInput": nameInput
        ])
      }
      
      public var nameInput: NameInput {
        get { __data["nameInput"] }
        set { __data["nameInput"] = newValue }
      }
    }
    
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("heroes", [Hero].self, arguments: ["input": .variable("input")], fieldPolicy: .init(keyArgs: ["input.nameInput.names"]))
      ]}
      var heroes: [Hero] { __data["heroes"] }
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["input": HeroSearchInput(nameInput: NameInput(names: ["Anakin", "Obi-Wan", "Ahsoka"]))]
    
    try await store.publish(records: [
      "QUERY_ROOT": [
        "Hero:Anakin": CacheReference("Hero:Anakin"),
        "Hero:Obi-Wan": CacheReference("Hero:Obi-Wan"),
        "Hero:Ahsoka": CacheReference("Hero:Ahsoka")
      ],
      "Hero:Anakin": [
        "age": 23,
        "isJedi": true,
        "name": "Anakin",
        "weight": 185.3,
        "__typename": "Hero",
      ],
      "Hero:Obi-Wan": [
        "age": 30,
        "isJedi": true,
        "name": "Obi-Wan",
        "weight": 179.7,
        "__typename": "Hero",
      ],
      "Hero:Ahsoka": [
        "age": 17,
        "isJedi": true,
        "name": "Ahsoka",
        "weight": 138.5,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.heroes[0].name, "Anakin")
    XCTAssertEqual(data.heroes[0].age, 23)
    XCTAssertEqual(data.heroes[0].isJedi, true)
    XCTAssertEqual(data.heroes[0].weight, 185.3)
    
    XCTAssertEqual(data.heroes[1].name, "Obi-Wan")
    XCTAssertEqual(data.heroes[1].age, 30)
    XCTAssertEqual(data.heroes[1].isJedi, true)
    XCTAssertEqual(data.heroes[1].weight, 179.7)
    
    XCTAssertEqual(data.heroes[2].name, "Ahsoka")
    XCTAssertEqual(data.heroes[2].age, 17)
    XCTAssertEqual(data.heroes[2].isJedi, true)
    XCTAssertEqual(data.heroes[2].weight, 138.5)
  }
  
  // MARK: - Multiple Key Argument Tests
  
  func test_fieldPolicy_withMultipleKeyArguments_resolvesCorrectCacheKey() async throws {
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["name": .variable("name"), "age": .variable("age")], fieldPolicy: .init(keyArgs: ["name", "age"]))
      ]}
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["name": "Luke", "age": 19]
    
    try await store.publish(records: [
      "QUERY_ROOT": ["Hero:Luke+19": CacheReference("Hero:Luke+19")],
      "Hero:Luke+19": [
        "age": 19,
        "isJedi": true,
        "name": "Luke",
        "weight": 175.2,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.hero?.name, "Luke")
    XCTAssertEqual(data.hero?.age, 19)
    XCTAssertEqual(data.hero?.isJedi, true)
    XCTAssertEqual(data.hero?.weight, 175.2)
  }
  
  func test_fieldPolicy_withMultipleKeyArguments_withDifferentOrder_resolvesCorrectCacheKey() async throws {
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["name": .variable("name"), "age": .variable("age")], fieldPolicy: .init(keyArgs: ["age", "name"]))
      ]}
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["name": "Luke", "age": 19]
    
    try await store.publish(records: [
      "QUERY_ROOT": ["Hero:19+Luke": CacheReference("Hero:19+Luke")],
      "Hero:19+Luke": [
        "age": 19,
        "isJedi": true,
        "name": "Luke",
        "weight": 175.2,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.hero?.name, "Luke")
    XCTAssertEqual(data.hero?.age, 19)
    XCTAssertEqual(data.hero?.isJedi, true)
    XCTAssertEqual(data.hero?.weight, 175.2)
  }
  
  func test_fieldPolicy_withMultipleKeyArguments_includingList_resolvesCorrectCacheKey() async throws {
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("heroes", [Hero].self, arguments: ["names": .variable("names"), "isJedi": .variable("isJedi")], fieldPolicy: .init(keyArgs: ["names", "isJedi"]))
      ]}
      var heroes: [Hero] { __data["heroes"] }
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["names": ["Anakin", "Obi-Wan", "Ahsoka"], "isJedi": true]
    
    try await store.publish(records: [
      "QUERY_ROOT": [
        "Hero:Anakin+true": CacheReference("Hero:Anakin+true"),
        "Hero:Obi-Wan+true": CacheReference("Hero:Obi-Wan+true"),
        "Hero:Ahsoka+true": CacheReference("Hero:Ahsoka+true")
      ],
      "Hero:Anakin+true": [
        "age": 23,
        "isJedi": true,
        "name": "Anakin",
        "weight": 185.3,
        "__typename": "Hero",
      ],
      "Hero:Obi-Wan+true": [
        "age": 30,
        "isJedi": true,
        "name": "Obi-Wan",
        "weight": 179.7,
        "__typename": "Hero",
      ],
      "Hero:Ahsoka+true": [
        "age": 17,
        "isJedi": true,
        "name": "Ahsoka",
        "weight": 138.5,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.heroes[0].name, "Anakin")
    XCTAssertEqual(data.heroes[0].age, 23)
    XCTAssertEqual(data.heroes[0].isJedi, true)
    XCTAssertEqual(data.heroes[0].weight, 185.3)
    
    XCTAssertEqual(data.heroes[1].name, "Obi-Wan")
    XCTAssertEqual(data.heroes[1].age, 30)
    XCTAssertEqual(data.heroes[1].isJedi, true)
    XCTAssertEqual(data.heroes[1].weight, 179.7)
    
    XCTAssertEqual(data.heroes[2].name, "Ahsoka")
    XCTAssertEqual(data.heroes[2].age, 17)
    XCTAssertEqual(data.heroes[2].isJedi, true)
    XCTAssertEqual(data.heroes[2].weight, 138.5)
  }
  
  func test_fieldPolicy_withMultipleKeyArguments_includingObject_resolvesCorrectCacheKey() async throws {
    struct HeroSearchInput: InputObject {
      public private(set) var __data: InputDict
      
      public init(_ data: InputDict) {
        __data = data
      }
      
      public init(
        name: String,
        isJedi: Bool
      ) {
        __data = InputDict([
          "name": name,
          "isJedi": true
        ])
      }
      
      public var name: String {
        get { __data["name"] }
        set { __data["name"] = newValue }
      }
      
      public var isJedi: Bool {
        get { __data["isJedi"] }
        set { __data["isJedi"] = newValue }
      }
    }
    
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["input": .variable("input")], fieldPolicy: .init(keyArgs: ["input.name", "input.isJedi"]))
      ]}
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["input": HeroSearchInput(name: "Luke", isJedi: true)]
    
    try await store.publish(records: [
      "QUERY_ROOT": ["Hero:Luke+true": CacheReference("Hero:Luke+true")],
      "Hero:Luke+true": [
        "age": 19,
        "isJedi": true,
        "name": "Luke",
        "weight": 175.2,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.hero?.name, "Luke")
    XCTAssertEqual(data.hero?.age, 19)
    XCTAssertEqual(data.hero?.isJedi, true)
    XCTAssertEqual(data.hero?.weight, 175.2)
  }
  
  func test_fieldPolicy_withMultipleKeyArguments_includingNestedObject_resolvesCorrectCacheKey() async throws {
    struct NameInput: InputObject {
      public private(set) var __data: InputDict
      
      public init(_ data: InputDict) {
        __data = data
      }
      
      public init(
        name: String
      ) {
        __data = InputDict([
          "name": name
        ])
      }
      
      public var name: String {
        get { __data["name"] }
        set { __data["name"] = newValue }
      }
    }
    
    struct HeroSearchInput: InputObject {
      public private(set) var __data: InputDict
      
      public init(_ data: InputDict) {
        __data = data
      }
      
      public init(
        nameInput: NameInput,
        isJedi: Bool
      ) {
        __data = InputDict([
          "nameInput": nameInput,
          "isJedi": isJedi
        ])
      }
      
      public var nameInput: NameInput {
        get { __data["nameInput"] }
        set { __data["nameInput"] = newValue }
      }
      
      public var isJedi: Bool {
        get { __data["isJedi"] }
        set { __data["isJedi"] = newValue }
      }
    }
    
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["input": .variable("input")], fieldPolicy: .init(keyArgs: ["input.nameInput.name", "input.isJedi"]))
      ]}
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["input": HeroSearchInput(nameInput: NameInput(name: "Luke"), isJedi: true)]
    
    try await store.publish(records: [
      "QUERY_ROOT": ["Hero:Luke+true": CacheReference("Hero:Luke+true")],
      "Hero:Luke+true": [
        "age": 19,
        "isJedi": true,
        "name": "Luke",
        "weight": 175.2,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.hero?.name, "Luke")
    XCTAssertEqual(data.hero?.age, 19)
    XCTAssertEqual(data.hero?.isJedi, true)
    XCTAssertEqual(data.hero?.weight, 175.2)
  }
  
  func test_fieldPolicy_withMultipleKeyArguments_includingNestedObjectList_resolvesCorrectCacheKey() async throws {
    struct NameInput: InputObject {
      public private(set) var __data: InputDict
      
      public init(_ data: InputDict) {
        __data = data
      }
      
      public init (names: [String]) {
        __data = InputDict([
          "names": names
        ])
      }
      
      public var names: [String] {
        get { __data["names"] }
        set { __data["names"] = newValue }
      }
    }
    
    struct HeroSearchInput: InputObject {
      public private(set) var __data: InputDict
      
      public init(_ data: InputDict) {
        __data = data
      }
      
      public init(
        nameInput: NameInput,
        isJedi: Bool
      ) {
        __data = InputDict([
          "nameInput": nameInput,
          "isJedi": isJedi
        ])
      }
      
      public var nameInput: NameInput {
        get { __data["nameInput"] }
        set { __data["nameInput"] = newValue }
      }
      
      public var isJedi: Bool {
        get { __data["isJedi"] }
        set { __data["isJedi"] = newValue }
      }
    }
    
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("heroes", [Hero].self, arguments: ["input": .variable("input")], fieldPolicy: .init(keyArgs: ["input.nameInput.names", "input.isJedi"]))
      ]}
      var heroes: [Hero] { __data["heroes"] }
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["input": HeroSearchInput(nameInput: NameInput(names: ["Anakin", "Obi-Wan", "Ahsoka"]), isJedi: true)]
    
    try await store.publish(records: [
      "QUERY_ROOT": [
        "Hero:Anakin+true": CacheReference("Hero:Anakin+true"),
        "Hero:Obi-Wan+true": CacheReference("Hero:Obi-Wan+true"),
        "Hero:Ahsoka+true": CacheReference("Hero:Ahsoka+true")
      ],
      "Hero:Anakin+true": [
        "age": 23,
        "isJedi": true,
        "name": "Anakin",
        "weight": 185.3,
        "__typename": "Hero",
      ],
      "Hero:Obi-Wan+true": [
        "age": 30,
        "isJedi": true,
        "name": "Obi-Wan",
        "weight": 179.7,
        "__typename": "Hero",
      ],
      "Hero:Ahsoka+true": [
        "age": 17,
        "isJedi": true,
        "name": "Ahsoka",
        "weight": 138.5,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.heroes[0].name, "Anakin")
    XCTAssertEqual(data.heroes[0].age, 23)
    XCTAssertEqual(data.heroes[0].isJedi, true)
    XCTAssertEqual(data.heroes[0].weight, 185.3)
    
    XCTAssertEqual(data.heroes[1].name, "Obi-Wan")
    XCTAssertEqual(data.heroes[1].age, 30)
    XCTAssertEqual(data.heroes[1].isJedi, true)
    XCTAssertEqual(data.heroes[1].weight, 179.7)
    
    XCTAssertEqual(data.heroes[2].name, "Ahsoka")
    XCTAssertEqual(data.heroes[2].age, 17)
    XCTAssertEqual(data.heroes[2].isJedi, true)
    XCTAssertEqual(data.heroes[2].weight, 138.5)
  }
  
  // MARK: - FieldPolicyProvider Tests
  
  func test_schemaConfiguration_givenFieldPolicyProvider_returnsSingleCacheKeyInfo() async throws {
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["name": .variable("name")])
      ]}
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    await FieldPolicySchemaMetadata.stub_cacheKeyForField_SingleReturn { _, _, _ in
      return CacheKeyInfo(id: "Luke")
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["name": "Luke"]
    
    try await store.publish(records: [
      "QUERY_ROOT": ["Hero:Luke": CacheReference("Hero:Luke")],
      "Hero:Luke": [
        "age": 19,
        "isJedi": true,
        "name": "Luke",
        "weight": 175.2,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.hero?.name, "Luke")
    XCTAssertEqual(data.hero?.age, 19)
    XCTAssertEqual(data.hero?.isJedi, true)
    XCTAssertEqual(data.hero?.weight, 175.2)
  }
  
  func test_schemaConfiguration_givenFieldPolicyProvider_returnsListOfCacheKeyInfo() async throws {
    class HeroSelectionSet: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("heroes", [Hero].self, arguments: ["names": .variable("names")])
      ]}
      var heroes: [Hero] { __data["heroes"] }
      
      class Hero: AbstractMockSelectionSet<NoFragments, FieldPolicySchemaMetadata>, @unchecked Sendable {
        override class var __parentType: any ParentType {
          Object(typename: "Hero", implementedInterfaces: [])
        }
        override class var __selections: [Selection] { [
          .field("__typename", String.self),
          .field("age", Int.self),
          .field("name", String.self),
          .field("isJedi", Bool.self),
          .field("weight", Double.self)
        ]}
      }
    }
    
    await FieldPolicySchemaMetadata.stub_cacheKeyForField_ListReturn { _, _, _ in
      return [
        CacheKeyInfo(id: "Anakin"),
        CacheKeyInfo(id: "Obi-Wan"),
        CacheKeyInfo(id: "Ahsoka")
      ]
    }
    
    let query = MockQuery<HeroSelectionSet>()
    query.__variables = ["names": ["Anakin", "Obi-Wan", "Ahsoka"]]
    
    try await store.publish(records: [
      "QUERY_ROOT": [
        "Hero:Anakin": CacheReference("Hero:Anakin"),
        "Hero:Obi-Wan": CacheReference("Hero:Obi-Wan"),
        "Hero:Ahsoka": CacheReference("Hero:Ahsoka")
      ],
      "Hero:Anakin": [
        "age": 23,
        "isJedi": true,
        "name": "Anakin",
        "weight": 185.3,
        "__typename": "Hero",
      ],
      "Hero:Obi-Wan": [
        "age": 30,
        "isJedi": true,
        "name": "Obi-Wan",
        "weight": 179.7,
        "__typename": "Hero",
      ],
      "Hero:Ahsoka": [
        "age": 17,
        "isJedi": true,
        "name": "Ahsoka",
        "weight": 138.5,
        "__typename": "Hero",
      ]
    ])
    
    let graphQLResult = try await client.fetch(query: query, cachePolicy: .cacheOnly)
        
    XCTAssertEqual(graphQLResult?.source, .cache)
    XCTAssertNil(graphQLResult?.errors)
    
    let data = try XCTUnwrap(graphQLResult?.data)
    XCTAssertEqual(data.heroes[0].name, "Anakin")
    XCTAssertEqual(data.heroes[0].age, 23)
    XCTAssertEqual(data.heroes[0].isJedi, true)
    XCTAssertEqual(data.heroes[0].weight, 185.3)
    
    XCTAssertEqual(data.heroes[1].name, "Obi-Wan")
    XCTAssertEqual(data.heroes[1].age, 30)
    XCTAssertEqual(data.heroes[1].isJedi, true)
    XCTAssertEqual(data.heroes[1].weight, 179.7)
    
    XCTAssertEqual(data.heroes[2].name, "Ahsoka")
    XCTAssertEqual(data.heroes[2].age, 17)
    XCTAssertEqual(data.heroes[2].isJedi, true)
    XCTAssertEqual(data.heroes[2].weight, 138.5)
  }
  
}

class FieldPolicySchemaMetadata: SchemaMetadata {
  init() { }

  nonisolated(unsafe) static var _configuration: SchemaConfiguration.Type = SchemaConfiguration.self
  static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

  @MainActor
  private static let testObserver = TestObserver() { _ in
    stub_objectTypeForTypeName(nil)
    stub_cacheKeyInfoForType_Object(nil)
  }

  private nonisolated(unsafe) static var _objectTypeForTypeName: ((String) -> Object?)?
  static var objectTypeForTypeName: ((String) -> Object?)? {
      _objectTypeForTypeName
  }

  @MainActor
  static func stub_objectTypeForTypeName(_ stub: ((String) -> Object?)?) {
    _objectTypeForTypeName = stub
    if _objectTypeForTypeName != nil {
      testObserver.start()
    }
  }

  @MainActor
  static func stub_cacheKeyInfoForType_Object(
    _ stub: ((Object, ObjectData) -> CacheKeyInfo?)?
  ){
    _configuration.stub_cacheKeyInfoForType_Object = stub
    if stub != nil {
      testObserver.start()
    }
  }
  
  @MainActor
  static func stub_cacheKeyForField_SingleReturn(
    _ stub: ((Selection.Field, GraphQLOperation.Variables?, ResponsePath) -> CacheKeyInfo?)?
  ) {
    _configuration.stub_cacheKeyForField_SingleReturn = stub
    if stub != nil {
      testObserver.start()
    }
  }

  @MainActor
  static func stub_cacheKeyForField_ListReturn(
    _ stub: ((Selection.Field, GraphQLOperation.Variables?, ResponsePath) -> [CacheKeyInfo]?)?
  ) {
    _configuration.stub_cacheKeyForField_ListReturn = stub
    if stub != nil {
      testObserver.start()
    }
  }

  static func objectType(forTypename __typename: String) -> Object? {
    if let stub = objectTypeForTypeName {
      return stub(__typename)
    }

    return Object(typename: __typename, implementedInterfaces: [])
  }
  
  final class SchemaConfiguration: ApolloAPI.SchemaConfiguration, ApolloAPI.FieldPolicyProvider {
    nonisolated(unsafe) static var stub_cacheKeyInfoForType_Object: ((Object, ObjectData) -> CacheKeyInfo?)?
    
    nonisolated(unsafe) static var stub_cacheKeyForField_SingleReturn: ((Selection.Field, GraphQLOperation.Variables?, ResponsePath) -> CacheKeyInfo?)?
    
    nonisolated(unsafe) static var stub_cacheKeyForField_ListReturn: ((Selection.Field, GraphQLOperation.Variables?, ResponsePath) -> [CacheKeyInfo]?)?

    public static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? {
      stub_cacheKeyInfoForType_Object?(type, object)
    }
    
    public static func cacheKey(for field: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> CacheKeyInfo? {
      stub_cacheKeyForField_SingleReturn?(field, variables, path)
    }
    
    public static func cacheKeyList(for listField: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> [CacheKeyInfo]? {
      stub_cacheKeyForField_ListReturn?(listField, variables, path)
    }
  }
}
