// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Unsafe) import ApolloAPI

public struct HeroParentTypeDependentFieldQuery: GraphQLQuery {
  public static let operationName: String = "HeroParentTypeDependentField"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "dc3b582f2baa66cfb5cd53eb3c215933427fd0537076767c8e0ef894d3990d15",
    definition: .init(
      #"query HeroParentTypeDependentField($episode: Episode) { hero(episode: $episode) { __typename name ... on Human { __typename friends { __typename name ... on Human { __typename height(unit: FOOT) } } } ... on Droid { __typename friends { __typename name ... on Human { __typename height(unit: METER) } } } } }"#
    ))

  public var episode: GraphQLNullable<GraphQLEnum<Episode>>

  public init(episode: GraphQLNullable<GraphQLEnum<Episode>>) {
    self.episode = episode
  }

  public var __variables: Variables? { ["episode": episode] }

  public struct Data: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("hero", Hero?.self, arguments: ["episode": .variable("episode")]),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      HeroParentTypeDependentFieldQuery.Data.self
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

      public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
        .inlineFragment(AsHuman.self),
        .inlineFragment(AsDroid.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HeroParentTypeDependentFieldQuery.Data.Hero.self
      ] }

      /// The name of the character
      public var name: String { __data["name"] }

      public var asHuman: AsHuman? { _asInlineFragment() }
      public var asDroid: AsDroid? { _asInlineFragment() }

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
      public struct AsHuman: StarWarsAPI.InlineFragment {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = HeroParentTypeDependentFieldQuery.Data.Hero
        public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Human }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("friends", [Friend?]?.self),
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          HeroParentTypeDependentFieldQuery.Data.Hero.self,
          HeroParentTypeDependentFieldQuery.Data.Hero.AsHuman.self
        ] }

        /// This human's friends, or an empty list if they have none
        public var friends: [Friend?]? { __data["friends"] }
        /// The name of the character
        public var name: String { __data["name"] }

        public init(
          friends: [Friend?]? = nil,
          name: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": StarWarsAPI.Objects.Human.typename,
            "friends": friends._fieldData,
            "name": name,
          ])
        }

        /// Hero.AsHuman.Friend
        ///
        /// Parent Type: `Character`
        public struct Friend: StarWarsAPI.SelectionSet {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("name", String.self),
            .inlineFragment(AsHuman.self),
          ] }
          public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            HeroParentTypeDependentFieldQuery.Data.Hero.AsHuman.Friend.self
          ] }

          /// The name of the character
          public var name: String { __data["name"] }

          public var asHuman: AsHuman? { _asInlineFragment() }

          public init(
            __typename: String,
            name: String
          ) {
            self.init(unsafelyWithData: [
              "__typename": __typename,
              "name": name,
            ])
          }

          /// Hero.AsHuman.Friend.AsHuman
          ///
          /// Parent Type: `Human`
          public struct AsHuman: StarWarsAPI.InlineFragment {
            @_spi(Unsafe) public let __data: DataDict
            @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

            public typealias RootEntityType = HeroParentTypeDependentFieldQuery.Data.Hero.AsHuman.Friend
            public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Human }
            public static var __selections: [ApolloAPI.Selection] { [
              .field("height", Double?.self, arguments: ["unit": "FOOT"]),
            ] }
            public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              HeroParentTypeDependentFieldQuery.Data.Hero.AsHuman.Friend.self,
              HeroParentTypeDependentFieldQuery.Data.Hero.AsHuman.Friend.AsHuman.self
            ] }

            /// Height in the preferred unit, default is meters
            public var height: Double? { __data["height"] }
            /// The name of the character
            public var name: String { __data["name"] }

            public init(
              height: Double? = nil,
              name: String
            ) {
              self.init(unsafelyWithData: [
                "__typename": StarWarsAPI.Objects.Human.typename,
                "height": height,
                "name": name,
              ])
            }
          }
        }
      }

      /// Hero.AsDroid
      ///
      /// Parent Type: `Droid`
      public struct AsDroid: StarWarsAPI.InlineFragment {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = HeroParentTypeDependentFieldQuery.Data.Hero
        public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Droid }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("friends", [Friend?]?.self),
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          HeroParentTypeDependentFieldQuery.Data.Hero.self,
          HeroParentTypeDependentFieldQuery.Data.Hero.AsDroid.self
        ] }

        /// This droid's friends, or an empty list if they have none
        public var friends: [Friend?]? { __data["friends"] }
        /// The name of the character
        public var name: String { __data["name"] }

        public init(
          friends: [Friend?]? = nil,
          name: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": StarWarsAPI.Objects.Droid.typename,
            "friends": friends._fieldData,
            "name": name,
          ])
        }

        /// Hero.AsDroid.Friend
        ///
        /// Parent Type: `Character`
        public struct Friend: StarWarsAPI.SelectionSet {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("name", String.self),
            .inlineFragment(AsHuman.self),
          ] }
          public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            HeroParentTypeDependentFieldQuery.Data.Hero.AsDroid.Friend.self
          ] }

          /// The name of the character
          public var name: String { __data["name"] }

          public var asHuman: AsHuman? { _asInlineFragment() }

          public init(
            __typename: String,
            name: String
          ) {
            self.init(unsafelyWithData: [
              "__typename": __typename,
              "name": name,
            ])
          }

          /// Hero.AsDroid.Friend.AsHuman
          ///
          /// Parent Type: `Human`
          public struct AsHuman: StarWarsAPI.InlineFragment {
            @_spi(Unsafe) public let __data: DataDict
            @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

            public typealias RootEntityType = HeroParentTypeDependentFieldQuery.Data.Hero.AsDroid.Friend
            public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Human }
            public static var __selections: [ApolloAPI.Selection] { [
              .field("height", Double?.self, arguments: ["unit": "METER"]),
            ] }
            public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              HeroParentTypeDependentFieldQuery.Data.Hero.AsDroid.Friend.self,
              HeroParentTypeDependentFieldQuery.Data.Hero.AsDroid.Friend.AsHuman.self
            ] }

            /// Height in the preferred unit, default is meters
            public var height: Double? { __data["height"] }
            /// The name of the character
            public var name: String { __data["name"] }

            public init(
              height: Double? = nil,
              name: String
            ) {
              self.init(unsafelyWithData: [
                "__typename": StarWarsAPI.Objects.Human.typename,
                "height": height,
                "name": name,
              ])
            }
          }
        }
      }
    }
  }
}
