// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct HeroNameConditionalBothSeparateQuery: GraphQLQuery {
  public static let operationName: String = "HeroNameConditionalBothSeparate"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "60741c6fca15865a9af75a269ed05871e681f48ac48edfac2a77d953d217d03c",
    definition: .init(
      #"query HeroNameConditionalBothSeparate($skipName: Boolean!, $includeName: Boolean!) { hero { __typename name @skip(if: $skipName) name @include(if: $includeName) } }"#
    ))

  public var skipName: Bool
  public var includeName: Bool

  public init(
    skipName: Bool,
    includeName: Bool
  ) {
    self.skipName = skipName
    self.includeName = includeName
  }

  @_spi(Unsafe) public var __variables: Variables? { [
    "skipName": skipName,
    "includeName": includeName
  ] }

  public struct Data: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("hero", Hero?.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      HeroNameConditionalBothSeparateQuery.Data.self
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
        .include(if: !"skipName" || "includeName", .field("name", String.self)),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HeroNameConditionalBothSeparateQuery.Data.Hero.self
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
