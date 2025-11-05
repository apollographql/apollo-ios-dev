// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class DogQuery: GraphQLQuery {
  public static let operationName: String = "DogQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query DogQuery { allAnimals { __typename id skinCovering ... on Dog { ...DogFragment houseDetails } } }"#,
      fragments: [DogFragment.self]
    ))

  public init() {}

  public struct Data: AnimalKingdomAPI.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("allAnimals", [AllAnimal].self),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      DogQuery.Data.self
    ] }

    public var allAnimals: [AllAnimal] { __data["allAnimals"] }

    public init(
      allAnimals: [AllAnimal]
    ) {
      self.init(unsafelyWithData: [
        "__typename": AnimalKingdomAPI.Objects.Query.typename,
        "allAnimals": allAnimals._fieldData,
      ])
    }

    /// AllAnimal
    ///
    /// Parent Type: `Animal`
    public struct AllAnimal: AnimalKingdomAPI.SelectionSet, Identifiable {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Animal }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", AnimalKingdomAPI.ID.self),
        .field("skinCovering", GraphQLEnum<AnimalKingdomAPI.SkinCovering>?.self),
        .inlineFragment(AsDog.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DogQuery.Data.AllAnimal.self
      ] }

      public var id: AnimalKingdomAPI.ID { __data["id"] }
      public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }

      public var asDog: AsDog? { _asInlineFragment() }

      public init(
        __typename: String,
        id: AnimalKingdomAPI.ID,
        skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "id": id,
          "skinCovering": skinCovering,
        ])
      }

      /// AllAnimal.AsDog
      ///
      /// Parent Type: `Dog`
      public struct AsDog: AnimalKingdomAPI.InlineFragment, Identifiable {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = DogQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Dog }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("houseDetails", AnimalKingdomAPI.Object?.self),
          .fragment(DogFragment.self),
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DogQuery.Data.AllAnimal.self,
          DogQuery.Data.AllAnimal.AsDog.self,
          DogFragment.self
        ] }

        public var houseDetails: AnimalKingdomAPI.Object? { __data["houseDetails"] }
        public var id: AnimalKingdomAPI.ID { __data["id"] }
        public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }
        public var species: String { __data["species"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var dogFragment: DogFragment { _toFragment() }
        }

        public init(
          houseDetails: AnimalKingdomAPI.Object? = nil,
          id: AnimalKingdomAPI.ID,
          skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
          species: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": AnimalKingdomAPI.Objects.Dog.typename,
            "houseDetails": houseDetails,
            "id": id,
            "skinCovering": skinCovering,
            "species": species,
          ])
        }
      }
    }
  }
}
