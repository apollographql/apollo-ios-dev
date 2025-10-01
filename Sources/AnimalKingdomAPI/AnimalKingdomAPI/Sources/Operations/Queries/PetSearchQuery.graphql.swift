// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct PetSearchQuery: GraphQLQuery {
  public static let operationName: String = "PetSearch"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query PetSearch($filters: PetSearchFilters = { species: ["Dog", "Cat"] size: SMALL measurements: [{ height: 10.5, weight: 5.0 }, { height: 10.5, weight: 5.0 }] }) { pets(filters: $filters) { __typename id humanName } }"#
    ))

  public var filters: GraphQLNullable<PetSearchFilters>

  public init(filters: GraphQLNullable<PetSearchFilters> = .init(
    PetSearchFilters(
      species: [
        "Dog",
        "Cat"
      ],
      size: .init(.small),
      measurements: [
        MeasurementsInput(
          height: 10.5,
          weight: 5.0
        ),
        MeasurementsInput(
          height: 10.5,
          weight: 5.0
        )
      ]
    )
  )) {
    self.filters = filters
  }

  @_spi(Unsafe) public var __variables: Variables? { ["filters": filters] }

  public struct Data: AnimalKingdomAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("pets", [Pet].self, arguments: ["filters": .variable("filters")]),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      PetSearchQuery.Data.self
    ] }

    public var pets: [Pet] { __data["pets"] }

    public init(
      pets: [Pet]
    ) {
      self.init(unsafelyWithData: [
        "__typename": AnimalKingdomAPI.Objects.Query.typename,
        "pets": pets._fieldData,
      ])
    }

    /// Pet
    ///
    /// Parent Type: `Pet`
    public struct Pet: AnimalKingdomAPI.SelectionSet, Identifiable {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Pet }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", AnimalKingdomAPI.ID.self),
        .field("humanName", String?.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        PetSearchQuery.Data.Pet.self
      ] }

      public var id: AnimalKingdomAPI.ID { __data["id"] }
      public var humanName: String? { __data["humanName"] }

      public init(
        __typename: String,
        id: AnimalKingdomAPI.ID,
        humanName: String? = nil
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "id": id,
          "humanName": humanName,
        ])
      }
    }
  }
}
