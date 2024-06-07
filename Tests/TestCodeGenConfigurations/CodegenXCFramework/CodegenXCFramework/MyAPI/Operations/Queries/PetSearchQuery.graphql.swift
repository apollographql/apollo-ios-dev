// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public extension MyAPI {
  class PetSearchQuery: GraphQLQuery {
    public static let operationName: String = "PetSearch"
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query PetSearch($filters: PetSearchFilters = { species: ["Dog", "Cat"] size: SMALL measurements: { height: 10.5, weight: 5.0 } }) { pets(filters: $filters) { __typename id humanName } }"#
      ))

    public var filters: GraphQLNullable<PetSearchFilters>

    public init(filters: GraphQLNullable<PetSearchFilters> = .init(
      PetSearchFilters(
        species: ["Dog", "Cat"],
        size: .init(.small),
        measurements: .init(
          MeasurementsInput(
            height: 10.5,
            weight: 5.0
          )
        )
      )
    )) {
      self.filters = filters
    }

    public var __variables: Variables? { ["filters": filters] }

    public struct Data: MyAPI.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MyAPI.Objects.Query }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("pets", [Pet].self, arguments: ["filters": .variable("filters")]),
      ] }

      public var pets: [Pet] { __data["pets"] }

      /// Pet
      ///
      /// Parent Type: `Pet`
      public struct Pet: MyAPI.SelectionSet {
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