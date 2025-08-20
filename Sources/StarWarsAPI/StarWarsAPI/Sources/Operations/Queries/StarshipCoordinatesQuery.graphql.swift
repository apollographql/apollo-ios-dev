// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Unsafe) import ApolloAPI

public struct StarshipCoordinatesQuery: GraphQLQuery {
  public static let operationName: String = "StarshipCoordinates"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "c10b54b8dd9361556f3b12d71f28c859ace043525d8d19541b39eadc47d14b15",
    definition: .init(
      #"query StarshipCoordinates($coordinates: [[Float!]!]) { starshipCoordinates(coordinates: $coordinates) { __typename name coordinates length } }"#
    ))

  public var coordinates: GraphQLNullable<[[Double]]>

  public init(coordinates: GraphQLNullable<[[Double]]>) {
    self.coordinates = coordinates
  }

  public var __variables: Variables? { ["coordinates": coordinates] }

  public struct Data: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("starshipCoordinates", StarshipCoordinates?.self, arguments: ["coordinates": .variable("coordinates")]),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      StarshipCoordinatesQuery.Data.self
    ] }

    public var starshipCoordinates: StarshipCoordinates? { __data["starshipCoordinates"] }

    public init(
      starshipCoordinates: StarshipCoordinates? = nil
    ) {
      self.init(unsafelyWithData: [
        "__typename": StarWarsAPI.Objects.Query.typename,
        "starshipCoordinates": starshipCoordinates._fieldData,
      ])
    }

    /// StarshipCoordinates
    ///
    /// Parent Type: `Starship`
    public struct StarshipCoordinates: StarWarsAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Starship }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
        .field("coordinates", [[Double]]?.self),
        .field("length", Double?.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        StarshipCoordinatesQuery.Data.StarshipCoordinates.self
      ] }

      /// The name of the starship
      public var name: String { __data["name"] }
      public var coordinates: [[Double]]? { __data["coordinates"] }
      /// Length of the starship, along the longest axis
      public var length: Double? { __data["length"] }

      public init(
        name: String,
        coordinates: [[Double]]? = nil,
        length: Double? = nil
      ) {
        self.init(unsafelyWithData: [
          "__typename": StarWarsAPI.Objects.Starship.typename,
          "name": name,
          "coordinates": coordinates,
          "length": length,
        ])
      }
    }
  }
}
