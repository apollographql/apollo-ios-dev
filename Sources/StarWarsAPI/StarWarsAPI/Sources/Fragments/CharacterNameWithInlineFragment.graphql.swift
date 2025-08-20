// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct CharacterNameWithInlineFragment: StarWarsAPI.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment CharacterNameWithInlineFragment on Character { __typename ... on Human { __typename friends { __typename appearsIn } } ... on Droid { __typename ...CharacterName ...FriendsNames } }"#
  }

  @_spi(Unsafe) public let __data: DataDict
  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

  @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
  @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .inlineFragment(AsHuman.self),
    .inlineFragment(AsDroid.self),
  ] }
  @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    CharacterNameWithInlineFragment.self
  ] }

  public var asHuman: AsHuman? { _asInlineFragment() }
  public var asDroid: AsDroid? { _asInlineFragment() }

  public init(
    __typename: String
  ) {
    self.init(unsafelyWithData: [
      "__typename": __typename,
    ])
  }

  /// AsHuman
  ///
  /// Parent Type: `Human`
  public struct AsHuman: StarWarsAPI.InlineFragment {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    public typealias RootEntityType = CharacterNameWithInlineFragment
    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Human }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("friends", [Friend?]?.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      CharacterNameWithInlineFragment.self,
      CharacterNameWithInlineFragment.AsHuman.self
    ] }

    /// This human's friends, or an empty list if they have none
    public var friends: [Friend?]? { __data["friends"] }

    public init(
      friends: [Friend?]? = nil
    ) {
      self.init(unsafelyWithData: [
        "__typename": StarWarsAPI.Objects.Human.typename,
        "friends": friends._fieldData,
      ])
    }

    /// AsHuman.Friend
    ///
    /// Parent Type: `Character`
    public struct Friend: StarWarsAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("appearsIn", [GraphQLEnum<StarWarsAPI.Episode>?].self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        CharacterNameWithInlineFragment.AsHuman.Friend.self
      ] }

      /// The movies this character appears in
      public var appearsIn: [GraphQLEnum<StarWarsAPI.Episode>?] { __data["appearsIn"] }

      public init(
        __typename: String,
        appearsIn: [GraphQLEnum<StarWarsAPI.Episode>?]
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "appearsIn": appearsIn,
        ])
      }
    }
  }

  /// AsDroid
  ///
  /// Parent Type: `Droid`
  public struct AsDroid: StarWarsAPI.InlineFragment {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    public typealias RootEntityType = CharacterNameWithInlineFragment
    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Droid }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .fragment(CharacterName.self),
      .fragment(FriendsNames.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      CharacterNameWithInlineFragment.self,
      CharacterNameWithInlineFragment.AsDroid.self,
      CharacterName.self,
      FriendsNames.self
    ] }

    /// The name of the character
    public var name: String { __data["name"] }
    /// The friends of the character, or an empty list if they have none
    public var friends: [Friend?]? { __data["friends"] }

    public struct Fragments: FragmentContainer {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      public var characterName: CharacterName { _toFragment() }
      public var friendsNames: FriendsNames { _toFragment() }
    }

    public init(
      name: String,
      friends: [Friend?]? = nil
    ) {
      self.init(unsafelyWithData: [
        "__typename": StarWarsAPI.Objects.Droid.typename,
        "name": name,
        "friends": friends._fieldData,
      ])
    }

    public typealias Friend = FriendsNames.Friend
  }
}
