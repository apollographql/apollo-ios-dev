// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct HeroNameConditionalExclusionQuery: GraphQLQuery {
  public static let operationName: String = "HeroNameConditionalExclusion"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "b6d6f1d10cde449adbf2891d489159006188e63d4dea4edb9a23eddcbe0bd361",
    definition: .init(
      #"query HeroNameConditionalExclusion($skipName: Boolean!) { hero { __typename name @skip(if: $skipName) } }"#
    ))

  public var skipName: Bool

  public init(skipName: Bool) {
    self.skipName = skipName
  }

  @_spi(Unsafe) public var __variables: Variables? { ["skipName": skipName] }

  public struct Data: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("hero", Hero?.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      HeroNameConditionalExclusionQuery.Data.self
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
        .include(if: !"skipName", .field("name", String.self)),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HeroNameConditionalExclusionQuery.Data.Hero.self
      ] }

      /// The name of the character
      public var name: String? { __data["name"] }

      public init(
        __typename: String,
        name: String? = nil
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "name": name,
        ])
      }
    }
  }
}
