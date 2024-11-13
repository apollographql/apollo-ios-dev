// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class FindPetQuery: GraphQLQuery {
  public static let operationName: String = "FindPet"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query FindPet($input: PetSearchInput!) { findPet(input: $input) { __typename id humanName } }"#
    ))

  public var input: PetSearchInput

  public init(input: PetSearchInput) {
    self.input = input
  }

  public var __variables: Variables? { ["input": input] }

  public struct Data: AnimalKingdomAPI.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("findPet", [FindPet].self, arguments: ["input": .variable("input")]),
    ] }

    public var findPet: [FindPet] { __data["findPet"] }

    public init(
      findPet: [FindPet]
    ) {
      self.init(_dataDict: DataDict(
        data: [
          "__typename": AnimalKingdomAPI.Objects.Query.typename,
          "findPet": findPet._fieldData,
        ],
        fulfilledFragments: [
          ObjectIdentifier(FindPetQuery.Data.self)
        ]
      ))
    }

    /// FindPet
    ///
    /// Parent Type: `Pet`
    public struct FindPet: AnimalKingdomAPI.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Pet }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", AnimalKingdomAPI.ID.self),
        .field("humanName", String?.self),
      ] }

      public var id: AnimalKingdomAPI.ID { __data["id"] }
      public var humanName: String? { __data["humanName"] }

      public init(
        __typename: String,
        id: AnimalKingdomAPI.ID,
        humanName: String? = nil
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "id": id,
            "humanName": humanName,
          ],
          fulfilledFragments: [
            ObjectIdentifier(FindPetQuery.Data.FindPet.self)
          ]
        ))
      }
    }
  }
}
