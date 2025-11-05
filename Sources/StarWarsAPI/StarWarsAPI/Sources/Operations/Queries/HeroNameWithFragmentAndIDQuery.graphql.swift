// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class HeroNameWithFragmentAndIDQuery: GraphQLQuery {
  public static let operationName: String = "HeroNameWithFragmentAndID"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "003467c64c7ab5a5bacfa69442c9611d5899fe9bd63ab726b241c02b1719327a",
    definition: .init(
      #"query HeroNameWithFragmentAndID($episode: Episode) { hero(episode: $episode) { __typename id ...CharacterName } }"#,
      fragments: [CharacterName.self]
    ))

  public var episode: GraphQLNullable<GraphQLEnum<Episode>>

  public init(episode: GraphQLNullable<GraphQLEnum<Episode>>) {
    self.episode = episode
  }

  public var __variables: Variables? { ["episode": episode] }

  public struct Data: StarWarsAPI.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("hero", Hero?.self, arguments: ["episode": .variable("episode")]),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      HeroNameWithFragmentAndIDQuery.Data.self
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
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", StarWarsAPI.ID.self),
        .fragment(CharacterName.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HeroNameWithFragmentAndIDQuery.Data.Hero.self,
        CharacterName.self
      ] }

      /// The ID of the character
      public var id: StarWarsAPI.ID { __data["id"] }
      /// The name of the character
      public var name: String { __data["name"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var characterName: CharacterName { _toFragment() }
      }

      public init(
        __typename: String,
        id: StarWarsAPI.ID,
        name: String
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "id": id,
          "name": name,
        ])
      }
    }
  }
}
