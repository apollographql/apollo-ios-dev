// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public extension MyAPI {
  class FindPetQuery: GraphQLQuery {
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

    public struct Data: MyAPI.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MyAPI.Objects.Query }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("findPet", [FindPet].self, arguments: ["input": .variable("input")]),
      ] }

      public var findPet: [FindPet] { __data["findPet"] }

      /// FindPet
      ///
      /// Parent Type: `Pet`
      public struct FindPet: MyAPI.SelectionSet {
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