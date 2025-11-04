import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

@MainActor
class SelectionSet_EquatableTests: XCTestCase {

  // MARK: Scalar tests

  func test__equatable__scalarString_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("stringValue", String?.self),
        ]
      }

      public var stringValue: String? { __data["stringValue"] }

      convenience init(
        stringValue: String?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "stringValue": stringValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(stringValue: "Han Solo")
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "stringValue": "Han Solo" as String,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).to(equal(dataDictHero))
    expect(initializerHero.hashValue).to(equal(dataDictHero.hashValue))
  }

  func test__equatable__scalarString_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("stringValue", String?.self),
        ]
      }

      public var stringValue: String? { __data["stringValue"] }

      convenience init(
        stringValue: String?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "stringValue": stringValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(stringValue: "Han Solo")
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "stringValue": "Darth Vader" as String,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarString_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("stringValue", String?.self),
        ]
      }

      public var stringValue: String? { __data["stringValue"] }

      convenience init(
        stringValue: String?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "stringValue": stringValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(stringValue: nil)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "stringValue": "Han Solo" as String,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarStringList_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("stringValue", [String?]?.self),
        ]
      }

      public var stringValue: [String?]? { __data["stringValue"] }

      convenience init(
        stringValue: [String?]?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "stringValue": stringValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(stringValue: ["Han Solo"])
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "stringValue": ["Han Solo"] as [String],  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).to(equal(dataDictHero))
    expect(initializerHero.hashValue).to(equal(dataDictHero.hashValue))
  }

  func test__equatable__scalarStringMultidimensionalList_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual()
  throws
  {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("fieldValue", [[[String?]]].self),
        ]
      }

      public var fieldValue: [[[String?]]] { __data["fieldValue"] }

      convenience init(
        fieldValue: [[[String?]]]
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "fieldValue": fieldValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(fieldValue: [[["Han Solo"]]])
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "fieldValue": [[["Han Solo"]]],
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).to(equal(dataDictHero))
    expect(initializerHero.hashValue).to(equal(dataDictHero.hashValue))
  }

  func
  test__equatable__scalarStringMultidimensionalList_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual()
  throws
  {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("fieldValue", [[[String?]]].self),
        ]
      }

      public var fieldValue: [[[String?]]] { __data["fieldValue"] }

      convenience init(
        fieldValue: [[[String?]]]
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "fieldValue": fieldValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(fieldValue: [[["Han Solo"]]])
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "fieldValue": [[["Luke Skywalker"]]],
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    XCTAssertNotEqual(initializerHero, dataDictHero)
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarStringList_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("stringValue", [String?]?.self),
        ]
      }

      public var stringValue: [String?]? { __data["stringValue"] }

      convenience init(
        stringValue: [String?]?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "stringValue": stringValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(stringValue: ["Han Solo"])
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "stringValue": ["Darth Vader"] as [String],  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarStringList_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("stringValue", [String?]?.self),
        ]
      }

      public var stringValue: [String?]? { __data["stringValue"] }

      convenience init(
        stringValue: [String?]?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "stringValue": stringValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(stringValue: nil)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "stringValue": ["Han Solo"] as [String],  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarInt_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("intValue", Int?.self),
        ]
      }

      public var intValue: Int? { __data["intValue"] }

      convenience init(
        intValue: Int?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "intValue": intValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(intValue: 1)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "intValue": 1 as Int,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).to(equal(dataDictHero))
    expect(initializerHero.hashValue).to(equal(dataDictHero.hashValue))
  }

  func test__equatable__scalarInt_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("intValue", Int?.self),
        ]
      }

      public var intValue: Int? { __data["intValue"] }

      convenience init(
        intValue: Int?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "intValue": intValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(intValue: 1)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "intValue": 2 as Int,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarInt_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("intValue", Int?.self),
        ]
      }

      public var intValue: Int? { __data["intValue"] }

      convenience init(
        intValue: Int?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "intValue": intValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(intValue: nil)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "intValue": 2 as Int,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarBool_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("boolValue", Bool?.self),
        ]
      }

      public var boolValue: Bool? { __data["boolValue"] }

      convenience init(
        boolValue: Bool?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "boolValue": boolValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(boolValue: true)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "boolValue": true as Bool,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).to(equal(dataDictHero))
    expect(initializerHero.hashValue).to(equal(dataDictHero.hashValue))
  }

  func test__equatable__scalarBool_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("boolValue", Bool?.self),
        ]
      }

      public var boolValue: Bool? { __data["boolValue"] }

      convenience init(
        boolValue: Bool?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "boolValue": boolValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(boolValue: true)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "boolValue": false as Bool,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarBool_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("boolValue", Bool?.self),
        ]
      }

      public var boolValue: Bool? { __data["boolValue"] }

      convenience init(
        boolValue: Bool?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "boolValue": boolValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(boolValue: nil)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "boolValue": true as Bool,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarFloat_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("floatValue", Float?.self),
        ]
      }

      public var floatValue: Float? { __data["floatValue"] }

      convenience init(
        floatValue: Float?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "floatValue": floatValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(floatValue: 1.1)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "floatValue": 1.1 as Float,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).to(equal(dataDictHero))
    expect(initializerHero.hashValue).to(equal(dataDictHero.hashValue))
  }

  func test__equatable__scalarFloat_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("floatValue", Float?.self),
        ]
      }

      public var floatValue: Float? { __data["floatValue"] }

      convenience init(
        floatValue: Float?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "floatValue": floatValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(floatValue: 1.1)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "floatValue": 2.2 as Float,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarFloat_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("floatValue", Float?.self),
        ]
      }

      public var floatValue: Float? { __data["floatValue"] }

      convenience init(
        floatValue: Float?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "floatValue": floatValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(floatValue: nil)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "floatValue": 2.2 as Float,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarDouble_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("doubleValue", Double?.self),
        ]
      }

      public var doubleValue: Double? { __data["doubleValue"] }

      convenience init(
        doubleValue: Double?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "doubleValue": doubleValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(doubleValue: 1.1)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "doubleValue": 1.1 as Double,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).to(equal(dataDictHero))
    expect(initializerHero.hashValue).to(equal(dataDictHero.hashValue))
  }

  func test__equatable__scalarDouble_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("doubleValue", Double?.self),
        ]
      }

      public var doubleValue: Double? { __data["doubleValue"] }

      convenience init(
        doubleValue: Double?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "doubleValue": doubleValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(doubleValue: 1.1)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "doubleValue": 2.2 as Double,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalarDouble_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("doubleValue", Double?.self),
        ]
      }

      public var doubleValue: Double? { __data["doubleValue"] }

      convenience init(
        doubleValue: Double?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "doubleValue": doubleValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(doubleValue: nil)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "doubleValue": 2.2 as Double,  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__scalar_givenDataDictValueOfDifferentTypeThatCannotCastToFieldType_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("fieldValue", String?.self),
        ]
      }

      public var fieldValue: String? { __data["fieldValue"] }

      convenience init(
        fieldValue: String?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "fieldValue": fieldValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(fieldValue: nil)  // Muse be `nil` to test `as?` equality type cast behavior
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "fieldValue": 2 as Int,
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__customScalar_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    typealias GivenCustomScalar = MockCustomScalar<Int64>

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("fieldValue", GivenCustomScalar?.self),
        ]
      }

      public var fieldValue: GivenCustomScalar? { __data["fieldValue"] }

      convenience init(
        fieldValue: GivenCustomScalar?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "fieldValue": fieldValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(fieldValue: GivenCustomScalar(value: 989_561_700))
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "fieldValue": GivenCustomScalar(value: 989_561_700),  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).to(equal(dataDictHero))
    expect(initializerHero.hashValue).to(equal(dataDictHero.hashValue))
  }

  func test__equatable__customScalar_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    typealias GivenCustomScalar = MockCustomScalar<Int64>

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("fieldValue", GivenCustomScalar?.self),
        ]
      }

      public var fieldValue: GivenCustomScalar? { __data["fieldValue"] }

      convenience init(
        fieldValue: GivenCustomScalar?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "fieldValue": fieldValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(fieldValue: GivenCustomScalar(value: 989_561_700))
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "fieldValue": GivenCustomScalar(value: 123),  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equatable__customScalar_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    typealias GivenCustomScalar = MockCustomScalar<Int64>

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("fieldValue", GivenCustomScalar?.self),
        ]
      }

      public var fieldValue: GivenCustomScalar? { __data["fieldValue"] }

      convenience init(
        fieldValue: GivenCustomScalar?
      ) {
        self.init(
          _dataDict: DataDict(
            data: [
              "__typename": "Hero",
              "fieldValue": fieldValue,
            ],
            fulfilledFragments: [ObjectIdentifier(Self.self)]
          )
        )
      }
    }

    // when
    let initializerHero = Hero(fieldValue: nil)
    let dataDictHero = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "fieldValue": GivenCustomScalar(value: 123),  // non-optional to oppose .field selection type
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  // MARK: Include/Skip (Conditional)
  func test__equatable__includeCondition__differentValue_forFieldFromIncludedTypeCase_returns_false() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata
      override class var __selections: [Selection] {
        [
          .field("name", String?.self),
          .include(if: "a", .inlineFragment(IfA.self)),
        ]
      }

      final class IfA: ConcreteMockTypeCase<HeroFragment>, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata
        override class var __selections: [Selection] {
          [
            .field("age", Int.self)
          ]
        }
      }
    }
    // when
    let selectionSet1 = HeroFragment(
      _dataDict: DataDict(
        data: [
          "name": "Name 1",
          "age": 25,
        ],
        fulfilledFragments: [
          ObjectIdentifier(HeroFragment.self),
          ObjectIdentifier(HeroFragment.IfA.self),
        ]
      )
    )
    let selectionSet2 = HeroFragment(
      _dataDict: DataDict(
        data: [
          "name": "Name 1",
          "age": 26,
        ],
        fulfilledFragments: [
          ObjectIdentifier(HeroFragment.self),
          ObjectIdentifier(HeroFragment.IfA.self),
        ]
      )
    )
    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }
  func test__equatable__includeCondition__differentValue_forFieldFromExcludedTypeCase_returns_true() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata
      override class var __selections: [Selection] {
        [
          .field("name", String?.self),
          .include(if: "a", .inlineFragment(IfA.self)),
        ]
      }

      final class IfA: ConcreteMockTypeCase<HeroFragment>, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __selections: [Selection] {
          [
            .field("age", Int.self)
          ]
        }

      }
    }
    // when
    let selectionSet1 = HeroFragment(
      _dataDict: DataDict(
        data: [
          "name": "Name 1",
          "age": 25,
        ],
        fulfilledFragments: [
          ObjectIdentifier(HeroFragment.self)
        ]
      )
    )
    let selectionSet2 = HeroFragment(
      _dataDict: DataDict(
        data: [
          "name": "Name 1",
          "age": 26,
        ],
        fulfilledFragments: [
          ObjectIdentifier(HeroFragment.self)
        ]
      )
    )
    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }
  func test__equatable__includeCondition__includedInOneButNotOther_returns_false() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata
      override class var __selections: [Selection] {
        [
          .field("name", String?.self),
          .include(if: "a", .inlineFragment(IfA.self)),
        ]
      }

      final class IfA: ConcreteMockTypeCase<HeroFragment>, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata
        override class var __selections: [Selection] {
          [
            .field("age", Int.self)
          ]
        }
      }
    }
    // when
    let selectionSet1 = HeroFragment(
      _dataDict: DataDict(
        data: [
          "name": "Name 1",
          "age": 25,
        ],
        fulfilledFragments: [
          ObjectIdentifier(HeroFragment.self),
          ObjectIdentifier(HeroFragment.IfA.self),
        ]
      )
    )
    let selectionSet2 = HeroFragment(
      _dataDict: DataDict(
        data: [
          "name": "Name 1"
        ],
        fulfilledFragments: [
          ObjectIdentifier(HeroFragment.self)
        ]
      )
    )
    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  func test__equatable__includeCondition__singleField_sameValues_returns_true() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("name", String?.self),
          .include(if: "includeAge", .field("age", Int?.self)),
        ]
      }
    }

    // when
    let selectionSet1 = HeroFragment(
      _dataDict: DataDict(
        data: [
          "name": "Name 1",
          "age": 25,
        ],
        fulfilledFragments: [
          ObjectIdentifier(HeroFragment.self)
        ]
      )
    )

    let selectionSet2 = HeroFragment(
      _dataDict: DataDict(
        data: [
          "name": "Name 1",
          "age": 25,
        ],
        fulfilledFragments: [
          ObjectIdentifier(HeroFragment.self)
        ]
      )
    )

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__includeCondition__singleField_differentValues_returns_false() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("name", String?.self),
          .include(if: "includeAge", .field("age", Int?.self)),
        ]
      }
    }

    // when
    let selectionSet1 = HeroFragment(
      _dataDict: DataDict(
        data: [
          "name": "Name 1",
          "age": 25,
        ],
        fulfilledFragments: [
          ObjectIdentifier(HeroFragment.self)
        ]
      )
    )

    let selectionSet2 = HeroFragment(
      _dataDict: DataDict(
        data: [
          "name": "Name 1",
          "age": 30,
        ],
        fulfilledFragments: [
          ObjectIdentifier(HeroFragment.self)
        ]
      )
    )

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  // MARK: Fragment Merging

  // Unit test to reproduce https://github.com/apollographql/apollo-ios/issues/3602
  func test__equatable__childObject_inBothSelfAndNamedFragment_withNestedInlineFragment_differentValues_returns_false() {
    // given
    final class Hero: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Object(typename: "Hero", implementedInterfaces: []) }
      override class var __selections: [Selection] {[
        .field("friends", [Friend].self),
        .fragment(HeroFriendFragment.self)
      ]}

      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [Hero.self, HeroFriendFragment.self]
      }

      class Friend: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .inlineFragment(AsCharacter.self)
        ]}

        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [Friend.self, HeroFriendFragment.Friend.self]
        }

        final class AsCharacter: ConcreteMockTypeCase<Friend>, @unchecked Sendable {
          typealias Schema = MockSchemaMetadata

          override class var __parentType: any ParentType { Object(typename: "Character", implementedInterfaces: []) }
          override class var __selections: [Selection] {[
            .field("age", Int?.self),
          ]}
          override class var __fulfilledFragments: [any SelectionSet.Type] {
            [Friend.self, Friend.AsCharacter.self, HeroFriendFragment.Friend.self]
          }
        }
      }
    }

    final class HeroFriendFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Object(typename: "Hero", implementedInterfaces: []) }
      override class var __selections: [Selection] {[
        .field("friends", [Friend].self)
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFriendFragment.self]
      }

      class Friend: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("name", String?.self),
        ]}

        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [Friend.self]
        }
      }
    }

    // when
    let selectionSet1 = Hero.Friend.AsCharacter.init(_dataDict: DataDict(
      data: [
        "name": "Name 1"
      ],
      fulfilledFragments: [
        ObjectIdentifier(Hero.Friend.self),
        ObjectIdentifier(Hero.Friend.AsCharacter.self),
        ObjectIdentifier(HeroFriendFragment.Friend.self)
      ]
    ))

    let selectionSet2 = Hero.Friend.AsCharacter.init(_dataDict: DataDict(
      data: [
        "name": "Name 2"
      ],
      fulfilledFragments: [
        ObjectIdentifier(Hero.Friend.self),
        ObjectIdentifier(Hero.Friend.AsCharacter.self),
        ObjectIdentifier(HeroFriendFragment.Friend.self)
      ]
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  // MARK: - Null/nil tests

  func test__equatable__optionalChildObject__isNullOnBoth_returns_true() {
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("name", String?.self),
        ]
      }
    }

    // when
    let selectionSet1 = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "name": NSNull(),
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    let selectionSet2 = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "name": NSNull(),
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__optionalChildObject__isNullAndNil_returns_true() {
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("name", String?.self),
        ]
      }
    }

    // when
    let selectionSet1 = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "name": NSNull(),
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    let selectionSet2 = Hero(
      _dataDict: DataDict(
        data: [
          "__typename": "Hero",
          "name": nil,
        ],
        fulfilledFragments: [ObjectIdentifier(Hero.self)]
      )
    )

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  // MARK: - Integration Tests

  func test__equatable__givenQueryResponseFetchedFromStore() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
            .field("friend", Friend.self),
          ]
        }
        var friend: Friend { __data["friend"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("name", String.self),
            ]
          }
          var name: String { __data["name"] }
        }
      }
    }

    let store = ApolloStore(cache: InMemoryNormalizedCache())
    store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "__typename": "Droid",
        "name": "R2-D2",
        "friend": CacheReference("1000"),
      ],
      "1000": ["__typename": "Human", "name": "Luke Skywalker"],
    ])

    let expected = try GivenSelectionSet(data: [
      "hero": [
        "__typename": "Droid",
        "name": "R2-D2",
        "friend": ["__typename": "Human", "name": "Luke Skywalker"],
      ]
    ])

    // when
    let updateCompletedExpectation = expectation(description: "Update completed")

    store.load(MockQuery<GivenSelectionSet>()) { result in
      defer { updateCompletedExpectation.fulfill() }

      XCTAssertSuccessResult(result)
      let responseData = try! result.get().data

      expect(responseData).to(equal(expected))
    }

    await fulfillment(of: [updateCompletedExpectation], timeout: 1.0)
  }

  func test__equatable__givenNestedObjects_sameValue_shouldBeEqual() throws {
    // given
    class ReverseFriendsQuery: MockSelectionSet {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero?.self, arguments: ["id": .variable("id")])
        ]
      }

      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("friendsConnection", FriendsConnection.self),
          ]
        }

        var friendsConnection: FriendsConnection { __data["friendsConnection"] }

        class FriendsConnection: MockSelectionSet {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("friends", [Character].self),
            ]
          }

          var friends: [Character] { __data["friends"] }

          class Character: MockSelectionSet {
            override class var __selections: [Selection] {
              [
                .field("__typename", String.self),
                .field("name", String.self),
                .field("id", String.self),
              ]
            }

            var name: String { __data["name"] }
            var id: String { __data["id"] }
          }
        }
      }
    }

    // when
    let query = MockQuery<ReverseFriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "before": "Y3Vyc29yMw=="]

    let body: JSONObject = [
      "data": [
        "hero": [
          "__typename": "Droid",
          "friendsConnection": [
            "__typename": "FriendsConnection",
            "friends": [
              [
                "__typename": "Human",
                "name": "Han Solo",
                "id": "1002",
              ],
              [
                "__typename": "Human",
                "name": "Leia Organa",
                "id": "1003",
              ],
            ],
          ],
        ]
      ]
    ]

    let first = try GraphQLResponse(
      operation: query,
      body: body
    ).parseResult().0.data

    let second = try GraphQLResponse(
      operation: query,
      body: body
    ).parseResult().0.data

    // then
    XCTAssertEqual(first, second)
    expect(first).to(equal(second))
  }

}
