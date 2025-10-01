// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct HeroAndFriendsNamesWithFragmentQuery: GraphQLQuery {
  public static let operationName: String = "HeroAndFriendsNamesWithFragment"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "599cd7d91ede7a5508cdb26b424e3b8e99e6c2c5575b799f6090695289ff8e99",
    definition: .init(
      #"query HeroAndFriendsNamesWithFragment($episode: Episode) { hero(episode: $episode) { __typename name ...FriendsNames } }"#,
      fragments: [FriendsNames.self]
    ))

  public var episode: GraphQLNullable<GraphQLEnum<Episode>>

  public init(episode: GraphQLNullable<GraphQLEnum<Episode>>) {
    self.episode = episode
  }

  @_spi(Unsafe) public var __variables: Variables? { ["episode": episode] }

  public struct Data: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("hero", Hero?.self, arguments: ["episode": .variable("episode")]),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      HeroAndFriendsNamesWithFragmentQuery.Data.self
    ] }

    public var hero: Hero? { __data["hero"] }

    public init(
      hero: Hero? = nil
    ) {
      self.init(unsafelyWithData: [
        "__typename": StarWarsAPI.Objects.Query.typename,
        "hero": hero._fieldData,
      ])
    }

    /// Hero
    ///
    /// Parent Type: `Character`
    public struct Hero: StarWarsAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
        .fragment(FriendsNames.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HeroAndFriendsNamesWithFragmentQuery.Data.Hero.self,
        FriendsNames.self
      ] }

      /// The name of the character
      public var name: String { __data["name"] }
      /// The friends of the character, or an empty list if they have none
      public var friends: [Friend?]? { __data["friends"] }

      public struct Fragments: FragmentContainer {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public var friendsNames: FriendsNames { _toFragment() }
      }

      public init(
        __typename: String,
        name: String,
        friends: [Friend?]? = nil
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "name": name,
          "friends": friends._fieldData,
        ])
      }

      public typealias Friend = FriendsNames.Friend
    }
  }
}
