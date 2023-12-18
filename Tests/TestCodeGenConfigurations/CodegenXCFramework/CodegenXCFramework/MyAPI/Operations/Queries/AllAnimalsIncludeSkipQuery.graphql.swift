// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public extension MyAPI {
  class AllAnimalsIncludeSkipQuery: GraphQLQuery {
    public static let operationName: String = "AllAnimalsIncludeSkipQuery"
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query AllAnimalsIncludeSkipQuery($includeSpecies: Boolean!, $skipHeightInMeters: Boolean!, $getCat: Boolean!, $getWarmBlooded: Boolean!, $varA: Boolean!) { allAnimals { __typename height { __typename feet inches } ...HeightInMeters @skip(if: $skipHeightInMeters) ...WarmBloodedDetails @include(if: $getWarmBlooded) species @include(if: $includeSpecies) skinCovering ... on Pet { ...PetDetails ...WarmBloodedDetails ... on Animal { height { __typename relativeSize @include(if: $varA) centimeters @include(if: $varA) } } } ... on Cat @include(if: $getCat) { isJellicle } ... on ClassroomPet { ... on Bird { wingspan } } predators { __typename species @include(if: $includeSpecies) ... on WarmBlooded @include(if: $getWarmBlooded) { species ...WarmBloodedDetails laysEggs @include(if: $getWarmBlooded) } } } }"#,
        fragments: [HeightInMeters.self, PetDetails.self, WarmBloodedDetails.self]
      ))

    public var includeSpecies: Bool
    public var skipHeightInMeters: Bool
    public var getCat: Bool
    public var getWarmBlooded: Bool
    public var varA: Bool

    public init(
      includeSpecies: Bool,
      skipHeightInMeters: Bool,
      getCat: Bool,
      getWarmBlooded: Bool,
      varA: Bool
    ) {
      self.includeSpecies = includeSpecies
      self.skipHeightInMeters = skipHeightInMeters
      self.getCat = getCat
      self.getWarmBlooded = getWarmBlooded
      self.varA = varA
    }

    public var __variables: Variables? { [
      "includeSpecies": includeSpecies,
      "skipHeightInMeters": skipHeightInMeters,
      "getCat": getCat,
      "getWarmBlooded": getWarmBlooded,
      "varA": varA
    ] }

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
          .field("height", Height.self),
          .field("skinCovering", GraphQLEnum<MyAPI.SkinCovering>?.self),
          .field("predators", [Predator].self),
          .inlineFragment(AsPet.self),
          .inlineFragment(AsClassroomPet.self),
          .include(if: "includeSpecies", .field("species", String.self)),
          .include(if: !"skipHeightInMeters", .inlineFragment(IfNotSkipHeightInMeters.self)),
          .include(if: "getWarmBlooded", .inlineFragment(AsWarmBloodedIfGetWarmBlooded.self)),
          .include(if: "getCat", .inlineFragment(AsCatIfGetCat.self)),
        ] }

        public var height: Height { __data["height"] }
        public var species: String? { __data["species"] }
        public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
        public var predators: [Predator] { __data["predators"] }

        public var ifNotSkipHeightInMeters: IfNotSkipHeightInMeters? { _asInlineFragment() }
        public var asWarmBloodedIfGetWarmBlooded: AsWarmBloodedIfGetWarmBlooded? { _asInlineFragment() }
        public var asPet: AsPet? { _asInlineFragment() }
        public var asCatIfGetCat: AsCatIfGetCat? { _asInlineFragment() }
        public var asClassroomPet: AsClassroomPet? { _asInlineFragment() }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var heightInMeters: HeightInMeters? { _toFragment() }
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
            .include(if: "includeSpecies", .field("species", String.self)),
            .include(if: "getWarmBlooded", .inlineFragment(AsWarmBloodedIfGetWarmBlooded.self)),
          ] }

          public var species: String? { __data["species"] }

          public var asWarmBloodedIfGetWarmBlooded: AsWarmBloodedIfGetWarmBlooded? { _asInlineFragment() }

          /// AllAnimal.Predator.AsWarmBloodedIfGetWarmBlooded
          ///
          /// Parent Type: `WarmBlooded`
          public struct AsWarmBloodedIfGetWarmBlooded: MyAPI.InlineFragment {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public typealias RootEntityType = AllAnimalsIncludeSkipQuery.Data.AllAnimal.Predator
            public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.WarmBlooded }
            public static var __selections: [ApolloAPI.Selection] { [
              .field("species", String.self),
              .fragment(WarmBloodedDetails.self),
              .field("laysEggs", Bool.self),
            ] }

            public var species: String { __data["species"] }
            public var laysEggs: Bool { __data["laysEggs"] }
            public var bodyTemperature: Int { __data["bodyTemperature"] }
            public var height: Height { __data["height"] }

            public struct Fragments: FragmentContainer {
              public let __data: DataDict
              public init(_dataDict: DataDict) { __data = _dataDict }

              public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
              public var heightInMeters: HeightInMeters { _toFragment() }
            }

            public typealias Height = HeightInMeters.Height
          }
        }

        /// AllAnimal.IfNotSkipHeightInMeters
        ///
        /// Parent Type: `Animal`
        public struct IfNotSkipHeightInMeters: MyAPI.InlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsIncludeSkipQuery.Data.AllAnimal
          public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.Animal }
          public static var __selections: [ApolloAPI.Selection] { [
            .fragment(HeightInMeters.self),
          ] }

          public var height: Height { __data["height"] }
          public var species: String? { __data["species"] }
          public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
          public var predators: [Predator] { __data["predators"] }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var heightInMeters: HeightInMeters { _toFragment() }
          }

          /// AllAnimal.IfNotSkipHeightInMeters.Height
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

        /// AllAnimal.AsWarmBloodedIfGetWarmBlooded
        ///
        /// Parent Type: `WarmBlooded`
        public struct AsWarmBloodedIfGetWarmBlooded: MyAPI.InlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsIncludeSkipQuery.Data.AllAnimal
          public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.WarmBlooded }
          public static var __selections: [ApolloAPI.Selection] { [
            .fragment(WarmBloodedDetails.self),
          ] }

          public var height: Height { __data["height"] }
          public var species: String? { __data["species"] }
          public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
          public var predators: [Predator] { __data["predators"] }
          public var bodyTemperature: Int { __data["bodyTemperature"] }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
            public var heightInMeters: HeightInMeters { _toFragment() }
          }

          /// AllAnimal.AsWarmBloodedIfGetWarmBlooded.Height
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

          public typealias RootEntityType = AllAnimalsIncludeSkipQuery.Data.AllAnimal
          public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.Pet }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("height", Height.self),
            .inlineFragment(AsWarmBlooded.self),
            .fragment(PetDetails.self),
          ] }

          public var height: Height { __data["height"] }
          public var species: String? { __data["species"] }
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
            public var heightInMeters: HeightInMeters? { _toFragment() }
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
              .include(if: "varA", [
                .field("relativeSize", GraphQLEnum<MyAPI.RelativeSize>.self),
                .field("centimeters", Double.self),
              ]),
            ] }

            public var relativeSize: GraphQLEnum<MyAPI.RelativeSize>? { __data["relativeSize"] }
            public var centimeters: Double? { __data["centimeters"] }
            public var feet: Int { __data["feet"] }
            public var inches: Int? { __data["inches"] }
          }



          public typealias Owner = PetDetails.Owner

          /// AllAnimal.AsPet.AsWarmBlooded
          ///
          /// Parent Type: `WarmBlooded`
          public struct AsWarmBlooded: MyAPI.InlineFragment {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public typealias RootEntityType = AllAnimalsIncludeSkipQuery.Data.AllAnimal
            public static var __parentType: ApolloAPI.ParentType { MyAPI.Interfaces.WarmBlooded }
            public static var __selections: [ApolloAPI.Selection] { [
              .fragment(WarmBloodedDetails.self),
            ] }

            public var height: Height { __data["height"] }
            public var species: String? { __data["species"] }
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
              public var relativeSize: GraphQLEnum<MyAPI.RelativeSize>? { __data["relativeSize"] }
              public var centimeters: Double? { __data["centimeters"] }
              public var meters: Int { __data["meters"] }
            }



            public typealias Owner = PetDetails.Owner
          }
        }

        /// AllAnimal.AsCatIfGetCat
        ///
        /// Parent Type: `Cat`
        public struct AsCatIfGetCat: MyAPI.InlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsIncludeSkipQuery.Data.AllAnimal
          public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Cat }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("isJellicle", Bool.self),
          ] }

          public var isJellicle: Bool { __data["isJellicle"] }
          public var height: Height { __data["height"] }
          public var species: String? { __data["species"] }
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
            public var petDetails: PetDetails { _toFragment() }
            public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
          }

          /// AllAnimal.AsCatIfGetCat.Height
          ///
          /// Parent Type: `Height`
          public struct Height: MyAPI.SelectionSet {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Height }

            public var feet: Int { __data["feet"] }
            public var inches: Int? { __data["inches"] }
            public var relativeSize: GraphQLEnum<MyAPI.RelativeSize>? { __data["relativeSize"] }
            public var centimeters: Double? { __data["centimeters"] }
            public var meters: Int { __data["meters"] }
          }



          public typealias Owner = PetDetails.Owner
        }

        /// AllAnimal.AsClassroomPet
        ///
        /// Parent Type: `ClassroomPet`
        public struct AsClassroomPet: MyAPI.InlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsIncludeSkipQuery.Data.AllAnimal
          public static var __parentType: ApolloAPI.ParentType { MyAPI.Unions.ClassroomPet }
          public static var __selections: [ApolloAPI.Selection] { [
            .inlineFragment(AsBird.self),
          ] }

          public var height: Height { __data["height"] }
          public var species: String? { __data["species"] }
          public var skinCovering: GraphQLEnum<MyAPI.SkinCovering>? { __data["skinCovering"] }
          public var predators: [Predator] { __data["predators"] }

          public var asBird: AsBird? { _asInlineFragment() }

          public struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public var heightInMeters: HeightInMeters? { _toFragment() }
          }

          /// AllAnimal.AsClassroomPet.AsBird
          ///
          /// Parent Type: `Bird`
          public struct AsBird: MyAPI.InlineFragment {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public typealias RootEntityType = AllAnimalsIncludeSkipQuery.Data.AllAnimal
            public static var __parentType: ApolloAPI.ParentType { MyAPI.Objects.Bird }
            public static var __selections: [ApolloAPI.Selection] { [
              .field("wingspan", Double.self),
            ] }

            public var wingspan: Double { __data["wingspan"] }
            public var height: Height { __data["height"] }
            public var species: String? { __data["species"] }
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
              public var petDetails: PetDetails { _toFragment() }
              public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
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
              public var relativeSize: GraphQLEnum<MyAPI.RelativeSize>? { __data["relativeSize"] }
              public var centimeters: Double? { __data["centimeters"] }
              public var meters: Int { __data["meters"] }
            }



            public typealias Owner = PetDetails.Owner
          }
        }
      }
    }
  }

}