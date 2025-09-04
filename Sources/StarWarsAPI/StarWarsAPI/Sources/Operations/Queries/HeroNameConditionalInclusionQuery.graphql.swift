// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct HeroNameConditionalInclusionQuery: GraphQLQuery {
  public static let operationName: String = "HeroNameConditionalInclusion"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "dd8e5df9634bb4fb6455e4aaddd2941c5abf785b7d28cda959aba65157e950c6",
    definition: .init(
      #"query HeroNameConditionalInclusion($includeName: Boolean!) { hero { __typename name @include(if: $includeName) } }"#
    ))

  public var includeName: Bool

  public init(includeName: Bool) {
    self.includeName = includeName
  }

  @_spi(Unsafe) public var __variables: Variables? { ["includeName": includeName] }

  public struct Data: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("hero", Hero?.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      HeroNameConditionalInclusionQuery.Data.self
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
        .include(if: "includeName", .field("name", String.self)),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HeroNameConditionalInclusionQuery.Data.Hero.self
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
