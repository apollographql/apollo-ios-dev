// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class ClassroomPetsQuery: GraphQLQuery {
  public static let operationName: String = "ClassroomPets"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query ClassroomPets { classroomPets { __typename ...ClassroomPetDetails } }"#,
      fragments: [ClassroomPetDetails.self]
    ))

  public init() {}

  public struct Data: AnimalKingdomAPI.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("classroomPets", [ClassroomPet?]?.self),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      ClassroomPetsQuery.Data.self
    ] }

    public var classroomPets: [ClassroomPet?]? { __data["classroomPets"] }

    public init(
      classroomPets: [ClassroomPet?]? = nil
    ) {
      self.init(unsafelyWithData: [
        "__typename": AnimalKingdomAPI.Objects.Query.typename,
        "classroomPets": classroomPets._fieldData,
      ])
    }

    /// ClassroomPet
    ///
    /// Parent Type: `ClassroomPet`
    public struct ClassroomPet: AnimalKingdomAPI.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Unions.ClassroomPet }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .fragment(ClassroomPetDetails.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ClassroomPetsQuery.Data.ClassroomPet.self
      ] }

      public var asAnimal: AsAnimal? { _asInlineFragment() }
      public var asPet: AsPet? { _asInlineFragment() }
      public var asWarmBlooded: AsWarmBlooded? { _asInlineFragment() }
      public var asCat: AsCat? { _asInlineFragment() }
      public var asBird: AsBird? { _asInlineFragment() }
      public var asPetRock: AsPetRock? { _asInlineFragment() }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var classroomPetDetails: ClassroomPetDetails { _toFragment() }
      }

      public init(
        __typename: String
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
        ])
      }

      /// ClassroomPet.AsAnimal
      ///
      /// Parent Type: `Animal`
      public struct AsAnimal: AnimalKingdomAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Animal }
        public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetDetails.AsAnimal.self
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetsQuery.Data.ClassroomPet.AsAnimal.self,
          ClassroomPetDetails.self,
          ClassroomPetDetails.AsAnimal.self
        ] }

        public var species: String { __data["species"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var classroomPetDetails: ClassroomPetDetails { _toFragment() }
        }

        public init(
          __typename: String,
          species: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
            "species": species,
          ])
        }
      }

      /// ClassroomPet.AsPet
      ///
      /// Parent Type: `Pet`
      public struct AsPet: AnimalKingdomAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Pet }
        public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetDetails.AsPet.self
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetsQuery.Data.ClassroomPet.AsPet.self,
          ClassroomPetDetails.self,
          ClassroomPetDetails.AsPet.self
        ] }

        public var humanName: String? { __data["humanName"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var classroomPetDetails: ClassroomPetDetails { _toFragment() }
        }

        public init(
          __typename: String,
          humanName: String? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
            "humanName": humanName,
          ])
        }
      }

      /// ClassroomPet.AsWarmBlooded
      ///
      /// Parent Type: `WarmBlooded`
      public struct AsWarmBlooded: AnimalKingdomAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.WarmBlooded }
        public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetDetails.AsAnimal.self,
          ClassroomPetDetails.AsWarmBlooded.self
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetsQuery.Data.ClassroomPet.AsWarmBlooded.self,
          ClassroomPetDetails.self,
          ClassroomPetDetails.AsAnimal.self,
          ClassroomPetDetails.AsWarmBlooded.self
        ] }

        public var species: String { __data["species"] }
        public var laysEggs: Bool { __data["laysEggs"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var classroomPetDetails: ClassroomPetDetails { _toFragment() }
        }

        public init(
          __typename: String,
          species: String,
          laysEggs: Bool
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
            "species": species,
            "laysEggs": laysEggs,
          ])
        }
      }

      /// ClassroomPet.AsCat
      ///
      /// Parent Type: `Cat`
      public struct AsCat: AnimalKingdomAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Cat }
        public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetDetails.AsAnimal.self,
          ClassroomPetDetails.AsPet.self,
          ClassroomPetDetails.AsWarmBlooded.self,
          ClassroomPetDetails.AsCat.self
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetsQuery.Data.ClassroomPet.AsCat.self,
          ClassroomPetDetails.self,
          ClassroomPetDetails.AsAnimal.self,
          ClassroomPetDetails.AsPet.self,
          ClassroomPetDetails.AsWarmBlooded.self,
          ClassroomPetDetails.AsCat.self
        ] }

        public var species: String { __data["species"] }
        public var humanName: String? { __data["humanName"] }
        public var laysEggs: Bool { __data["laysEggs"] }
        public var bodyTemperature: Int { __data["bodyTemperature"] }
        public var isJellicle: Bool { __data["isJellicle"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var classroomPetDetails: ClassroomPetDetails { _toFragment() }
        }

        public init(
          species: String,
          humanName: String? = nil,
          laysEggs: Bool,
          bodyTemperature: Int,
          isJellicle: Bool
        ) {
          self.init(unsafelyWithData: [
            "__typename": AnimalKingdomAPI.Objects.Cat.typename,
            "species": species,
            "humanName": humanName,
            "laysEggs": laysEggs,
            "bodyTemperature": bodyTemperature,
            "isJellicle": isJellicle,
          ])
        }
      }

      /// ClassroomPet.AsBird
      ///
      /// Parent Type: `Bird`
      public struct AsBird: AnimalKingdomAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Bird }
        public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetDetails.AsAnimal.self,
          ClassroomPetDetails.AsPet.self,
          ClassroomPetDetails.AsWarmBlooded.self,
          ClassroomPetDetails.AsBird.self
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetsQuery.Data.ClassroomPet.AsBird.self,
          ClassroomPetDetails.self,
          ClassroomPetDetails.AsAnimal.self,
          ClassroomPetDetails.AsPet.self,
          ClassroomPetDetails.AsWarmBlooded.self,
          ClassroomPetDetails.AsBird.self
        ] }

        public var species: String { __data["species"] }
        public var humanName: String? { __data["humanName"] }
        public var laysEggs: Bool { __data["laysEggs"] }
        public var wingspan: Double { __data["wingspan"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var classroomPetDetails: ClassroomPetDetails { _toFragment() }
        }

        public init(
          species: String,
          humanName: String? = nil,
          laysEggs: Bool,
          wingspan: Double
        ) {
          self.init(unsafelyWithData: [
            "__typename": AnimalKingdomAPI.Objects.Bird.typename,
            "species": species,
            "humanName": humanName,
            "laysEggs": laysEggs,
            "wingspan": wingspan,
          ])
        }
      }

      /// ClassroomPet.AsPetRock
      ///
      /// Parent Type: `PetRock`
      public struct AsPetRock: AnimalKingdomAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.PetRock }
        public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetDetails.AsPet.self,
          ClassroomPetDetails.AsPetRock.self
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ClassroomPetsQuery.Data.ClassroomPet.self,
          ClassroomPetsQuery.Data.ClassroomPet.AsPetRock.self,
          ClassroomPetDetails.self,
          ClassroomPetDetails.AsPet.self,
          ClassroomPetDetails.AsPetRock.self
        ] }

        public var humanName: String? { __data["humanName"] }
        public var favoriteToy: String { __data["favoriteToy"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var classroomPetDetails: ClassroomPetDetails { _toFragment() }
        }

        public init(
          humanName: String? = nil,
          favoriteToy: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": AnimalKingdomAPI.Objects.PetRock.typename,
            "humanName": humanName,
            "favoriteToy": favoriteToy,
          ])
        }
      }
    }
  }
}
