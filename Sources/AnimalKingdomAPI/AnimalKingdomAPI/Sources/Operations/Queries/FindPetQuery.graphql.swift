// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct FindPetQuery: GraphQLQuery {
  public static let operationName: String = "FindPet"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query FindPet($input: PetSearchInput!) { findPet(input: $input) { __typename id humanName } }"#
    ))

  public var input: PetSearchInput

  public init(input: PetSearchInput) {
    self.input = input
  }

  @_spi(Unsafe) public var __variables: Variables? { ["input": input] }

  public struct Data: AnimalKingdomAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("findPet", [FindPet].self, arguments: ["input": .variable("input")]),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      FindPetQuery.Data.self
    ] }

    public var findPet: [FindPet] { __data["findPet"] }

    public init(
      findPet: [FindPet]
    ) {
      self.init(unsafelyWithData: [
        "__typename": AnimalKingdomAPI.Objects.Query.typename,
        "findPet": findPet._fieldData,
      ])
    }

    /// FindPet
    ///
    /// Parent Type: `Pet`
    public struct FindPet: AnimalKingdomAPI.SelectionSet, Identifiable {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Pet }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", AnimalKingdomAPI.ID.self),
        .field("humanName", String?.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        FindPetQuery.Data.FindPet.self
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
