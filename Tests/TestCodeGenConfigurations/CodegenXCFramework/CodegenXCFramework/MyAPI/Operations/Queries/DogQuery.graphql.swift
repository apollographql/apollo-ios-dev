// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public extension MyAPI {
  class DogQuery: GraphQLQuery {
    public static let operationName: String = "DogQuery"
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query DogQuery { allAnimals { __typename id skinCovering ... on Dog { ...DogFragment houseDetails } } }"#,
        fragments: [DogFragment.self]
      ))

    public init() {}

    public struct Data: MyAPI.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MyAPI.Objects.Query }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("allAnimals", [AllAnimal].self),
      ] }

      public var allAnimals: [AllAnimal] { __data["allAnimals"] }

      /// AllAnimal
      ///
      /// Parent Type: `Animal`
      public struct AllAnimal: MyAPI.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { MyAPI.Interfaces.Animal }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", MyAPI.ID.self),
          .field("skinCovering", GraphQLEnum<MyAPI.SkinCovering>?.self),
          .inlineFragment(AsDog.self),
        ] }

        public var id: MyAPI.ID { __data["id"] }
        public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }

        public var asDog: AsDog? { _asInlineFragment() }

        /// AllAnimal.AsDog
        ///
        /// Parent Type: `Dog`
        public struct AsDog: MyAPI.InlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = DogQuery.Data.AllAnimal
          public static var __parentType: any ApolloAPI.ParentType { MyAPI.Objects.Dog }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("houseDetails", MyAPI.Object?.self),
            .fragment(DogFragment.self),
          ] }

          public var houseDetails: MyAPI.Object? { __data["houseDetails"] }
          public var id: MyAPI.ID { __data["id"] }
          public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
          public var species: String { __data["species"] }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var dogFragment: DogFragment { _toFragment() }
          }
        }
      }
    }
  }

}