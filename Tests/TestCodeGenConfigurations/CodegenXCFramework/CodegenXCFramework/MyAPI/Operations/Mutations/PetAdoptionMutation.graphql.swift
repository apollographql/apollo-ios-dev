// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public extension MyAPI {
  class PetAdoptionMutation: GraphQLMutation {
    public static let operationName: String = "PetAdoptionMutation"
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation PetAdoptionMutation($input: PetAdoptionInput!) { adoptPet(input: $input) { __typename id humanName } }"#
      ))

    public var input: PetAdoptionInput

    public init(input: PetAdoptionInput) {
      self.input = input
    }

    public var __variables: Variables? { ["input": input] }

    public struct Data: MyAPI.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MyAPI.Objects.Mutation }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("adoptPet", AdoptPet.self, arguments: ["input": .variable("input")]),
      ] }

      public var adoptPet: AdoptPet { __data["adoptPet"] }

      /// AdoptPet
      ///
      /// Parent Type: `Pet`
      public struct AdoptPet: MyAPI.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { MyAPI.Interfaces.Pet }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", MyAPI.ID.self),
          .field("humanName", String?.self),
        ] }

        public var id: MyAPI.ID { __data["id"] }
        public var humanName: String? { __data["humanName"] }
      }
    }
  }

}