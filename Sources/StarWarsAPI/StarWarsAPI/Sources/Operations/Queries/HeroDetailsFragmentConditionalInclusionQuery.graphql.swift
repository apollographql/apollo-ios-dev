// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct HeroDetailsFragmentConditionalInclusionQuery: GraphQLQuery {
  public static let operationName: String = "HeroDetailsFragmentConditionalInclusion"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "48319024203f115072c25e1c19237ab7699fe8e73936689a5e5c2e412ab9f64e",
    definition: .init(
      #"query HeroDetailsFragmentConditionalInclusion($includeDetails: Boolean!) { hero { __typename ...HeroDetails @include(if: $includeDetails) } }"#,
      fragments: [HeroDetails.self]
    ))

  public var includeDetails: Bool

  public init(includeDetails: Bool) {
    self.includeDetails = includeDetails
  }

  public var __variables: Variables? { ["includeDetails": includeDetails] }

  public struct Data: StarWarsAPI.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("hero", Hero?.self),
    ] }

    public var hero: Hero? { __data["hero"] }

    public init(
      hero: Hero? = nil
    ) {
      self.init(_dataDict: DataDict(
        data: [
          "__typename": StarWarsAPI.Objects.Query.typename,
          "hero": hero._fieldData,
        ],
        fulfilledFragments: [
          ObjectIdentifier(HeroDetailsFragmentConditionalInclusionQuery.Data.self)
        ]
      ))
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
        .include(if: "includeDetails", .inlineFragment(IfIncludeDetails.self)),
      ] }

      public var ifIncludeDetails: IfIncludeDetails? { _asInlineFragment() }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var heroDetails: HeroDetails? { _toFragment() }
      }

      public init(
        __typename: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
          ],
          fulfilledFragments: [
            ObjectIdentifier(HeroDetailsFragmentConditionalInclusionQuery.Data.Hero.self)
          ]
        ))
      }

      /// Hero.IfIncludeDetails
      ///
      /// Parent Type: `Character`
      public struct IfIncludeDetails: StarWarsAPI.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = HeroDetailsFragmentConditionalInclusionQuery.Data.Hero
        public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
        public static var __selections: [ApolloAPI.Selection] { [
          .fragment(HeroDetails.self),
        ] }

        /// The name of the character
        public var name: String { __data["name"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var heroDetails: HeroDetails { _toFragment() }
        }

        public init(
          __typename: String,
          name: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "name": name,
            ],
            fulfilledFragments: [
              ObjectIdentifier(HeroDetailsFragmentConditionalInclusionQuery.Data.Hero.self),
              ObjectIdentifier(HeroDetailsFragmentConditionalInclusionQuery.Data.Hero.IfIncludeDetails.self),
              ObjectIdentifier(HeroDetails.self)
            ]
          ))
        }
      }
    }
  }
}
