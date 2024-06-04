// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public extension MyAPI {
  class AllAnimalsQuery: GraphQLQuery {
    public static let operationName: String = "AllAnimalsQuery"
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query AllAnimalsQuery { allAnimals { __typename id height { __typename feet inches } ...HeightInMeters ...WarmBloodedDetails species skinCovering ... on Pet { ...PetDetails ...WarmBloodedDetails ... on Animal { height { __typename relativeSize centimeters } } } ... on Cat { isJellicle } ... on ClassroomPet { ... on Bird { wingspan } } ... on Dog { favoriteToy birthdate } predators { __typename species ... on WarmBlooded { predators { __typename species } ...WarmBloodedDetails laysEggs } } } }"#,
        fragments: [HeightInMeters.self, PetDetails.self, WarmBloodedDetails.self]
      ))

    public init() {}

    public struct Data: MyAPI.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Query }
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

        public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.Animal }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", MyAPI.ID.self),
          .field("height", Height.self),
          .field("species", String.self),
          .field("skinCovering", GraphQLEnum<MyAPI.SkinCovering>?.self),
          .field("predators", [Predator].self),
          .inlineFragment(AsWarmBlooded.self),
          .inlineFragment(AsPet.self),
          .inlineFragment(AsCat.self),
          .inlineFragment(AsClassroomPet.self),
          .inlineFragment(AsDog.self),
          .fragment(HeightInMeters.self),
        ] }

        public var id: MyAPI.ID { __data["id"] }
        public var height: Height { __data["height"] }
        public var species: String { __data["species"] }
        public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
        public var predators: [Predator] { __data["predators"] }

        public var asWarmBlooded: AsWarmBlooded? { _asInlineFragment() }
        public var asPet: AsPet? { _asInlineFragment() }
        public var asCat: AsCat? { _asInlineFragment() }
        public var asClassroomPet: AsClassroomPet? { _asInlineFragment() }
        public var asDog: AsDog? { _asInlineFragment() }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var heightInMeters: HeightInMeters { _toFragment() }
        }

        /// AllAnimal.Height
        ///
        /// Parent Type: `Height`
        public struct Height: MyAPI.SelectionSet {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Height }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("feet", Int.self),
            .field("inches", Int?.self),
          ] }

          public var feet: Int { __data["feet"] }
          public var inches: Int? { __data["inches"] }
          public var meters: Int { __data["meters"] }
        }

        /// AllAnimal.Predator
        ///
        /// Parent Type: `Animal`
        public struct Predator: MyAPI.SelectionSet {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.Animal }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("species", String.self),
            .inlineFragment(AsWarmBlooded.self),
          ] }

          public var species: String { __data["species"] }

          public var asWarmBlooded: AsWarmBlooded? { _asInlineFragment() }

          /// AllAnimal.Predator.AsWarmBlooded
          ///
          /// Parent Type: `WarmBlooded`
          public struct AsWarmBlooded: MyAPI.InlineFragment {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal.Predator
            public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.WarmBlooded }
            public static var __selections: [ApolloAPI.Selection] { [
              .field("predators", [Predator].self),
              .field("laysEggs", Bool.self),
              .fragment(WarmBloodedDetails.self),
            ] }

            public var predators: [Predator] { __data["predators"] }
            public var laysEggs: Bool { __data["laysEggs"] }
            public var species: String { __data["species"] }
            public var bodyTemperature: Int { __data["bodyTemperature"] }
            public var height: Height { __data["height"] }

            public struct Fragments: FragmentContainer {
              public let __data: DataDict
              public init(_dataDict: DataDict) { __data = _dataDict }

              public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
              public var heightInMeters: HeightInMeters { _toFragment() }
            }

            /// AllAnimal.Predator.AsWarmBlooded.Predator
            ///
            /// Parent Type: `Animal`
            public struct Predator: MyAPI.SelectionSet {
              public let __data: DataDict
              public init(_dataDict: DataDict) { __data = _dataDict }

              public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.Animal }
              public static var __selections: [ApolloAPI.Selection] { [
                .field("__typename", String.self),
                .field("species", String.self),
              ] }

              public var species: String { __data["species"] }
            }

            public typealias Height = HeightInMeters.Height
          }
        }

        /// AllAnimal.AsWarmBlooded
        ///
        /// Parent Type: `WarmBlooded`
        public struct AsWarmBlooded: MyAPI.InlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
          public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.WarmBlooded }
          public static var __selections: [ApolloAPI.Selection] { [
            .fragment(WarmBloodedDetails.self),
          ] }

          public var id: MyAPI.ID { __data["id"] }
          public var height: Height { __data["height"] }
          public var species: String { __data["species"] }
          public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
          public var predators: [Predator] { __data["predators"] }
          public var bodyTemperature: Int { __data["bodyTemperature"] }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
            public var heightInMeters: HeightInMeters { _toFragment() }
          }

          /// AllAnimal.AsWarmBlooded.Height
          ///
          /// Parent Type: `Height`
          public struct Height: MyAPI.SelectionSet {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Height }

            public var feet: Int { __data["feet"] }
            public var inches: Int? { __data["inches"] }
            public var meters: Int { __data["meters"] }
          }
        }

        /// AllAnimal.AsPet
        ///
        /// Parent Type: `Pet`
        public struct AsPet: MyAPI.InlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
          public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.Pet }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("height", Height.self),
            .inlineFragment(AsWarmBlooded.self),
            .fragment(PetDetails.self),
          ] }

          public var height: Height { __data["height"] }
          public var id: MyAPI.ID { __data["id"] }
          public var species: String { __data["species"] }
          public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
          public var predators: [Predator] { __data["predators"] }
          public var humanName: String? { __data["humanName"] }
          public var favoriteToy: String { __data["favoriteToy"] }
          public var owner: Owner? { __data["owner"] }

          public var asWarmBlooded: AsWarmBlooded? { _asInlineFragment() }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var petDetails: PetDetails { _toFragment() }
            public var heightInMeters: HeightInMeters { _toFragment() }
          }

          /// AllAnimal.AsPet.Height
          ///
          /// Parent Type: `Height`
          public struct Height: MyAPI.SelectionSet {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Height }
            public static var __selections: [ApolloAPI.Selection] { [
              .field("__typename", String.self),
              .field("relativeSize", GraphQLEnum<MyAPI.RelativeSize>.self),
              .field("centimeters", Double.self),
            ] }

            public var relativeSize: GraphQLEnum<MyAPI.RelativeSize> { __data["relativeSize"] }
            public var centimeters: Double { __data["centimeters"] }
            public var feet: Int { __data["feet"] }
            public var inches: Int? { __data["inches"] }
            public var meters: Int { __data["meters"] }
          }

          public typealias Owner = PetDetails.Owner

          /// AllAnimal.AsPet.AsWarmBlooded
          ///
          /// Parent Type: `WarmBlooded`
          public struct AsWarmBlooded: MyAPI.InlineFragment {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
            public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.WarmBlooded }
            public static var __selections: [ApolloAPI.Selection] { [
              .fragment(WarmBloodedDetails.self),
            ] }

            public var id: MyAPI.ID { __data["id"] }
            public var height: Height { __data["height"] }
            public var species: String { __data["species"] }
            public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
            public var predators: [Predator] { __data["predators"] }
            public var bodyTemperature: Int { __data["bodyTemperature"] }
            public var humanName: String? { __data["humanName"] }
            public var favoriteToy: String { __data["favoriteToy"] }
            public var owner: Owner? { __data["owner"] }

            public struct Fragments: FragmentContainer {
              public let __data: DataDict
              public init(_dataDict: DataDict) { __data = _dataDict }

              public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
              public var heightInMeters: HeightInMeters { _toFragment() }
              public var petDetails: PetDetails { _toFragment() }
            }

            /// AllAnimal.AsPet.AsWarmBlooded.Height
            ///
            /// Parent Type: `Height`
            public struct Height: MyAPI.SelectionSet {
              public let __data: DataDict
              public init(_dataDict: DataDict) { __data = _dataDict }

              public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Height }

              public var feet: Int { __data["feet"] }
              public var inches: Int? { __data["inches"] }
              public var meters: Int { __data["meters"] }
              public var relativeSize: GraphQLEnum<MyAPI.RelativeSize> { __data["relativeSize"] }
              public var centimeters: Double { __data["centimeters"] }
            }

            public typealias Owner = PetDetails.Owner
          }
        }

        /// AllAnimal.AsCat
        ///
        /// Parent Type: `Cat`
        public struct AsCat: MyAPI.InlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
          public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Cat }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("isJellicle", Bool.self),
          ] }

          public var isJellicle: Bool { __data["isJellicle"] }
          public var id: MyAPI.ID { __data["id"] }
          public var height: Height { __data["height"] }
          public var species: String { __data["species"] }
          public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
          public var predators: [Predator] { __data["predators"] }
          public var bodyTemperature: Int { __data["bodyTemperature"] }
          public var humanName: String? { __data["humanName"] }
          public var favoriteToy: String { __data["favoriteToy"] }
          public var owner: Owner? { __data["owner"] }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var heightInMeters: HeightInMeters { _toFragment() }
            public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
            public var petDetails: PetDetails { _toFragment() }
          }

          /// AllAnimal.AsCat.Height
          ///
          /// Parent Type: `Height`
          public struct Height: MyAPI.SelectionSet {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Height }

            public var feet: Int { __data["feet"] }
            public var inches: Int? { __data["inches"] }
            public var meters: Int { __data["meters"] }
            public var relativeSize: GraphQLEnum<MyAPI.RelativeSize> { __data["relativeSize"] }
            public var centimeters: Double { __data["centimeters"] }
          }

          public typealias Owner = PetDetails.Owner
        }

        /// AllAnimal.AsClassroomPet
        ///
        /// Parent Type: `ClassroomPet`
        public struct AsClassroomPet: MyAPI.InlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
          public static var __parentType: ApolloAPI.ParentType { MyAPI.Unions.ClassroomPet }
          public static var __selections: [ApolloAPI.Selection] { [
            .inlineFragment(AsBird.self),
          ] }

          public var id: MyAPI.ID { __data["id"] }
          public var height: Height { __data["height"] }
          public var species: String { __data["species"] }
          public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
          public var predators: [Predator] { __data["predators"] }

          public var asBird: AsBird? { _asInlineFragment() }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var heightInMeters: HeightInMeters { _toFragment() }
          }

          /// AllAnimal.AsClassroomPet.Height
          ///
          /// Parent Type: `Height`
          public struct Height: MyAPI.SelectionSet {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Height }

            public var feet: Int { __data["feet"] }
            public var inches: Int? { __data["inches"] }
            public var meters: Int { __data["meters"] }
          }

          /// AllAnimal.AsClassroomPet.AsBird
          ///
          /// Parent Type: `Bird`
          public struct AsBird: MyAPI.InlineFragment {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
            public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Bird }
            public static var __selections: [ApolloAPI.Selection] { [
              .field("wingspan", Double.self),
            ] }

            public var wingspan: Double { __data["wingspan"] }
            public var id: MyAPI.ID { __data["id"] }
            public var height: Height { __data["height"] }
            public var species: String { __data["species"] }
            public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
            public var predators: [Predator] { __data["predators"] }
            public var bodyTemperature: Int { __data["bodyTemperature"] }
            public var humanName: String? { __data["humanName"] }
            public var favoriteToy: String { __data["favoriteToy"] }
            public var owner: Owner? { __data["owner"] }

            public struct Fragments: FragmentContainer {
              public let __data: DataDict
              public init(_dataDict: DataDict) { __data = _dataDict }

              public var heightInMeters: HeightInMeters { _toFragment() }
              public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
              public var petDetails: PetDetails { _toFragment() }
            }

            /// AllAnimal.AsClassroomPet.AsBird.Height
            ///
            /// Parent Type: `Height`
            public struct Height: MyAPI.SelectionSet {
              public let __data: DataDict
              public init(_dataDict: DataDict) { __data = _dataDict }

              public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Height }

              public var feet: Int { __data["feet"] }
              public var inches: Int? { __data["inches"] }
              public var meters: Int { __data["meters"] }
              public var relativeSize: GraphQLEnum<MyAPI.RelativeSize> { __data["relativeSize"] }
              public var centimeters: Double { __data["centimeters"] }
            }

            public typealias Owner = PetDetails.Owner
          }
        }

        /// AllAnimal.AsDog
        ///
        /// Parent Type: `Dog`
        public struct AsDog: MyAPI.InlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
          public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Dog }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("favoriteToy", String.self),
            .field("birthdate", MyAPI.CustomDate?.self),
          ] }

          public var favoriteToy: String { __data["favoriteToy"] }
          public var birthdate: MyAPI.CustomDate? { __data["birthdate"] }
          public var id: MyAPI.ID { __data["id"] }
          public var height: Height { __data["height"] }
          public var species: String { __data["species"] }
          public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
          public var predators: [Predator] { __data["predators"] }
          public var bodyTemperature: Int { __data["bodyTemperature"] }
          public var humanName: String? { __data["humanName"] }
          public var owner: Owner? { __data["owner"] }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var heightInMeters: HeightInMeters { _toFragment() }
            public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
            public var petDetails: PetDetails { _toFragment() }
          }

          /// AllAnimal.AsDog.Height
          ///
          /// Parent Type: `Height`
          public struct Height: MyAPI.SelectionSet {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Height }

            public var feet: Int { __data["feet"] }
            public var inches: Int? { __data["inches"] }
            public var meters: Int { __data["meters"] }
            public var relativeSize: GraphQLEnum<MyAPI.RelativeSize> { __data["relativeSize"] }
            public var centimeters: Double { __data["centimeters"] }
          }

          public typealias Owner = PetDetails.Owner
        }
      }
    }
  }

}