// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct SameHeroTwiceQuery: GraphQLQuery {
  public static let operationName: String = "SameHeroTwice"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "3d960acb3caffc4e42701ccada8535b1a5640f0cc46966b6a12830c755ff46d8",
    definition: .init(
      #"query SameHeroTwice { hero { __typename name } r2: hero { __typename appearsIn } }"#
    ))

  public init() {}

  public struct Data: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("hero", Hero?.self),
      .field("hero", alias: "r2", R2?.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      SameHeroTwiceQuery.Data.self
    ] }

    public var hero: Hero? { __data["hero"] }
    public var r2: R2? { __data["r2"] }

    public init(
      hero: Hero? = nil,
      r2: R2? = nil
    ) {
      self.init(unsafelyWithData: [
        "__typename": StarWarsAPI.Objects.Query.typename,
        "hero": hero._fieldData,
        "r2": r2._fieldData,
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
        .field("name", String.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SameHeroTwiceQuery.Data.Hero.self
      ] }

      /// The name of the character
      public var name: String { __data["name"] }

      public init(
        __typename: String,
        name: String
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "name": name,
        ])
      }
    }

    /// R2
    ///
    /// Parent Type: `Character`
    public struct R2: StarWarsAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("appearsIn", [GraphQLEnum<StarWarsAPI.Episode>?].self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SameHeroTwiceQuery.Data.R2.self
      ] }

      /// The movies this character appears in
      public var appearsIn: [GraphQLEnum<StarWarsAPI.Episode>?] { __data["appearsIn"] }

      public init(
        __typename: String,
        appearsIn: [GraphQLEnum<StarWarsAPI.Episode>?]
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "appearsIn": appearsIn,
        ])
      }
    }
  }
}
