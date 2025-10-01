// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct HeroNameAndAppearsInWithFragmentQuery: GraphQLQuery {
  public static let operationName: String = "HeroNameAndAppearsInWithFragment"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "4ae734544e707769dbe7be2ff25cb2abd75d03634bda31a53ec7ae6e9e661fa5",
    definition: .init(
      #"query HeroNameAndAppearsInWithFragment($episode: Episode) { hero(episode: $episode) { __typename ...CharacterNameAndAppearsIn } }"#,
      fragments: [CharacterNameAndAppearsIn.self]
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
      HeroNameAndAppearsInWithFragmentQuery.Data.self
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
        .fragment(CharacterNameAndAppearsIn.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HeroNameAndAppearsInWithFragmentQuery.Data.Hero.self,
        CharacterNameAndAppearsIn.self
      ] }

      /// The name of the character
      public var name: String { __data["name"] }
      /// The movies this character appears in
      public var appearsIn: [GraphQLEnum<StarWarsAPI.Episode>?] { __data["appearsIn"] }

      public struct Fragments: FragmentContainer {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public var characterNameAndAppearsIn: CharacterNameAndAppearsIn { _toFragment() }
      }

      public init(
        __typename: String,
        name: String,
        appearsIn: [GraphQLEnum<StarWarsAPI.Episode>?]
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "name": name,
          "appearsIn": appearsIn,
        ])
      }
    }
  }
}
