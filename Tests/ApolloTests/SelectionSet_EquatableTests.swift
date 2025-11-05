import XCTest
@testable @_spi(Execution) import Apollo
@testable @_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import Nimble

class SelectionSet_EquatableTests: XCTestCase {

  // MARK: - Helpers

  struct Types {
    static let Hero = Interface(name: "Hero", implementingObjects: ["Character"])
    static let Character = Object(typename: "Character", implementedInterfaces: [Hero.self])
    static let Content = Interface(name: "Content", implementingObjects: ["Character"])
    static let Human = Interface(name: "Human", implementingObjects: [])
    static let Height = Object(typename: "Height", implementedInterfaces: [])
    static let Item = Object(typename: "Item", implementedInterfaces: [])
  }

  final class Hero: MockSelectionSet, @unchecked Sendable {
    typealias Schema = MockSchemaMetadata

    override class var __parentType: any ParentType { Types.Hero }
    override class var __selections: [Selection] {[
      .field("__typename", String.self),
      .field("name", String?.self),
      .field("height", Height?.self),
      .inlineFragment(AsCharacter.self),
      .inlineFragment(AsContent.self),
    ]}
    override class var __fulfilledFragments: [any SelectionSet.Type] {
      [Hero.self]
    }

    final class AsCharacter: ConcreteMockTypeCase<Hero>, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Character }
      override class var __selections: [Selection] {[
        .field("age", Int.self),
        .field("height", Height?.self)
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [Hero.self, AsCharacter.self]
      }

      final class Height: ConcreteMockTypeCase<Hero.Height>, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Height }
        override class var __selections: [Selection] {[
          .field("feet", Int.self)
        ]}
        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [Height.self]
        }
      }
    }

    final class AsContent: ConcreteMockTypeCase<Hero>, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Content }
      override class var __selections: [Selection] {[
        .field("id", Int.self),
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [Hero.self, AsContent.self]
      }
    }

    final class Height: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Height }
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("inches", Int.self),
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [Height.self]
      }
    }
  }

  // MARK: - Tests

  func test__equatable__sameValues_returns_true() {
    // given
    let data: JSONObject = [
      "__typename": "Character",
      "name": "Name1"
    ]

    // when
    let selectionSet1 = Hero(_dataDict: DataDict(
      data: data,
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    let selectionSet2 = Hero(_dataDict: DataDict(
      data: data,
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__differentValue_returns_false() {
    // when
    let selectionSet1 = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "name": "Name 1"
      ],
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    let selectionSet2 = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "name": "Name 2"
      ],
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  // MARK: TypeCase (Inline Fragment)

  func test__equatable__typeCase_differentValue_forFieldFromRootType_returns_false() {
    // given

    // when
    let selectionSet1 = Hero.AsCharacter(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "name": "Name 1",
        "age": 25
      ],
      fulfilledFragments: Hero.AsCharacter.__fulfilledFragmentIds
    ))

    let selectionSet2 = Hero.AsCharacter(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "name": "Name 2",
        "age": 25
      ],
      fulfilledFragments: Hero.AsCharacter.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }


  func test__equatable__typeCase_differentValue_forFieldFromUnrelatedTypeCase_returns_true() {
    // given

    // when
    let selectionSet1 = Hero.AsCharacter(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "name": "Name 1",
        "age": 25,
        "id": 1 // From Unrelated sibling Hero.AsContent
      ],
      fulfilledFragments: Hero.AsCharacter.__fulfilledFragmentIds
    ))

    let selectionSet2 = Hero.AsCharacter(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "name": "Name 1",
        "age": 25,
        "id": 2 // From Unrelated sibling Hero.AsContent
      ],
      fulfilledFragments: Hero.AsCharacter.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__typeCase_differentValue_forFieldFromMatchedChildTypeCase_returns_false() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
        .inlineFragment(AsCharacter.self),
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self]
      }

      final class AsCharacter: ConcreteMockTypeCase<Hero>, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Character }
        override class var __selections: [Selection] {[
          .field("age", Int.self),
        ]}
        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [HeroFragment.self, HeroFragment.AsCharacter.self]
        }
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 25
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(HeroFragment.AsCharacter.self)
      ]
    ))

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 26
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(HeroFragment.AsCharacter.self)
      ]
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  func test__equatable__typeCase_fulfilledInOneButNotOther_returns_false() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
        .inlineFragment(AsCharacter.self),
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self]
      }

      final class AsCharacter: ConcreteMockTypeCase<Hero>, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Character }
        override class var __selections: [Selection] {[
          .field("age", Int.self),
        ]}
        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [HeroFragment.self, HeroFragment.AsCharacter.self]
        }
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 25
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(HeroFragment.AsCharacter.self)
      ]
    ))

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self)
      ]
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  // MARK: Include/Skip (Conditional)

  func test__equatable__includeCondition__differentValue_forFieldFromIncludedTypeCase_returns_false() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
        .include(if: "a", .inlineFragment(IfA.self))
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self]
      }

      final class IfA: ConcreteMockTypeCase<Hero>, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Character }
        override class var __selections: [Selection] {[
          .field("age", Int.self),
        ]}
        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [HeroFragment.self, HeroFragment.IfA.self]
        }
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 25
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(HeroFragment.IfA.self)
      ]
    ))

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 26
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(HeroFragment.IfA.self)
      ]
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  func test__equatable__includeCondition__differentValue_forFieldFromExcludedTypeCase_returns_true() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
        .include(if: "a", .inlineFragment(IfA.self))
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self]
      }

      final class IfA: ConcreteMockTypeCase<Hero>, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Character }
        override class var __selections: [Selection] {[
          .field("age", Int.self),
        ]}
        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [HeroFragment.self, HeroFragment.IfA.self]
        }
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 25
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self)
      ]
    ))

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 26
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self)
      ]
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__includeCondition__includedInOneButNotOther_returns_false() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
        .include(if: "a", .inlineFragment(IfA.self))
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self]
      }

      final class IfA: ConcreteMockTypeCase<Hero>, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Character }
        override class var __selections: [Selection] {[
          .field("age", Int.self),
        ]}
        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [HeroFragment.self, HeroFragment.IfA.self]
        }
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 25
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(HeroFragment.IfA.self)
      ]
    ))

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",        
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self)
      ]
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  func test__equatable__includeCondition__singleField_sameValues_returns_true() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
        .include(if: "includeAge", .field("age", Int?.self))
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self]
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 25
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self)
      ]
    ))

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 25
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self)
      ]
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__includeCondition__singleField_differentValues_returns_false() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
        .include(if: "includeAge", .field("age", Int?.self))
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self]
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 25
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self)
      ]
    ))

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 30
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self)
      ]
    ))

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

      override class var __parentType: any ParentType { Types.Hero }
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

          override class var __parentType: any ParentType { Types.Character }
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

      override class var __parentType: any ParentType { Types.Hero }
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

  // MARK: Named Fragment

  func test__equatable__namedFragment_differentValue_forFieldInChildNamedFragment_returns_false() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .fragment(NameFragment.self),
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self, NameFragment.self]
      }
    }

    final class NameFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [NameFragment.self]
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1"
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(NameFragment.self)
      ]
    ))

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 2"
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(NameFragment.self)
      ]
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  func test__equatable__namedFragment_differentValue_forFieldInParentSourceOfNamedFragment_returns_true() {
    // given
    struct HeroFragment: RootSelectionSet, Fragment, @unchecked Sendable {
      var __data: ApolloAPI.DataDict
      init(_dataDict: ApolloAPI.DataDict) { self.__data = _dataDict }

      typealias Schema = MockSchemaMetadata

      static var __parentType: any ParentType { Types.Hero }
      static var __selections: [Selection] {[
        .field("age", Int.self),
        .fragment(NameFragment.self),
      ]}
      static var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self, NameFragment.self]
      }

      struct Fragments: FragmentContainer {
        var __data: DataDict
        init(_dataDict: DataDict) { self.__data = _dataDict }

        var nameFragment: NameFragment { _toFragment() }
      }
    }

    final class NameFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [NameFragment.self]
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 25
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(NameFragment.self)
      ]
    )).fragments.nameFragment

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1",
        "age": 26
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(NameFragment.self)
      ]
    )).fragments.nameFragment

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  // MARK: Deferred

  func test__equatable__deferredFragment_differentValue_forFieldInFulfilledDeferrableFragment_returns_false() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .deferred(NameFragment.self, label: "Name")
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self]
      }
      class var __deferredFragments: [any Deferrable.Type] {
        [NameFragment.self]
      }
    }

    final class NameFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [NameFragment.self]
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1"
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(NameFragment.self)
      ]
    ))

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 2"
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(NameFragment.self)
      ]
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  func test__equatable__deferredFragment_differentValue_forFieldInUnfulfilledDeferrableFragment_returns_true() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .deferred(NameFragment.self, label: "Name")
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self]
      }
      class var __deferredFragments: [any Deferrable.Type] {
        [NameFragment.self]
      }
    }

    final class NameFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [NameFragment.self]
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1"
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self)
      ]
    ))

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 2"
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self)
      ]
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__deferredFragment__deferrableFragmentFulfilledInOneButNotOther_returns_false() {
    // given
    final class HeroFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .deferred(NameFragment.self, label: "Name")
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HeroFragment.self]
      }
      class var __deferredFragments: [any Deferrable.Type] {
        [NameFragment.self]
      }
    }

    final class NameFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Hero }
      override class var __selections: [Selection] {[
        .field("name", String?.self),
      ]}
      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [NameFragment.self]
      }
    }

    // when
    let selectionSet1 = HeroFragment(_dataDict: DataDict(
      data: [
        "name": "Name 1"
      ],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
        ObjectIdentifier(NameFragment.self)
      ]
    ))

    let selectionSet2 = HeroFragment(_dataDict: DataDict(
      data: [:],
      fulfilledFragments: [
        ObjectIdentifier(HeroFragment.self),
      ]
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  // MARK: Child Objects

  func test__equatable__childObject__sameValues_returns_true() {
    // given
    let heightData: JSONObject = [
      "__typename": "Height",
      "inches": 5
    ]
    let data: JSONObject = [
      "__typename": "Character",
      "height": DataDict(data: heightData, fulfilledFragments: [
        ObjectIdentifier(Hero.Height.self)
      ])
    ]

    // when
    let selectionSet1 = Hero(_dataDict: DataDict(
      data: data,
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    let selectionSet2 = Hero(_dataDict: DataDict(
      data: data,
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__childObject__differentValues_returns_false() {
    // when
    let selectionSet1 = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "height": DataDict(data: [
          "__typename": "Height",
          "inches": 5
        ], fulfilledFragments: [
          ObjectIdentifier(Hero.Height.self)
        ])
      ],
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    let selectionSet2 = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "height": DataDict(data: [
          "__typename": "Height",
          "inches": 6
        ], fulfilledFragments: [
          ObjectIdentifier(Hero.Height.self)
        ])
      ],
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  func test__equatable__childObject_onNamedFragment__differentValues_forFieldNotInFragment_returns_true() {
    // given
    final class HumanFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .field("height", Height?.self)
      ]}

      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HumanFragment.self]
      }

      final class Height: MockSelectionSet, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Height }
        override class var __selections: [Selection] {[
          .field("feet", Int.self)
        ]}
        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [Height.self]
        }
      }
    }

    // when
    let selectionSet1 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "height": DataDict(data: [
          "__typename": "Height",
          "inches": 3,
          "feet": 1
        ], fulfilledFragments: [
          ObjectIdentifier(HumanFragment.Height.self)
        ])
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    let selectionSet2 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "height": DataDict(data: [
          "__typename": "Height",
          "inches": 2,
          "feet": 1
        ], fulfilledFragments: [
          ObjectIdentifier(HumanFragment.Height.self)
        ])
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    // then    
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  // MARK: - List Fields

  func test__equatable__listOfScalarsField__sameValues_returns_true() {
    // given
    final class HumanFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .field("ids", [Int].self)
      ]}

      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HumanFragment.self]
      }
    }

    // when
    let selectionSet1 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "items": [1, 2, 3]
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    let selectionSet2 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "items": [1, 2, 3]
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__listOfObjectsField__sameValues_returns_true() {
    // given
    final class HumanFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .field("items", [Item].self)
      ]}

      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HumanFragment.self]
      }

      final class Item: MockSelectionSet, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Item }
        override class var __selections: [Selection] {[
          .field("id", Int.self)
        ]}
        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [Item.self]
        }
      }
    }

    // when
    let selectionSet1 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "items": [
          DataDict(data: [
            "__typename": "Item",
            "id": 1,
          ], fulfilledFragments: [
            ObjectIdentifier(HumanFragment.Item.self)
          ])
        ]
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    let selectionSet2 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "items": [
          DataDict(data: [
            "__typename": "Item",
            "id": 1,
          ], fulfilledFragments: [
            ObjectIdentifier(HumanFragment.Item.self)
          ])
        ]
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__listOfObjectsField__emptyList_returns_true() {
    // given
    final class HumanFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .field("items", [Item].self)
      ]}

      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HumanFragment.self]
      }

      final class Item: MockSelectionSet, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Item }
        override class var __selections: [Selection] {[
          .field("id", Int.self)
        ]}
        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [Item.self]
        }
      }
    }

    // when
    let selectionSet1 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "items": [] as JSONValue
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    let selectionSet2 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "items": [] as JSONValue
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__2DimensionalListOfObjectsField__sameValues_returns_true() {
    // given
    final class HumanFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .field("nestedItems", [[Item]].self)
      ]}

      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HumanFragment.self]
      }

      final class Item: MockSelectionSet, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Item }
        override class var __selections: [Selection] {[
          .field("id", Int.self)
        ]}
        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [Item.self]
        }
      }
    }

    // when
    let selectionSet1 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "nestedItems": [[
          DataDict(data: [
            "__typename": "Item",
            "id": 1,
          ], fulfilledFragments: [
            ObjectIdentifier(HumanFragment.Item.self)
          ])
        ]]
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    let selectionSet2 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "nestedItems": [[
          DataDict(data: [
            "__typename": "Item",
            "id": 1,
          ], fulfilledFragments: [
            ObjectIdentifier(HumanFragment.Item.self)
          ])
        ]]
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__2DimensionalListOfObjectsField__differentValues_returns_false() {
    // given
    final class HumanFragment: MockFragment, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Human }
      override class var __selections: [Selection] {[
        .field("nestedItems", [[Item]].self)
      ]}

      override class var __fulfilledFragments: [any SelectionSet.Type] {
        [HumanFragment.self]
      }

      final class Item: MockSelectionSet, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Item }
        override class var __selections: [Selection] {[
          .field("id", Int.self)
        ]}
        override class var __fulfilledFragments: [any SelectionSet.Type] {
          [Item.self]
        }
      }
    }

    // when
    let selectionSet1 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "nestedItems": [
          [
            DataDict(data: [
              "__typename": "Item",
              "id": 1,
            ], fulfilledFragments: [
              ObjectIdentifier(HumanFragment.Item.self)
            ])
          ],
          [
            DataDict(data: [
              "__typename": "Item",
              "id": 2,
            ], fulfilledFragments: [
              ObjectIdentifier(HumanFragment.Item.self)
            ])
          ]
        ]
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    let selectionSet2 = HumanFragment(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "nestedItems": [
          [
            DataDict(data: [
              "__typename": "Item",
              "id": 1,
            ], fulfilledFragments: [
              ObjectIdentifier(HumanFragment.Item.self)
            ])
          ],
          [
            DataDict(data: [
              "__typename": "Item",
              "id": 3,
            ], fulfilledFragments: [
              ObjectIdentifier(HumanFragment.Item.self)
            ])
          ]
        ]
      ],
      fulfilledFragments: HumanFragment.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).toNot(equal(selectionSet2))
    expect(selectionSet1.hashValue).toNot(equal(selectionSet2.hashValue))
  }

  // MARK: - Integration Tests

  func test__equatable__givenQueryResponseFetchedFromStore()
    async throws
  {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("hero", Hero.self)
        ]
      }
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
            .field("friend", Friend.self),
          ]
        }
        var friend: Friend { __data["friend"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
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
    try await store.publish(records: [
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "__typename": "Droid",
        "name": "R2-D2",
        "friend": CacheReference("1000"),
      ],
      "1000": ["__typename": "Human", "name": "Luke Skywalker"],
    ])

    let expected = try await GivenSelectionSet(data: [
      "hero": [
        "__typename": "Droid",
        "name": "R2-D2",
        "friend": ["__typename": "Human", "name": "Luke Skywalker"]
      ]
    ])

    // when
    let query = MockQuery<GivenSelectionSet>()

    let response = try await store.load(query)

    expect(response!.data).to(equal(expected))
  }

  // MARK: - Null/nil tests

  func test__equatable__optionalChildObject__isNullOnBoth_returns_true() {
    // when
    let selectionSet1 = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "height": NSNull()
      ],
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    let selectionSet2 = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "height": NSNull()
      ],
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }

  func test__equatable__optionalChildObject__isNullAndNil_returns_true() {
    // when
    let selectionSet1 = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "height": NSNull()
      ],
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    let selectionSet2 = Hero(_dataDict: DataDict(
      data: [
        "__typename": "Character",
        "height": nil
      ],
      fulfilledFragments: Hero.__fulfilledFragmentIds
    ))

    // then
    expect(selectionSet1).to(equal(selectionSet2))
    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
  }
}
