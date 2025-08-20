import XCTest
import Nimble
@testable import Apollo
@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloInternalTestHelpers

class MutatingSelectionSetTests: XCTestCase {

  func test__selectionSet_dataDict_hasValueSemantics() {
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

      init(
        __typename: String,
        hero: Hero
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "hero": hero._fieldData,
          ], fulfilledFragments: [
            ObjectIdentifier(Self.self),
          ]))
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

        init(
          __typename: String,
          name: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "name": name,
            ], fulfilledFragments: [
              ObjectIdentifier(Self.self),
            ]))
        }
      }
    }

    // when
    let data = GivenSelectionSet(
      __typename: "Query",
      hero: .init(
        __typename: "Hero",
        name: "Luke"
      )
    )

    let hero = data.hero
    var hero2 = hero

    hero2.name = "Leia"

    var data2 = data
    data2.hero = hero2

    // then
    expect(data.hero.name).to(equal("Luke"))
    expect(hero.name).to(equal("Luke"))
    expect(hero2.name).to(equal("Leia"))
    expect(data2.hero.name).to(equal("Leia"))
  }

  func test__mutateIfFulfilled_typeCaseProperties__typeCaseIsFulfilled_mutatesProperties() throws {
    // given
    var model = TypeCaseSelectionSet.AsHero(__typename: "Hero", name: "A", age: 1).asRootEntityType

    // when
    let didMutate = model.mutateIfFulfilled(\.asHero) { hero in
      hero.name = "B"
      hero.age = 2
    }

    // then
    expect(didMutate).to(beTrue())
    expect(model.asHero?.name).to(equal("B"))
    expect(model.asHero?.age).to(equal(2))
  }

  func test__mutateIfFulfilled_typeCaseProperty__typeCaseIsNotFulfilled_returnsFalseAndDoesNotCallMutationBlock() throws {
    // given
    var model = TypeCaseSelectionSet(__typename: "Hero")

    // when
    let didMutate = model.mutateIfFulfilled(\.asHero) { hero in
      fail("Should not call mutation block")
    }

    // then
    expect(didMutate).to(beFalse())
    expect(model.asHero).to(beNil())
  }

  func test__mutateIfFulfilled_doubleNestedTypeCaseProperties__typeCaseIsFulfilled_mutatesProperties() throws {
    // given
    var model = TypeCaseSelectionSet.AsHero.AsHuman(
      __typename: "Hero", name: "A", age: 1, birthMonth: "Jan"
    ).asRootEntityType

    // when
    let didMutate = model.mutateIfFulfilled(\.asHero?.asHuman) { hero in
      hero.birthMonth = "Feb"
    }

    // then
    expect(didMutate).to(beTrue())
    expect(model.asHero?.asHuman?.birthMonth).to(equal("Feb"))
  }

  // MARK: - Shared Models

  struct TypeCaseSelectionSet: MockMutableRootSelectionSet {
    public var __data: DataDict = .empty()
    init(_dataDict: DataDict) { __data = _dataDict }

    static var __selections: [Selection] { [
      .inlineFragment(AsHero.self)
    ]}

    var asHero: AsHero? { _asInlineFragment() }

    init(
      __typename: String
    ) {
      self.init(_dataDict: DataDict(
        data: [
          "__typename": __typename
        ], fulfilledFragments: [
          ObjectIdentifier(Self.self),
        ]))
    }

    struct AsHero: MockMutableInlineFragment {
      typealias RootEntityType = TypeCaseSelectionSet

      static var __parentType: any ApolloAPI.ParentType { Object.mock }

      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] { [
        .field("name", String.self),
        .inlineFragment(AsHuman.self)
      ]}

      var asHuman: AsHuman? { _asInlineFragment() }

      var name: String {
        get { __data["name"] }
        set { __data["name"] = newValue }
      }

      var age: Int32? {
        get { __data["age"] }
        set { __data["age"] = newValue }
      }

      init(
        __typename: String,
        name: String,
        age: Int32
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "name": name,
            "age": age,
          ], fulfilledFragments: [
            ObjectIdentifier(TypeCaseSelectionSet.self),
            ObjectIdentifier(Self.self),
          ]))
      }

      struct AsHuman: MockMutableInlineFragment {
        typealias RootEntityType = TypeCaseSelectionSet

        static var __parentType: any ApolloAPI.ParentType { Object.mock }

        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] { [
          .field("birthMonth", String?.self)
        ]}

        var birthMonth: String? {
          get { __data["birthMonth"] }
          set { __data["birthMonth"] = newValue }
        }

        init(
          __typename: String,
          name: String,
          age: Int32,
          birthMonth: String?
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "name": name,
              "age": age,
              "birthMonth": birthMonth
            ], fulfilledFragments: [
              ObjectIdentifier(Self.self),
              ObjectIdentifier(AsHero.self),
              ObjectIdentifier(TypeCaseSelectionSet.self),
            ]))
        }
      }
    }
  }

}
