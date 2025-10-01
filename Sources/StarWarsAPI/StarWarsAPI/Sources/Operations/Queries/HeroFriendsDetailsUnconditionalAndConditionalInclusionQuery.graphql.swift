// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct HeroFriendsDetailsUnconditionalAndConditionalInclusionQuery: GraphQLQuery {
  public static let operationName: String = "HeroFriendsDetailsUnconditionalAndConditionalInclusion"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "e36c8e5d752afda2a90fe44bcbfeb92de68f0da92b8390d626d3005cbad16dbe",
    definition: .init(
      #"query HeroFriendsDetailsUnconditionalAndConditionalInclusion($includeFriendsDetails: Boolean!) { hero { __typename friends { __typename name } friends @include(if: $includeFriendsDetails) { __typename name ... on Droid { __typename primaryFunction } } } }"#
    ))

  public var includeFriendsDetails: Bool

  public init(includeFriendsDetails: Bool) {
    self.includeFriendsDetails = includeFriendsDetails
  }

  @_spi(Unsafe) public var __variables: Variables? { ["includeFriendsDetails": includeFriendsDetails] }

  public struct Data: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("hero", Hero?.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      HeroFriendsDetailsUnconditionalAndConditionalInclusionQuery.Data.self
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
        .field("friends", [Friend?]?.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HeroFriendsDetailsUnconditionalAndConditionalInclusionQuery.Data.Hero.self
      ] }

      /// The friends of the character, or an empty list if they have none
      public var friends: [Friend?]? { __data["friends"] }

      public init(
        __typename: String,
        friends: [Friend?]? = nil
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "friends": friends._fieldData,
        ])
      }

      /// Hero.Friend
      ///
      /// Parent Type: `Character`
      public struct Friend: StarWarsAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("name", String.self),
          .include(if: "includeFriendsDetails", .inlineFragment(IfIncludeFriendsDetails.self)),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          HeroFriendsDetailsUnconditionalAndConditionalInclusionQuery.Data.Hero.Friend.self
        ] }

        /// The name of the character
        public var name: String { __data["name"] }

        public var ifIncludeFriendsDetails: IfIncludeFriendsDetails? { _asInlineFragment() }

        public init(
          __typename: String,
          name: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
            "name": name,
          ])
        }

        /// Hero.Friend.IfIncludeFriendsDetails
        ///
        /// Parent Type: `Character`
        public struct IfIncludeFriendsDetails: StarWarsAPI.InlineFragment {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = HeroFriendsDetailsUnconditionalAndConditionalInclusionQuery.Data.Hero.Friend
          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
          @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
            .field("name", String.self),
            .inlineFragment(AsDroid.self),
          ] }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            HeroFriendsDetailsUnconditionalAndConditionalInclusionQuery.Data.Hero.Friend.self,
            HeroFriendsDetailsUnconditionalAndConditionalInclusionQuery.Data.Hero.Friend.IfIncludeFriendsDetails.self
          ] }

          /// The name of the character
          public var name: String { __data["name"] }

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

          /// Hero.Friend.IfIncludeFriendsDetails.AsDroid
          ///
          /// Parent Type: `Droid`
          public struct AsDroid: StarWarsAPI.InlineFragment {
            @_spi(Unsafe) public let __data: DataDict
            @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

            public typealias RootEntityType = HeroFriendsDetailsUnconditionalAndConditionalInclusionQuery.Data.Hero.Friend
            @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Droid }
            @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
              .field("primaryFunction", String?.self),
            ] }
            @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              HeroFriendsDetailsUnconditionalAndConditionalInclusionQuery.Data.Hero.Friend.self,
              HeroFriendsDetailsUnconditionalAndConditionalInclusionQuery.Data.Hero.Friend.IfIncludeFriendsDetails.self,
              HeroFriendsDetailsUnconditionalAndConditionalInclusionQuery.Data.Hero.Friend.IfIncludeFriendsDetails.AsDroid.self
            ] }

            /// This droid's primary function
            public var primaryFunction: String? { __data["primaryFunction"] }
            /// The name of the character
            public var name: String { __data["name"] }

            public init(
              primaryFunction: String? = nil,
              name: String
            ) {
              self.init(unsafelyWithData: [
                "__typename": StarWarsAPI.Objects.Droid.typename,
                "primaryFunction": primaryFunction,
                "name": name,
              ])
            }
          }
        }
      }
    }
  }
}
