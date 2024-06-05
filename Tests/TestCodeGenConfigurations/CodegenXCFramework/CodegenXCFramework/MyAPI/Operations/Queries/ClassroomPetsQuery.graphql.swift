// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public extension MyAPI {
  class ClassroomPetsQuery: GraphQLQuery {
    public static let operationName: String = "ClassroomPets"
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query ClassroomPets { classroomPets { __typename ...ClassroomPetDetails } }"#,
        fragments: [ClassroomPetDetails.self]
      ))

    public init() {}

    public struct Data: MyAPI.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MyAPI.Objects.Query }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("classroomPets", [ClassroomPet?]?.self),
      ] }

      public var classroomPets: [ClassroomPet?]? { __data["classroomPets"] }

      /// ClassroomPet
      ///
      /// Parent Type: `ClassroomPet`
      public struct ClassroomPet: MyAPI.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { MyAPI.Unions.ClassroomPet }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(ClassroomPetDetails.self),
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

        /// ClassroomPet.AsAnimal
        ///
        /// Parent Type: `Animal`
        public struct AsAnimal: MyAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
          public static var __parentType: any ApolloAPI.ParentType { MyAPI.Interfaces.Animal }
          public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
            ClassroomPetsQuery.Data.ClassroomPet.self,
            ClassroomPetDetails.AsAnimal.self
          ] }

          public var species: String { __data["species"] }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var classroomPetDetails: ClassroomPetDetails { _toFragment() }
          }
        }

        /// ClassroomPet.AsPet
        ///
        /// Parent Type: `Pet`
        public struct AsPet: MyAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
          public static var __parentType: any ApolloAPI.ParentType { MyAPI.Interfaces.Pet }
          public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
            ClassroomPetsQuery.Data.ClassroomPet.self,
            ClassroomPetDetails.AsPet.self
          ] }

          public var humanName: String? { __data["humanName"] }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var classroomPetDetails: ClassroomPetDetails { _toFragment() }
          }
        }

        /// ClassroomPet.AsWarmBlooded
        ///
        /// Parent Type: `WarmBlooded`
        public struct AsWarmBlooded: MyAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
          public static var __parentType: any ApolloAPI.ParentType { MyAPI.Interfaces.WarmBlooded }
          public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
            ClassroomPetsQuery.Data.ClassroomPet.self,
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
        }

        /// ClassroomPet.AsCat
        ///
        /// Parent Type: `Cat`
        public struct AsCat: MyAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
          public static var __parentType: any ApolloAPI.ParentType { MyAPI.Objects.Cat }
          public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
            ClassroomPetsQuery.Data.ClassroomPet.self,
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
        }

        /// ClassroomPet.AsBird
        ///
        /// Parent Type: `Bird`
        public struct AsBird: MyAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
          public static var __parentType: any ApolloAPI.ParentType { MyAPI.Objects.Bird }
          public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
            ClassroomPetsQuery.Data.ClassroomPet.self,
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
        }

        /// ClassroomPet.AsPetRock
        ///
        /// Parent Type: `PetRock`
        public struct AsPetRock: MyAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = ClassroomPetsQuery.Data.ClassroomPet
          public static var __parentType: any ApolloAPI.ParentType { MyAPI.Objects.PetRock }
          public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
            ClassroomPetsQuery.Data.ClassroomPet.self,
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
        }
      }
    }
  }

}