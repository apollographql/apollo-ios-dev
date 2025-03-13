import XCTest
@testable import Apollo
@testable import ApolloAPI
import ApolloInternalTestHelpers
import Nimble

class SelectionSetTests: XCTestCase {

  // MARK: - Equatable/Hashable Tests

  func test__equatable__selectionSetWithSameDataAndDifferentFulfilledFragments_returns_true() {
    // given
    let data: JSONObject = [
      "__typename": "Human",
      "name": "Johnny Tsunami"
    ]

    // when
    let selectionSet1 = MockSelectionSet(_dataDict: DataDict(
      data: data,
      fulfilledFragments: [ObjectIdentifier(MockSelectionSet.self)]
    ))

    let selectionSet2 = MockSelectionSet(_dataDict: DataDict(
      data: data,
      fulfilledFragments: []
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  // MARK: - Field Accessor Tests

  func test__selection_givenOptionalField_givenValue__returnsValue() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("name", String?.self)
      ]}

      var name: String? { __data["name"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "name": "Johnny Tsunami"
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.name).to(equal("Johnny Tsunami"))
  }

  func test__selection_givenOptionalField_missingValue__returnsNil() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("name", String?.self)
      ]}

      var name: String? { __data["name"] }
    }

    let object: JSONObject = [
      "__typename": "Human"
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.name).to(beNil())
  }

  func test__selection_givenOptionalField_givenNilValue__returnsNil() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("name", String?.self)
      ]}

      var name: String? { __data["name"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "name": String?.none
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.name).to(beNil())
  }

  // MARK: Scalar - Nested Array Tests

  func test__selection__nestedArrayOfScalar_nonNull_givenValue__returnsValue() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("nestedList", [[String]].self)
      ]}

      var nestedList: [[String]] { __data["nestedList"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "nestedList": [["A"]]
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.nestedList).to(equal([["A"]]))
  }

  // MARK: Entity

  func test__selection_givenRequiredEntityField_givenValue__returnsValue() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friend", Friend.self)
      ]}

      var friend: Friend { __data["friend"] }

      class Friend: MockSelectionSet {
        typealias Schema = MockSchemaMetadata

        override class var __selections: [Selection] {[
          .field("__typename", String.self),
        ]}
      }
    }

    let friendData: JSONObject = ["__typename": "Human"]

    let object: JSONObject = [
      "__typename": "Human",
      "friend": friendData
    ]

    let expected = try! Hero.Friend(data: friendData)

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friend).to(equal(expected))
  }

  func test__selection_givenOptionalEntityField_givenValue__returnsValue() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friend", Hero?.self)
      ]}

      var friend: Hero? { __data["friend"] }
    }

    let friendData: JSONObject = ["__typename": "Human"]

    let object: JSONObject = [
      "__typename": "Human",
      "friend": friendData
    ]

    let expected = try! Hero(data: friendData, variables: nil)

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friend).to(equal(expected))
  }

  func test__selection_givenOptionalEntityField_givenNilValue__returnsNil() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friend", Hero?.self)
      ]}

      var friend: Hero? { __data["friend"] }
    }

    let object: JSONObject = [
      "__typename": "Human"
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friend).to(beNil())
  }

  func test__selection_givenOptionalEntityField_givenNullValue__returnsNil() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friend", Hero?.self)
      ]}

      var friend: Hero? { __data["friend"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "friend": DataDict._NullValue
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friend).to(beNil())
  }

  // MARK: Entity - Array Tests

  func test__selection__arrayOfEntity_nonNull_givenValue__returnsValue() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friends", [Hero].self)
      ]}

      var friends: [Hero] { __data["friends"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "friends": [
        [
          "__typename": "Human",
          "friends": []
        ]
      ]
    ]

    let expected = try! Hero(
      data: [
        "__typename": "Human",
        "friends": []
      ],
      variables: nil
    )

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friends).to(equal([expected]))
  }

  func test__selection__arrayOfEntity_nullableEntity_givenValue__returnsValue() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friends", [Hero?].self)
      ]}

      var friends: [Hero?] { __data["friends"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "friends": [
        [
          "__typename": "Human",
          "friends": []
        ]
      ]
    ]

    let expected = try! Hero(
      data: [
        "__typename": "Human",
        "friends": []
      ],
      variables: nil
    )

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friends).to(equal([expected]))
  }

  func test__selection__arrayOfEntity_nullableEntity_givenNilValueInList__returnsArrayWithNil() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friends", [Hero?].self)
      ]}

      var friends: [Hero?] { __data["friends"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "friends": [
        Hero?.none,
        ["__typename": "Human", "friends": []],
        Hero?.none
      ]
    ]

    let expected = try! Hero(
      data: [
        "__typename": "Human",
        "friends": []
      ],
      variables: nil
    )

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friends).to(equal([Hero?.none, expected, Hero?.none]))
  }

  func test__selection__arrayOfEntity_nullableList_givenValue__returnsValue() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friends", [Hero]?.self)
      ]}

      var friends: [Hero]? { __data["friends"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "friends": [
        [
          "__typename": "Human",
          "friends": []
        ]
      ]
    ]

    let expected = try! Hero(
      data: [
        "__typename": "Human",
        "friends": []
      ],
      variables: nil
    )

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friends).to(equal([expected]))
  }

  func test__selection__arrayOfEntity_nullableList_givenNoListValue__returnsNil() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friends", [Hero]?.self)
      ]}

      var friends: [Hero]? { __data["friends"] }
    }

    let object: JSONObject = [
      "__typename": "Human"
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friends).to(beNil())
  }

  // MARK: Entity - Nested Array Tests

  func test__selection__nestedArrayOfEntity_nonNull_givenValue__returnsValue() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("nestedList", [[Hero]].self)
      ]}

      var nestedList: [[Hero]] { __data["nestedList"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "nestedList": [[
        [
          "__typename": "Human",
          "nestedList": [[]]
        ]
      ]]
    ]

    let expected = try! Hero(
      data: [
        "__typename": "Human",
        "nestedList": [[]]
      ],
      variables: nil
    )

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.nestedList).to(equal([[expected]]))
  }

  func test__selection__nestedArrayOfEntity_nullableInnerList_givenValue__returnsValue() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("nestedList", [[Hero]?].self)
      ]}

      var nestedList: [[Hero]?] { __data["nestedList"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "nestedList": [[
        [
          "__typename": "Human",
          "nestedList": [[]]
        ]
      ]]
    ]

    let expected = try! Hero(
      data: [
        "__typename": "Human",
        "nestedList": [[]]
      ],
      variables: nil
    )

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.nestedList).to(equal([[expected]]))
  }

  func test__selection__nestedArrayOfEntity_nullableInnerList_givenNilValues__returnsListWithNils() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("nestedList", [[Hero]?].self)
      ]}

      var nestedList: [[Hero]?] { __data["nestedList"] }
    }

    let nestedObjectData: JSONObject = [
      "__typename": "Human",
      "nestedList": [[]]
    ]

    let object: JSONObject = [
      "__typename": "Human",
      "nestedList": [
        [Hero]?.none,
        [nestedObjectData],
        [Hero]?.none,
      ]
    ]

    let expectedItem = try! Hero(data: nestedObjectData, variables: nil)

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.nestedList).to(equal([[Hero]?.none, [expectedItem], [Hero]?.none]))
  }

  func test__selection__nestedArrayOfEntity_nullableEntity_givenValue__returnsValue() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("nestedList", [[Hero?]].self)
      ]}

      var nestedList: [[Hero?]] { __data["nestedList"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "nestedList": [[
        [
          "__typename": "Human",
          "nestedList": [[]]
        ]
      ]]
    ]
    
    let expected = try! Hero(
      data: [
        "__typename": "Human",
        "nestedList": [[]]
      ],
      variables: nil
    )

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.nestedList).to(equal([[expected]]))
  }

  func test__selection__nestedArrayOfEntity_nullableOuterList_givenValue__returnsValue() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("nestedList", [[Hero]]?.self)
      ]}

      var nestedList: [[Hero]]? { __data["nestedList"] }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "nestedList": [[
        [
          "__typename": "Human",
          "nestedList": [[]]
        ]
      ]]
    ]

    let expected = try! Hero(
      data: [
        "__typename": "Human",
        "nestedList": [[]]
      ],
      variables: nil
    )

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.nestedList).to(equal([[expected]]))
  }

  // MARK: - TypeCase Conversion Tests

  @MainActor
  func test__asInlineFragment_givenObjectType_returnsTypeIfCorrectType() {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
      static let Droid = Object(typename: "Droid", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      case "Droid": return Types.Droid
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .inlineFragment(AsHuman.self),
        .inlineFragment(AsDroid.self),
      ]}

      var asHuman: AsHuman? { _asInlineFragment() }
      var asDroid: AsDroid? { _asInlineFragment() }

      class AsHuman: MockTypeCase {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Human }
        override class var __selections: [Selection] {[
          .field("name", String?.self)
        ]}
      }

      class AsDroid: MockTypeCase {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Droid }
        override class var __selections: [Selection] {[
          .field("primaryFunction", String?.self)
        ]}
      }
    }

    let object: JSONObject = [
      "__typename": "Droid",
      "name": "R2-D2"
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.asHuman).to(beNil())
    expect(actual.asDroid).toNot(beNil())
  }

  @MainActor
  func test__asInlineFragment_givenInterfaceType_typeForTypeNameImplementsInterface_returnsType() {
    // given
    struct Types {
      static let Humanoid = Interface(name: "Humanoid", implementingObjects: ["Human"])
      static let Human = Object(typename: "Human", implementedInterfaces: [Humanoid])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .inlineFragment(AsHumanoid.self),
      ]}

      var asHumanoid: AsHumanoid? { _asInlineFragment() }

      class AsHumanoid: MockTypeCase {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Humanoid }
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
      }

    }

    let object: JSONObject = [
      "__typename": "Human",
      "name": "Han Solo"
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.asHumanoid).toNot(beNil())
  }

  @MainActor
  func test__asInlineFragment_givenInterfaceType_typeForTypeNameDoesNotImplementInterface_returnsNil() {
    // given
    struct Types {
      static let Humanoid = Interface(name: "Humanoid", implementingObjects: [])
      static let Droid = Object(typename: "Droid", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Droid": return Types.Droid
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .inlineFragment(AsHumanoid.self),
      ]}

      var asHumanoid: AsHumanoid? { _asInlineFragment() }

      class AsHumanoid: MockTypeCase {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Humanoid }
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
      }

    }

    let object: JSONObject = [
      "__typename": "Droid",
      "name": "R2-D2"
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.asHumanoid).to(beNil())
  }

  @MainActor
  func test__asInlineFragment_givenUnionType_typeNameIsTypeInUnionPossibleTypes_returnsType() {
    // given
    enum Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
      static let Character = Union(name: "Character", possibleTypes: [Types.Human])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .inlineFragment(AsCharacter.self),
      ]}

      var asCharacter: AsCharacter? { _asInlineFragment() }

      class AsCharacter: MockTypeCase {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Character }
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
      }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "name": "Han Solo"
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.asCharacter).toNot(beNil())
  }

  @MainActor
  func test__asInlineFragment_givenUnionType_typeNameNotIsTypeInUnionPossibleTypes_returnsNil() {
    // given
    enum Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
      static let Character = Union(name: "Character", possibleTypes: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .inlineFragment(AsCharacter.self),
      ]}

      var asCharacter: AsCharacter? { _asInlineFragment() }

      class AsCharacter: MockTypeCase {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Character }
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
      }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "name": "Han Solo"
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.asCharacter).to(beNil())
  }

  @MainActor
  func test__asInlineFragment_givenInterfaceTypeOnOperationRoot_typeImplementsInterface_returnsType() {
    // given
    struct Types {
      static let AdminQuery = Interface(name: "AdminQuery", implementingObjects: ["Query"])
      static let Query = Object(typename: "Query", implementedInterfaces: [AdminQuery])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Query": return Types.Query
      default: XCTFail(); return nil
      }
    })

    class RootData: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Query }
      override class var __selections: [Selection] {[
        .inlineFragment(AsAdminQuery.self),
      ]}

      var asAdminQuery: AsAdminQuery? { _asInlineFragment() }

      class AsAdminQuery: MockTypeCase {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.AdminQuery }
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
      }

    }

    let object: JSONObject = [
      // JSON does not include typename for the operation root
      "name": "Admin"
    ]

    // when
    let actual = try! RootData(data: object)

    // then
    expect(actual.asAdminQuery).toNot(beNil())
  }


  // MARK: - To Fragment Conversion Tests

  func test__toFragment_givenInclusionCondition_true_returnsFragment() {
    // given
    class GivenFragment: MockFragment { }

    class Hero: AbstractMockSelectionSet<Hero.Fragments, MockSchemaMetadata> {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .include(if: "includeFragment", .fragment(GivenFragment.self))
      ]}

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var givenFragment: GivenFragment? { _toFragment() }
      }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "name": "Han Solo"
    ]

    // when
    let actual = try! Hero(data: object, variables: ["includeFragment": true])

    // then
    expect(actual.fragments.givenFragment).toNot(beNil())
  }

  func test__toFragment_givenInclusionCondition_false_returnsNil() {
    // given
    class GivenFragment: MockFragment { }

    class Hero: AbstractMockSelectionSet<Hero.Fragments, MockSchemaMetadata> {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .include(if: "includeFragment", .fragment(GivenFragment.self))
      ]}

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var givenFragment: GivenFragment? { _toFragment() }
      }
    }

    let object: JSONObject = [
      "__typename": "Human",
      "name": "Han Solo"
    ]

    // when
    let actual = try! Hero(data: object, variables: ["includeFragment": false])

    // then
    expect(actual.fragments.givenFragment).to(beNil())
  }

  // MARK: - Initializer Tests

  @MainActor
  func test__selectionInitializer_givenInitTypeWithTypeCondition__canConvertToConditionalType() {
    // given
    struct Types {
      static let Animal = Interface(name: "Animal", implementingObjects: ["Human"])
      static let Human = Object(typename: "Human", implementedInterfaces: [Animal])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .inlineFragment(AsAnimal.self)
      ]}

      var asAnimal: AsAnimal? { _asInlineFragment() }

      class AsAnimal: ConcreteMockTypeCase<Hero> {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Animal }
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
        var name: String { __data["name"] }

        convenience init(
          __typename: String,
          name: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "name": name,
            ], fulfilledFragments: [
              ObjectIdentifier(Self.self),
              ObjectIdentifier(Hero.self),
            ]))
        }
      }

    }

    // when
    let actual = Hero.AsAnimal(__typename: "Droid", name: "Artoo").asRootEntityType

    // then
    expect(actual.asAnimal?.name).to(equal("Artoo"))
  }

  @MainActor
  func test__selectionInitializer_givenInitNestedTypeWithTypeCondition__canConvertToConditionalType() {
    // given
    struct Types {
      static let Query = Object(typename: "Query", implementedInterfaces: [])
      static let Animal = Interface(name: "Animal", implementingObjects: ["Human"])
      static let Human = Object(typename: "Human", implementedInterfaces: [Animal])
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
          .inlineFragment(AsAnimal.self)
        ]}

        var asAnimal: AsAnimal? { _asInlineFragment() }

        class AsAnimal: ConcreteMockTypeCase<Hero> {
          typealias Schema = MockSchemaMetadata

          override class var __parentType: any ParentType { Types.Animal }
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
              "name": name,
            ], fulfilledFragments: [
              ObjectIdentifier(Self.self),
              ObjectIdentifier(Hero.self),
            ]))
          }
        }
      }
    }

    // when
    let actual = Data(
      hero: Data.Hero.AsAnimal(__typename: "Droid", name: "Artoo").asRootEntityType
    )

    // then
    expect(actual.hero.asAnimal?.name).to(equal("Artoo"))
  }

  @MainActor
  func test__selectionInitializer_givenInitTypeWithInclusionCondition__canConvertToConditionalType() {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .include(if: "a", .inlineFragment(IfA.self))
      ]}

      var ifA: IfA? { _asInlineFragment() }

      class IfA: ConcreteMockTypeCase<Hero> {
        typealias Schema = MockSchemaMetadata

        typealias RootEntityType = Hero
        override class var __parentType: any ParentType { Types.Human }
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
        var name: String { __data["name"] }

        convenience init(
          name: String
        ) {
          self.init(_dataDict: DataDict(data: [
            "__typename": Types.Human.typename,
            "name": name
          ], fulfilledFragments: [
            ObjectIdentifier(Self.self),
            ObjectIdentifier(Hero.self),
          ]))
        }
      }

    }

    // when
    let actual = Hero.IfA(name: "Han Solo").asRootEntityType

    // then
    expect(actual.ifA?.name).to(equal("Han Solo"))
  }

  @MainActor
  func test__selectionInitializer_givenInitTypeWithInclusionCondition__cannotConvertToOtherConditionalType() {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .include(if: "a", .inlineFragment(IfA.self)),
        .include(if: "b", .inlineFragment(IfB.self))
      ]}

      var ifA: IfA? { _asInlineFragment() }
      var ifB: IfB? { _asInlineFragment() }

      class IfA: ConcreteMockTypeCase<Hero> {
        typealias Schema = MockSchemaMetadata
        override class var __parentType: any ParentType { Types.Human }
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
        var name: String { __data["name"] }

        convenience init(
          name: String
        ) {
          self.init(_dataDict: DataDict(data: [
            "__typename": Types.Human.typename,
            "name": name,
          ], fulfilledFragments: [
            ObjectIdentifier(Self.self),
            ObjectIdentifier(Hero.self),
          ]))
        }
      }
      class IfB: ConcreteMockTypeCase<Hero> {
        typealias Schema = MockSchemaMetadata
        override class var __parentType: any ParentType { Types.Human }
        override class var __selections: [Selection] {[
        ]}
      }
    }

    // when
    let actual = Hero.IfA(name: "Han Solo").asRootEntityType

    // then
    expect(actual.ifA).toNot(beNil())
    expect(actual.ifB).to(beNil())
  }

  @MainActor
  func test__selectionInitializer_givenInitNestedTypeWithInclusionCondition__cannotConvertToOtherConditionalType() {
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
            .field("friend", Friend.self)
          ]}
          var name: String { __data["name"] }
          var friend: Friend { __data["friend"] }

          convenience init(
            name: String,
            friend: Friend? = nil
          ) {
            self.init(_dataDict: DataDict(data: [
              "__typename": Types.Human.typename,
              "name": name,
              "friend": friend._fieldData,
            ], fulfilledFragments: [
              ObjectIdentifier(Self.self),
              ObjectIdentifier(Hero.self),
            ]))
          }

          class Friend: MockSelectionSet {
            typealias Schema = MockSchemaMetadata

            override class var __parentType: any ParentType { Types.Human }
            override class var __selections: [Selection] {[
              .include(if: !"c", .inlineFragment(IfNotC.self))
            ]}

            var ifNotC: IfNotC? { _asInlineFragment() }

            class IfNotC: ConcreteMockTypeCase<Friend> {
              typealias Schema = MockSchemaMetadata
              override class var __parentType: any ParentType { Types.Human }
              override class var __selections: [Selection] {[
                .field("name", String.self)
              ]}
              var name: String { __data["name"] }

              convenience init(
                name: String
              ) {
                self.init(_dataDict: DataDict(data: [
                  "__typename": Types.Human.typename,
                  "name": name,
                ], fulfilledFragments: [
                  ObjectIdentifier(Self.self),
                  ObjectIdentifier(Friend.self),
                ]))
              }
            }
          }
        }

        class IfB: ConcreteMockTypeCase<Hero> {
          typealias Schema = MockSchemaMetadata
          override class var __parentType: any ParentType { Types.Human }
          override class var __selections: [Selection] {[]}

          convenience init() {
            self.init(_dataDict: DataDict(data: [
              "__typename": Types.Human.typename,
            ], fulfilledFragments: [
              ObjectIdentifier(Self.self),
              ObjectIdentifier(Hero.self),
            ]))
          }
        }
      }
    }

    // when
    let actual = Data(
      hero: .IfA(
        name: "Han Solo",
        friend: Data.Hero.IfA.Friend.IfNotC(name: "Leia Organa").asRootEntityType
      ).asRootEntityType
    )

    // then
    expect(actual.hero.ifA).toNot(beNil())
    expect(actual.hero.ifA?.friend.ifNotC).toNot(beNil())
    expect(actual.hero.ifB).to(beNil())
  }

  @MainActor
  func test__selectionInitializer_givenInitMultipleTypesWithConflictingInclusionConditions__canConvertToAllConditionalTypes() {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .include(if: "a", .inlineFragment(IfA.self))
      ]}

      var ifA: IfA? { _asInlineFragment() }

      class IfA: ConcreteMockTypeCase<Hero> {
        typealias Schema = MockSchemaMetadata
        override class var __parentType: any ParentType { Types.Human }
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
        var name: String { __data["name"] }

        convenience init(
          name: String
        ) {
          self.init(_dataDict: DataDict(data: [
            "__typename": Types.Human.typename,
            "name": name,
          ], fulfilledFragments: [
            ObjectIdentifier(Self.self),
            ObjectIdentifier(Hero.self),
          ]))
        }
      }

    }

    // when
    let actual = Hero.IfA(name: "Han Solo").asRootEntityType

    // then
    expect(actual.ifA?.name).to(equal("Han Solo"))
  }

  // MARK: Initializer - Optional Field Tests

  @MainActor
  func test__selectionInitializer_givenOptionalScalarField__fieldIsPresentWithOptionalNilValue() {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .field("name", String?.self)
      ]}

      var name: String? { __data["name"] }

      convenience init(
        name: String? = nil
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": Types.Human.typename,
          "name": name,
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }
    }

    // when
    let actual = Hero(name: nil)

    // then
    expect(actual.name).to(beNil())
    expect(actual.__data._data.keys.contains("name")).to(beTrue())

    guard let nameValue = actual.__data._data["name"] else {
      fail("name should be Optional.some(Optional.none)")
      return
    }
    expect(nameValue).to(beNil())
    
    if DataDict._AnyHashableCanBeCoerced {
      guard let nameValue = nameValue as? String? else {
        fail("name should be Optional.some(Optional.none).")
        return
      }
      expect(nameValue).to(beNil())
    } else {
      guard let nameValue = nameValue.base as? String? else {
        fail("name should be Optional.some(Optional.none).")
        return
      }
      expect(nameValue).to(beNil())
    }
  }

  @MainActor
  func test__selectionInitializer_givenOptionalEntityField__fieldIsPresentWithOptionalNilValue() {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .field("child", Child?.self)
      ]}

      var child: Child? { __data["child"] }

      convenience init(
        child: Child? = nil
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": Types.Human.typename,
          "child": child,
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }

      class Child: MockSelectionSet {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Human }
        override class var __selections: [Selection] {[
          .field("name", String?.self)
        ]}

        var name: String? { __data["name"] }

        convenience init(
          name: String? = nil
        ) {
          self.init(_dataDict: DataDict(data: [
            "__typename": Types.Human.typename,
            "name": name,
          ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
        }
      }
    }

    // when
    let actual = Hero(child: nil)

    // then
    expect(actual.child).to(beNil())
    expect(actual.__data._data.keys.contains("child")).to(beTrue())

    guard let childValue = actual.__data._data["child"] else {
      fail("child should be Optional.some(Optional.none)")
      return
    }
    expect(childValue).to(beNil())

    if DataDict._AnyHashableCanBeCoerced {
      guard let childValue = childValue as? Hero.Child? else {
        fail("child should be Optional.some(Optional.none).")
        return
      }
      expect(childValue).to(beNil())

    } else {
      guard let childValue = childValue.base as? Hero.Child? else {
        fail("child should be Optional.some(Optional.none).")
        return
      }
      expect(childValue).to(beNil())
    }
  }

  @MainActor
  func test__selectionInitializer_givenOptionalListOfOptionalEntitiesField__setsFieldDataCorrectly() {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .field("friends", [Friend?]?.self)
      ]}

      var friends: [Friend?]? { __data["friends"] }

      convenience init(
        friends: [Friend?]? = nil
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": Types.Human.typename,
          "friends": friends._fieldData,
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }

      class Friend: MockSelectionSet {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Human }
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
        var name: String { __data["name"] }

        convenience init(
          name: String
        ) {
          self.init(_dataDict: DataDict(data: [
            "__typename": Types.Human.typename,
            "name": name,
          ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
        }
      }
    }

    // when
    let actual = Hero(friends: [
      .init(name: "Han"),
      nil,
      .init(name: "Leia"),
    ])

    // then
    expect(actual.friends?[0]?.name).to(equal("Han"))
    expect(actual.friends?[1]).to(beNil())
    expect(actual.friends?[2]?.name).to(equal("Leia"))
  }

  @MainActor
  func test__selectionInitializer_givenOptionalListOfOptionalScalarsField__setsFieldDataCorrectly() {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: XCTFail(); return nil
      }
    })

    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .field("names", [String?]?.self)
      ]}

      var names: [String?]? { __data["names"] }

      convenience init(
        names: [String?]? = nil
      ) {
        self.init(_dataDict: DataDict(data: [
          "__typename": Types.Human.typename,
          "names": names,
        ], fulfilledFragments: [ObjectIdentifier(Self.self)]))
      }

    }

    // when
    let actual = Hero(names: [
      "Han",
      nil,
      "Leia",
    ])

    // then
    expect(actual.names?[0]).to(equal("Han"))
    expect(actual.names?[1]).to(beNil())
    expect(actual.names?[2]).to(equal("Leia"))
  }

  // MARK: Condition Tests

  func test__condition__givenStringLiteral_initializesVariableCase() {
    let condition: Selection.Condition = "filter"
    let expected: Selection.Condition = .variable(name: "filter", inverted: false)

    expect(condition).to(equal(expected))
  }

  func test__condition__givenInvertedStringLiteral_initializesInvertedVariableCase() {
    let condition: Selection.Condition = !"filter"
    let expected: Selection.Condition = .variable(name: "filter", inverted: true)

    expect(condition).to(equal(expected))
  }

  func test__condition__givenBooleanLiteral_initializesValueCase() {
    let condition: Selection.Condition = true
    let expected: Selection.Condition = .value(true)

    expect(condition).to(equal(expected))
  }

  func test__condition__givenInvertedBooleanLiteral_initializesInvertedValueCase() {
    let condition: Selection.Condition = !true
    let expected: Selection.Condition = .value(false)

    expect(condition).to(equal(expected))
  }

  func test__condition__givenIfConvenienceStringLiteral_initializesVariableCase() {
    let condition: Selection.Condition = .if("filter")
    let expected: Selection.Condition = .variable(name: "filter", inverted: false)

    expect(condition).to(equal(expected))
  }

  func test__condition__givenIfConvenienceInvertedStringLiteral_initializesInvertedVariableCase() {
    let condition: Selection.Condition = .if(!"filter")
    let expected: Selection.Condition = .variable(name: "filter", inverted: true)

    expect(condition).to(equal(expected))
  }

  // MARK Selection dict intializer
  func test__selectionDictInitializer_givenNonOptionalEntityField_givenValue__setsFieldDataCorrectly() {
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("name", String?.self)
      ]}

      var name: String? { __data["name"] }
    }

    let object: [String: Any] = [
      "__typename": "Human",
      "name": "Johnny Tsunami"
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.name).to(equal("Johnny Tsunami"))
  }
  
  func test__selectionDictInitializer_givenOptionalEntityField_givenNilValue__returnsNil() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friend", Hero?.self)
      ]}

      var friend: Hero? { __data["friend"] }
    }

    let object: [String: Any] = [
      "__typename": "Human"
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friend).to(beNil())
  }
  
  func test__selectionDictInitializer_giveDictionaryEntityFiled_givenNonOptionalValue__setsFieldDataCorrectly() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friend", Friend.self)
      ]}

      var friend: Friend { __data["friend"] }

      class Friend: MockSelectionSet {
        typealias Schema = MockSchemaMetadata

        override class var __selections: [Selection] {[
          .field("__typename", String.self),
        ]}
      }
    }

    let object: [String: Any] = [
      "__typename": "Human",
      "friend": ["__typename": "Human"]
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friend.__typename).to(equal("Human"))
  }
  
  func test__selectionDictInitializer_giveOptionalDictionaryEntityFiled_givenNilValue__returnsNil() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friend", Friend?.self)
      ]}

      var friend: Friend? { __data["friend"] }

      class Friend: MockSelectionSet {
        typealias Schema = MockSchemaMetadata

        override class var __selections: [Selection] {[
          .field("__typename", String.self),
        ]}
      }
    }

    let object: [String: Any] = [
      "__typename": "Human",
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friend).to(beNil())
  }
  
  func test__selectionDictInitializer_giveDictionaryArrayEntityField_givenNonOptionalValue__setsFieldDataCorrectly() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friends", [Friend].self)
      ]}

      var friends: [Friend] { __data["friends"] }

      class Friend: MockSelectionSet {
        typealias Schema = MockSchemaMetadata

        override class var __selections: [Selection] {[
          .field("__typename", String.self),
        ]}
      }
    }

    let object: [String: Any] = [
      "__typename": "Human",
      "friends": [
        ["__typename": "Human"],
        ["__typename": "Human"],
        ["__typename": "Human"]
      ]
    ]
    
    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friends.count).to(equal(3))
  }
  
  func test__selectionDictInitializer_giveOptionalDictionaryArrayEntityField_givenNilValue__returnsNil() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friends", [Friend]?.self)
      ]}

      var friends: [Friend]? { __data["friends"] }

      class Friend: MockSelectionSet {
        typealias Schema = MockSchemaMetadata

        override class var __selections: [Selection] {[
          .field("__typename", String.self),
        ]}
      }
    }

    let object: [String: Any] = [
      "__typename": "Human"
    ]
    
    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friends).to(beNil())
  }
  
  func test__selectionDictInitializer_giveDictionaryArrayEntityField_givenEmptyValue__returnsEmpty() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friends", [Friend].self)
      ]}

      var friends: [Friend] { __data["friends"] }

      class Friend: MockSelectionSet {
        typealias Schema = MockSchemaMetadata

        override class var __selections: [Selection] {[
          .field("__typename", String.self),
        ]}
      }
    }

    let object: [String: Any] = [
      "__typename": "Human",
      "friends": []
    ]

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.friends).to(beEmpty())
  }

  func test__selectionDictInitializer_giveNestedListEntityField_givenNonOptionalValue__setsFieldDataCorrectly() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("nestedList", [[Hero]].self)
      ]}

      var nestedList: [[Hero]] { __data["nestedList"] }
    }

    let object: [String: Any] = [
      "__typename": "Human",
      "nestedList": [[
        [
          "__typename": "Human",
          "nestedList": [[]]
        ]
      ]]
    ]
    
    let expected = try! Hero(
      data: [
        "__typename": "Human",
        "nestedList": [[]]
      ],
      variables: nil
    )

    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.nestedList).to(equal([[expected]]))
  }
  
  func test__selectionDictInitializer_giveOptionalNestedListEntityField_givenNilValue__returnsNil() {
    // given
    class Hero: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("nestedList", [[Hero]]?.self)
      ]}

      var nestedList: [[Hero]]? { __data["nestedList"] }
    }

    let object: [String: Any] = [
      "__typename": "Human",
    ]
  
    // when
    let actual = try! Hero(data: object)

    // then
    expect(actual.nestedList).to(beNil())
  }
}
