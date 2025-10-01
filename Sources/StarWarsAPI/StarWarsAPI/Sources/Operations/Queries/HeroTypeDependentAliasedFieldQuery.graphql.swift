// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct HeroTypeDependentAliasedFieldQuery: GraphQLQuery {
  public static let operationName: String = "HeroTypeDependentAliasedField"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "5b1ed6a84e96a4e48a3cad675ebb46020bce176f47361d097d8a0a824b7b8452",
    definition: .init(
      #"query HeroTypeDependentAliasedField($episode: Episode) { hero(episode: $episode) { __typename ... on Human { __typename property: homePlanet } ... on Droid { __typename property: primaryFunction } } }"#
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
      HeroTypeDependentAliasedFieldQuery.Data.self
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
        .inlineFragment(AsHuman.self),
        .inlineFragment(AsDroid.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HeroTypeDependentAliasedFieldQuery.Data.Hero.self
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

      /// Hero.AsHuman
      ///
      /// Parent Type: `Human`
      public struct AsHuman: StarWarsAPI.InlineFragment {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = HeroTypeDependentAliasedFieldQuery.Data.Hero
        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Human }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("homePlanet", alias: "property", String?.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          HeroTypeDependentAliasedFieldQuery.Data.Hero.self,
          HeroTypeDependentAliasedFieldQuery.Data.Hero.AsHuman.self
        ] }

        /// The home planet of the human, or null if unknown
        public var property: String? { __data["property"] }

        public init(
          property: String? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": StarWarsAPI.Objects.Human.typename,
            "property": property,
          ])
        }
      }

      /// Hero.AsDroid
      ///
      /// Parent Type: `Droid`
      public struct AsDroid: StarWarsAPI.InlineFragment {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = HeroTypeDependentAliasedFieldQuery.Data.Hero
        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Droid }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("primaryFunction", alias: "property", String?.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          HeroTypeDependentAliasedFieldQuery.Data.Hero.self,
          HeroTypeDependentAliasedFieldQuery.Data.Hero.AsDroid.self
        ] }

        /// This droid's primary function
        public var property: String? { __data["property"] }

        public init(
          property: String? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": StarWarsAPI.Objects.Droid.typename,
            "property": property,
          ])
        }
      }
    }
  }
}
