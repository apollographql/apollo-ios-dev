@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

@MainActor
class SelectionSet_EqualityTests: XCTestCase {

  func test__equality__scalarString_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("stringValue", String?.self)
      ]}

      public var stringValue: String? { __data["stringValue"] }

      convenience init(
        stringValue: String?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "stringValue": stringValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(stringValue: "Han Solo")
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "stringValue": "Han Solo" as String // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).to(equal(dataDictHero))
  }

  func test__equality__scalarString_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("stringValue", String?.self)
      ]}

      public var stringValue: String? { __data["stringValue"] }

      convenience init(
        stringValue: String?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "stringValue": stringValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(stringValue: "Han Solo")
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "stringValue": "Darth Vader" as String // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalarString_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("stringValue", String?.self)
      ]}

      public var stringValue: String? { __data["stringValue"] }

      convenience init(
        stringValue: String?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "fieldValue": stringValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(stringValue: nil)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "stringValue": "Han Solo" as String // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalarStringList_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("stringValue", [String?]?.self)
      ]}

      public var stringValue: [String?]? { __data["stringValue"] }

      convenience init(
        stringValue: [String?]?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "stringValue": stringValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(stringValue: ["Han Solo"])
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "stringValue": ["Han Solo"] as [String] // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).to(equal(dataDictHero))
  }

  func test__equality__scalarStringList_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("stringValue", [String?]?.self)
      ]}

      public var stringValue: [String?]? { __data["stringValue"] }

      convenience init(
        stringValue: [String?]?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "stringValue": stringValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(stringValue: ["Han Solo"])
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "stringValue": ["Darth Vader"] as [String] // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalarStringList_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("stringValue", [String?]?.self)
      ]}

      public var stringValue: [String?]? { __data["stringValue"] }

      convenience init(
        stringValue: [String?]?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "fieldValue": stringValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(stringValue: nil)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "stringValue": ["Han Solo"] as [String] // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalarInt_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("intValue", Int?.self)
      ]}

      public var intValue: Int? { __data["intValue"] }

      convenience init(
        intValue: Int?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "intValue": intValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(intValue: 1)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "intValue": 1 as Int // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).to(equal(dataDictHero))
  }

  func test__equality__scalarInt_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("intValue", Int?.self)
      ]}

      public var intValue: Int? { __data["intValue"] }

      convenience init(
        intValue: Int?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "intValue": intValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(intValue: 1)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "intValue": 2 as Int // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalarInt_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("intValue", Int?.self)
      ]}

      public var intValue: Int? { __data["intValue"] }

      convenience init(
        intValue: Int?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "intValue": intValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(intValue: nil)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "intValue": 2 as Int // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalarBool_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("boolValue", Bool?.self)
      ]}

      public var boolValue: Bool? { __data["boolValue"] }

      convenience init(
        boolValue: Bool?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "boolValue": boolValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(boolValue: true)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "boolValue": true as Bool // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).to(equal(dataDictHero))
  }

  func test__equality__scalarBool_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("boolValue", Bool?.self)
      ]}

      public var boolValue: Bool? { __data["boolValue"] }

      convenience init(
        boolValue: Bool?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "intValue": boolValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(boolValue: true)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "boolValue": false as Bool // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalarBool_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("boolValue", Bool?.self)
      ]}

      public var boolValue: Bool? { __data["boolValue"] }

      convenience init(
        boolValue: Bool?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "boolValue": boolValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(boolValue: nil)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "boolValue": true as Bool // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalarFloat_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("floatValue", Float?.self)
      ]}

      public var floatValue: Float? { __data["floatValue"] }

      convenience init(
        floatValue: Float?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "floatValue": floatValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(floatValue: 1.1)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "floatValue": 1.1 as Float // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).to(equal(dataDictHero))
  }

  func test__equality__scalarFloat_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("floatValue", Float?.self)
      ]}

      public var floatValue: Float? { __data["floatValue"] }

      convenience init(
        floatValue: Float?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "floatValue": floatValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(floatValue: 1.1)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "floatValue": 2.2 as Float // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalarFloat_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("floatValue", Float?.self)
      ]}

      public var floatValue: Float? { __data["floatValue"] }

      convenience init(
        floatValue: Float?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "floatValue": floatValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(floatValue: nil)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "floatValue": 2.2 as Float // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalarDouble_givenOptionalityOpposedDataDictValue_sameValue_shouldBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("doubleValue", Double?.self)
      ]}

      public var doubleValue: Double? { __data["doubleValue"] }

      convenience init(
        doubleValue: Double?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "doubleValue": doubleValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(doubleValue: 1.1)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "doubleValue": 1.1 as Double // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).to(equal(dataDictHero))
  }

  func test__equality__scalarDouble_givenOptionalityOpposedDataDictValue_differentValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("doubleValue", Double?.self)
      ]}

      public var doubleValue: Double? { __data["doubleValue"] }

      convenience init(
        doubleValue: Double?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "doubleValue": doubleValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(doubleValue: 1.1)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "doubleValue": 2.2 as Double // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalarDouble_givenOptionalityOpposedDataDictValue_nilValue_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("doubleValue", Double?.self)
      ]}

      public var doubleValue: Double? { __data["doubleValue"] }

      convenience init(
        doubleValue: Double?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "doubleValue": doubleValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(doubleValue: nil)
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "doubleValue": 2.2 as Double // non-optional to oppose .field selection type
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

  func test__equality__scalar_givenDataDictValueOfDifferentTypeThatCannotCastToFieldType_shouldNotBeEqual() throws {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("fieldValue", String?.self)
      ]}

      public var fieldValue: String? { __data["fieldValue"] }

      convenience init(
        fieldValue: String?
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": "Hero",
          "fieldValue": fieldValue
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let initializerHero = Hero(fieldValue: nil) // Muse be `nil` to test `as?` equality type cast behavior
    let dataDictHero = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Hero",
        "stringValue": 2 as Int
      ],
      fulfilledFragments: [ObjectIdentifier(Hero.self)]
    ))

    // then
    expect(initializerHero).notTo(equal(dataDictHero))
  }

}
