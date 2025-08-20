// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Unsafe) import ApolloAPI

public struct HeroDetailsInlineConditionalInclusionQuery: GraphQLQuery {
  public static let operationName: String = "HeroDetailsInlineConditionalInclusion"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "e251576f8c1cfcd442f44d2fbe5fd4b425a36ddd41fb4b6c1019c501ac6ac5bc",
    definition: .init(
      #"query HeroDetailsInlineConditionalInclusion($includeDetails: Boolean!) { hero { __typename ... @include(if: $includeDetails) { __typename name appearsIn } } }"#
    ))

  public var includeDetails: Bool

  public init(includeDetails: Bool) {
    self.includeDetails = includeDetails
  }

  public var __variables: Variables? { ["includeDetails": includeDetails] }

  public struct Data: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("hero", Hero?.self),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      HeroDetailsInlineConditionalInclusionQuery.Data.self
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
        .include(if: "includeDetails", .inlineFragment(IfIncludeDetails.self)),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HeroDetailsInlineConditionalInclusionQuery.Data.Hero.self
      ] }

      public var ifIncludeDetails: IfIncludeDetails? { _asInlineFragment() }

      public init(
        __typename: String
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
        ])
      }

      /// Hero.IfIncludeDetails
      ///
      /// Parent Type: `Character`
      public struct IfIncludeDetails: StarWarsAPI.InlineFragment {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = HeroDetailsInlineConditionalInclusionQuery.Data.Hero
        public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("name", String.self),
          .field("appearsIn", [GraphQLEnum<StarWarsAPI.Episode>?].self),
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          HeroDetailsInlineConditionalInclusionQuery.Data.Hero.self,
          HeroDetailsInlineConditionalInclusionQuery.Data.Hero.IfIncludeDetails.self
        ] }

        /// The name of the character
        public var name: String { __data["name"] }
        /// The movies this character appears in
        public var appearsIn: [GraphQLEnum<StarWarsAPI.Episode>?] { __data["appearsIn"] }

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
}
