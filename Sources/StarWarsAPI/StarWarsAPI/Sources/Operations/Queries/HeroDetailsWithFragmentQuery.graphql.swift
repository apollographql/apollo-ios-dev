// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class HeroDetailsWithFragmentQuery: GraphQLQuery {
  public static let operationName: String = "HeroDetailsWithFragment"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "ffe0a8189e4b2c1fa2c309e2c545cd49b61fd9428b64aa62582513d7413beb11",
    definition: .init(
      #"query HeroDetailsWithFragment($episode: Episode) { hero(episode: $episode) { __typename ...HeroDetails } }"#,
      fragments: [HeroDetails.self]
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
      HeroDetailsWithFragmentQuery.Data.self
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
        .fragment(HeroDetails.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HeroDetailsWithFragmentQuery.Data.Hero.self,
        HeroDetails.self
      ] }

      /// The name of the character
      public var name: String { __data["name"] }

      public var asHuman: AsHuman? { _asInlineFragment() }
      public var asDroid: AsDroid? { _asInlineFragment() }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var heroDetails: HeroDetails { _toFragment() }
      }

      public init(
        __typename: String,
        name: String
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "name": name,
        ])
      }

      /// Hero.AsHuman
      ///
      /// Parent Type: `Human`
      public struct AsHuman: StarWarsAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = HeroDetailsWithFragmentQuery.Data.Hero
        public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Human }
        public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
          HeroDetailsWithFragmentQuery.Data.Hero.self,
          HeroDetails.self,
          HeroDetails.AsHuman.self
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          HeroDetailsWithFragmentQuery.Data.Hero.self,
          HeroDetailsWithFragmentQuery.Data.Hero.AsHuman.self,
          HeroDetails.self,
          HeroDetails.AsHuman.self
        ] }

        /// The name of the character
        public var name: String { __data["name"] }
        /// Height in the preferred unit, default is meters
        public var height: Double? { __data["height"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var heroDetails: HeroDetails { _toFragment() }
        }

        public init(
          name: String,
          height: Double? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": StarWarsAPI.Objects.Human.typename,
            "name": name,
            "height": height,
          ])
        }
      }

      /// Hero.AsDroid
      ///
      /// Parent Type: `Droid`
      public struct AsDroid: StarWarsAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = HeroDetailsWithFragmentQuery.Data.Hero
        public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Droid }
        public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
          HeroDetailsWithFragmentQuery.Data.Hero.self,
          HeroDetails.self,
          HeroDetails.AsDroid.self
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          HeroDetailsWithFragmentQuery.Data.Hero.self,
          HeroDetailsWithFragmentQuery.Data.Hero.AsDroid.self,
          HeroDetails.self,
          HeroDetails.AsDroid.self
        ] }

        /// The name of the character
        public var name: String { __data["name"] }
        /// This droid's primary function
        public var primaryFunction: String? { __data["primaryFunction"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var heroDetails: HeroDetails { _toFragment() }
        }

        public init(
          name: String,
          primaryFunction: String? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": StarWarsAPI.Objects.Droid.typename,
            "name": name,
            "primaryFunction": primaryFunction,
          ])
        }
      }
    }
  }
}
