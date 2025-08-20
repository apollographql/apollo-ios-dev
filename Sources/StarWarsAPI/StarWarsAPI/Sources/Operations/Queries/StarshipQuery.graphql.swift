// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Unsafe) import ApolloAPI

public struct StarshipQuery: GraphQLQuery {
  public static let operationName: String = "Starship"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "e42a9be2ae0f222985e3eacf8d8d513002954d5031dcf544bbb0d27b1089fc58",
    definition: .init(
      #"query Starship { starship(id: 3000) { __typename name coordinates } }"#
    ))

  public init() {}

  public struct Data: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("starship", Starship?.self, arguments: ["id": 3000]),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      StarshipQuery.Data.self
    ] }

    public var starship: Starship? { __data["starship"] }

    public init(
      starship: Starship? = nil
    ) {
      self.init(unsafelyWithData: [
        "__typename": StarWarsAPI.Objects.Query.typename,
        "starship": starship._fieldData,
      ])
    }

    /// Starship
    ///
    /// Parent Type: `Starship`
    public struct Starship: StarWarsAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Starship }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
        .field("coordinates", [[Double]]?.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        StarshipQuery.Data.Starship.self
      ] }

      /// The name of the starship
      public var name: String { __data["name"] }
      public var coordinates: [[Double]]? { __data["coordinates"] }

      public init(
        name: String,
        coordinates: [[Double]]? = nil
      ) {
        self.init(unsafelyWithData: [
          "__typename": StarWarsAPI.Objects.Starship.typename,
          "name": name,
          "coordinates": coordinates,
        ])
      }
    }
  }
}
