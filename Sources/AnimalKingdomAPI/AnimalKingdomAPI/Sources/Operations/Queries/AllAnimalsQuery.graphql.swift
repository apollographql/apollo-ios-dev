// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct AllAnimalsQuery: GraphQLQuery {
  public static let operationName: String = "AllAnimalsQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query AllAnimalsQuery { allAnimals { __typename id height { __typename feet inches } ...HeightInMeters ...WarmBloodedDetails species skinCovering ... on Pet { ...PetDetails ...WarmBloodedDetails ... on Animal { height { __typename relativeSize centimeters } } } ... on Cat { isJellicle } ... on ClassroomPet { ... on Bird { wingspan } } ... on Dog { favoriteToy birthdate } predators { __typename species ... on WarmBlooded { predators { __typename species } ...WarmBloodedDetails laysEggs } } } }"#,
      fragments: [HeightInMeters.self, PetDetails.self, WarmBloodedDetails.self]
    ))

  public init() {}

  public struct Data: AnimalKingdomAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("allAnimals", [AllAnimal].self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      AllAnimalsQuery.Data.self
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
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Animal }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", AnimalKingdomAPI.ID.self),
        .field("height", Height.self),
        .field("species", String.self),
        .field("skinCovering", GraphQLEnum<AnimalKingdomAPI.SkinCovering>?.self),
        .field("predators", [Predator].self),
        .inlineFragment(AsWarmBlooded.self),
        .inlineFragment(AsPet.self),
        .inlineFragment(AsCat.self),
        .inlineFragment(AsClassroomPet.self),
        .inlineFragment(AsDog.self),
        .fragment(HeightInMeters.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        AllAnimalsQuery.Data.AllAnimal.self
      ] }

      public var id: AnimalKingdomAPI.ID { __data["id"] }
      public var height: Height { __data["height"] }
      public var species: String { __data["species"] }
      public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }
      public var predators: [Predator] { __data["predators"] }

      public var asWarmBlooded: AsWarmBlooded? { _asInlineFragment() }
      public var asPet: AsPet? { _asInlineFragment() }
      public var asCat: AsCat? { _asInlineFragment() }
      public var asClassroomPet: AsClassroomPet? { _asInlineFragment() }
      public var asDog: AsDog? { _asInlineFragment() }

      public struct Fragments: FragmentContainer {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public var heightInMeters: HeightInMeters { _toFragment() }
      }

      public init(
        __typename: String,
        id: AnimalKingdomAPI.ID,
        height: Height,
        species: String,
        skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
        predators: [Predator]
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "id": id,
          "height": height._fieldData,
          "species": species,
          "skinCovering": skinCovering,
          "predators": predators._fieldData,
        ])
      }

      /// AllAnimal.Height
      ///
      /// Parent Type: `Height`
      public struct Height: AnimalKingdomAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("feet", Int.self),
          .field("inches", Int?.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          AllAnimalsQuery.Data.AllAnimal.Height.self,
          HeightInMeters.Height.self
        ] }

        public var feet: Int { __data["feet"] }
        public var inches: Int? { __data["inches"] }
        public var meters: Int { __data["meters"] }

        public init(
          feet: Int,
          inches: Int? = nil,
          meters: Int
        ) {
          self.init(unsafelyWithData: [
            "__typename": AnimalKingdomAPI.Objects.Height.typename,
            "feet": feet,
            "inches": inches,
            "meters": meters,
          ])
        }
      }

      /// AllAnimal.Predator
      ///
      /// Parent Type: `Animal`
      public struct Predator: AnimalKingdomAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Animal }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("species", String.self),
          .inlineFragment(AsWarmBlooded.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          AllAnimalsQuery.Data.AllAnimal.Predator.self
        ] }

        public var species: String { __data["species"] }

        public var asWarmBlooded: AsWarmBlooded? { _asInlineFragment() }

        public init(
          __typename: String,
          species: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
            "species": species,
          ])
        }

        /// AllAnimal.Predator.AsWarmBlooded
        ///
        /// Parent Type: `WarmBlooded`
        public struct AsWarmBlooded: AnimalKingdomAPI.InlineFragment {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal.Predator
          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.WarmBlooded }
          @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
            .field("predators", [Predator].self),
            .field("laysEggs", Bool.self),
            .fragment(WarmBloodedDetails.self),
          ] }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            AllAnimalsQuery.Data.AllAnimal.Predator.self,
            AllAnimalsQuery.Data.AllAnimal.Predator.AsWarmBlooded.self,
            WarmBloodedDetails.self,
            HeightInMeters.self
          ] }

          public var predators: [Predator] { __data["predators"] }
          public var laysEggs: Bool { __data["laysEggs"] }
          public var species: String { __data["species"] }
          public var bodyTemperature: Int { __data["bodyTemperature"] }
          public var height: Height { __data["height"] }

          public struct Fragments: FragmentContainer {
            @_spi(Unsafe) public let __data: DataDict
            @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

            public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
            public var heightInMeters: HeightInMeters { _toFragment() }
          }

          public init(
            __typename: String,
            predators: [Predator],
            laysEggs: Bool,
            species: String,
            bodyTemperature: Int,
            height: Height
          ) {
            self.init(unsafelyWithData: [
              "__typename": __typename,
              "predators": predators._fieldData,
              "laysEggs": laysEggs,
              "species": species,
              "bodyTemperature": bodyTemperature,
              "height": height._fieldData,
            ])
          }

          /// AllAnimal.Predator.AsWarmBlooded.Predator
          ///
          /// Parent Type: `Animal`
          public struct Predator: AnimalKingdomAPI.SelectionSet {
            @_spi(Unsafe) public let __data: DataDict
            @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

            @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Animal }
            @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
              .field("__typename", String.self),
              .field("species", String.self),
            ] }
            @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              AllAnimalsQuery.Data.AllAnimal.Predator.AsWarmBlooded.Predator.self
            ] }

            public var species: String { __data["species"] }

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

          public typealias Height = HeightInMeters.Height
        }
      }

      /// AllAnimal.AsWarmBlooded
      ///
      /// Parent Type: `WarmBlooded`
      public struct AsWarmBlooded: AnimalKingdomAPI.InlineFragment, Identifiable {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.WarmBlooded }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .fragment(WarmBloodedDetails.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          AllAnimalsQuery.Data.AllAnimal.self,
          AllAnimalsQuery.Data.AllAnimal.AsWarmBlooded.self,
          WarmBloodedDetails.self,
          HeightInMeters.self
        ] }

        public var id: AnimalKingdomAPI.ID { __data["id"] }
        public var height: Height { __data["height"] }
        public var species: String { __data["species"] }
        public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }
        public var predators: [Predator] { __data["predators"] }
        public var bodyTemperature: Int { __data["bodyTemperature"] }

        public struct Fragments: FragmentContainer {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
          public var heightInMeters: HeightInMeters { _toFragment() }
        }

        public init(
          __typename: String,
          id: AnimalKingdomAPI.ID,
          height: Height,
          species: String,
          skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
          predators: [Predator],
          bodyTemperature: Int
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
            "id": id,
            "height": height._fieldData,
            "species": species,
            "skinCovering": skinCovering,
            "predators": predators._fieldData,
            "bodyTemperature": bodyTemperature,
          ])
        }

        /// AllAnimal.AsWarmBlooded.Height
        ///
        /// Parent Type: `Height`
        public struct Height: AnimalKingdomAPI.SelectionSet {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            AllAnimalsQuery.Data.AllAnimal.AsWarmBlooded.Height.self,
            AllAnimalsQuery.Data.AllAnimal.Height.self,
            HeightInMeters.Height.self
          ] }

          public var feet: Int { __data["feet"] }
          public var inches: Int? { __data["inches"] }
          public var meters: Int { __data["meters"] }

          public init(
            feet: Int,
            inches: Int? = nil,
            meters: Int
          ) {
            self.init(unsafelyWithData: [
              "__typename": AnimalKingdomAPI.Objects.Height.typename,
              "feet": feet,
              "inches": inches,
              "meters": meters,
            ])
          }
        }
      }

      /// AllAnimal.AsPet
      ///
      /// Parent Type: `Pet`
      public struct AsPet: AnimalKingdomAPI.InlineFragment, Identifiable {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Pet }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("height", Height.self),
          .inlineFragment(AsWarmBlooded.self),
          .fragment(PetDetails.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          AllAnimalsQuery.Data.AllAnimal.self,
          AllAnimalsQuery.Data.AllAnimal.AsPet.self,
          PetDetails.self
        ] }

        public var height: Height { __data["height"] }
        public var id: AnimalKingdomAPI.ID { __data["id"] }
        public var species: String { __data["species"] }
        public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }
        public var predators: [Predator] { __data["predators"] }
        public var humanName: String? { __data["humanName"] }
        public var favoriteToy: String { __data["favoriteToy"] }
        public var owner: Owner? { __data["owner"] }

        public var asWarmBlooded: AsWarmBlooded? { _asInlineFragment() }

        public struct Fragments: FragmentContainer {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public var petDetails: PetDetails { _toFragment() }
          public var heightInMeters: HeightInMeters { _toFragment() }
        }

        public init(
          __typename: String,
          height: Height,
          id: AnimalKingdomAPI.ID,
          species: String,
          skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
          predators: [Predator],
          humanName: String? = nil,
          favoriteToy: String,
          owner: Owner? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
            "height": height._fieldData,
            "id": id,
            "species": species,
            "skinCovering": skinCovering,
            "predators": predators._fieldData,
            "humanName": humanName,
            "favoriteToy": favoriteToy,
            "owner": owner._fieldData,
          ])
        }

        /// AllAnimal.AsPet.Height
        ///
        /// Parent Type: `Height`
        public struct Height: AnimalKingdomAPI.SelectionSet {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
          @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("relativeSize", GraphQLEnum<AnimalKingdomAPI.RelativeSize>.self),
            .field("centimeters", Double.self),
          ] }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            AllAnimalsQuery.Data.AllAnimal.AsPet.Height.self,
            AllAnimalsQuery.Data.AllAnimal.Height.self,
            HeightInMeters.Height.self
          ] }

          public var relativeSize: GraphQLEnum<AnimalKingdomAPI.RelativeSize> { __data["relativeSize"] }
          public var centimeters: Double { __data["centimeters"] }
          public var feet: Int { __data["feet"] }
          public var inches: Int? { __data["inches"] }
          public var meters: Int { __data["meters"] }

          public init(
            relativeSize: GraphQLEnum<AnimalKingdomAPI.RelativeSize>,
            centimeters: Double,
            feet: Int,
            inches: Int? = nil,
            meters: Int
          ) {
            self.init(unsafelyWithData: [
              "__typename": AnimalKingdomAPI.Objects.Height.typename,
              "relativeSize": relativeSize,
              "centimeters": centimeters,
              "feet": feet,
              "inches": inches,
              "meters": meters,
            ])
          }
        }

        public typealias Owner = PetDetails.Owner

        /// AllAnimal.AsPet.AsWarmBlooded
        ///
        /// Parent Type: `WarmBlooded`
        public struct AsWarmBlooded: AnimalKingdomAPI.InlineFragment, Identifiable {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.WarmBlooded }
          @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
            .fragment(WarmBloodedDetails.self),
          ] }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            AllAnimalsQuery.Data.AllAnimal.self,
            AllAnimalsQuery.Data.AllAnimal.AsPet.self,
            AllAnimalsQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self,
            WarmBloodedDetails.self,
            HeightInMeters.self,
            PetDetails.self
          ] }

          public var id: AnimalKingdomAPI.ID { __data["id"] }
          public var height: Height { __data["height"] }
          public var species: String { __data["species"] }
          public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }
          public var predators: [Predator] { __data["predators"] }
          public var bodyTemperature: Int { __data["bodyTemperature"] }
          public var humanName: String? { __data["humanName"] }
          public var favoriteToy: String { __data["favoriteToy"] }
          public var owner: Owner? { __data["owner"] }

          public struct Fragments: FragmentContainer {
            @_spi(Unsafe) public let __data: DataDict
            @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

            public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
            public var heightInMeters: HeightInMeters { _toFragment() }
            public var petDetails: PetDetails { _toFragment() }
          }

          public init(
            __typename: String,
            id: AnimalKingdomAPI.ID,
            height: Height,
            species: String,
            skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
            predators: [Predator],
            bodyTemperature: Int,
            humanName: String? = nil,
            favoriteToy: String,
            owner: Owner? = nil
          ) {
            self.init(unsafelyWithData: [
              "__typename": __typename,
              "id": id,
              "height": height._fieldData,
              "species": species,
              "skinCovering": skinCovering,
              "predators": predators._fieldData,
              "bodyTemperature": bodyTemperature,
              "humanName": humanName,
              "favoriteToy": favoriteToy,
              "owner": owner._fieldData,
            ])
          }

          /// AllAnimal.AsPet.AsWarmBlooded.Height
          ///
          /// Parent Type: `Height`
          public struct Height: AnimalKingdomAPI.SelectionSet {
            @_spi(Unsafe) public let __data: DataDict
            @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

            @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
            @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              AllAnimalsQuery.Data.AllAnimal.AsPet.AsWarmBlooded.Height.self,
              AllAnimalsQuery.Data.AllAnimal.Height.self,
              HeightInMeters.Height.self,
              AllAnimalsQuery.Data.AllAnimal.AsPet.Height.self
            ] }

            public var feet: Int { __data["feet"] }
            public var inches: Int? { __data["inches"] }
            public var meters: Int { __data["meters"] }
            public var relativeSize: GraphQLEnum<AnimalKingdomAPI.RelativeSize> { __data["relativeSize"] }
            public var centimeters: Double { __data["centimeters"] }

            public init(
              feet: Int,
              inches: Int? = nil,
              meters: Int,
              relativeSize: GraphQLEnum<AnimalKingdomAPI.RelativeSize>,
              centimeters: Double
            ) {
              self.init(unsafelyWithData: [
                "__typename": AnimalKingdomAPI.Objects.Height.typename,
                "feet": feet,
                "inches": inches,
                "meters": meters,
                "relativeSize": relativeSize,
                "centimeters": centimeters,
              ])
            }
          }

          public typealias Owner = PetDetails.Owner
        }
      }

      /// AllAnimal.AsCat
      ///
      /// Parent Type: `Cat`
      public struct AsCat: AnimalKingdomAPI.InlineFragment, Identifiable {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Cat }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("isJellicle", Bool.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          AllAnimalsQuery.Data.AllAnimal.self,
          AllAnimalsQuery.Data.AllAnimal.AsCat.self,
          AllAnimalsQuery.Data.AllAnimal.AsWarmBlooded.self,
          WarmBloodedDetails.self,
          HeightInMeters.self,
          AllAnimalsQuery.Data.AllAnimal.AsPet.self,
          AllAnimalsQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self,
          PetDetails.self
        ] }

        public var isJellicle: Bool { __data["isJellicle"] }
        public var id: AnimalKingdomAPI.ID { __data["id"] }
        public var height: Height { __data["height"] }
        public var species: String { __data["species"] }
        public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }
        public var predators: [Predator] { __data["predators"] }
        public var bodyTemperature: Int { __data["bodyTemperature"] }
        public var humanName: String? { __data["humanName"] }
        public var favoriteToy: String { __data["favoriteToy"] }
        public var owner: Owner? { __data["owner"] }

        public struct Fragments: FragmentContainer {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public var heightInMeters: HeightInMeters { _toFragment() }
          public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
          public var petDetails: PetDetails { _toFragment() }
        }

        public init(
          isJellicle: Bool,
          id: AnimalKingdomAPI.ID,
          height: Height,
          species: String,
          skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
          predators: [Predator],
          bodyTemperature: Int,
          humanName: String? = nil,
          favoriteToy: String,
          owner: Owner? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": AnimalKingdomAPI.Objects.Cat.typename,
            "isJellicle": isJellicle,
            "id": id,
            "height": height._fieldData,
            "species": species,
            "skinCovering": skinCovering,
            "predators": predators._fieldData,
            "bodyTemperature": bodyTemperature,
            "humanName": humanName,
            "favoriteToy": favoriteToy,
            "owner": owner._fieldData,
          ])
        }

        /// AllAnimal.AsCat.Height
        ///
        /// Parent Type: `Height`
        public struct Height: AnimalKingdomAPI.SelectionSet {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            AllAnimalsQuery.Data.AllAnimal.AsCat.Height.self,
            AllAnimalsQuery.Data.AllAnimal.Height.self,
            HeightInMeters.Height.self,
            AllAnimalsQuery.Data.AllAnimal.AsPet.Height.self
          ] }

          public var feet: Int { __data["feet"] }
          public var inches: Int? { __data["inches"] }
          public var meters: Int { __data["meters"] }
          public var relativeSize: GraphQLEnum<AnimalKingdomAPI.RelativeSize> { __data["relativeSize"] }
          public var centimeters: Double { __data["centimeters"] }

          public init(
            feet: Int,
            inches: Int? = nil,
            meters: Int,
            relativeSize: GraphQLEnum<AnimalKingdomAPI.RelativeSize>,
            centimeters: Double
          ) {
            self.init(unsafelyWithData: [
              "__typename": AnimalKingdomAPI.Objects.Height.typename,
              "feet": feet,
              "inches": inches,
              "meters": meters,
              "relativeSize": relativeSize,
              "centimeters": centimeters,
            ])
          }
        }

        public typealias Owner = PetDetails.Owner
      }

      /// AllAnimal.AsClassroomPet
      ///
      /// Parent Type: `ClassroomPet`
      public struct AsClassroomPet: AnimalKingdomAPI.InlineFragment {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Unions.ClassroomPet }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .inlineFragment(AsBird.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          AllAnimalsQuery.Data.AllAnimal.self,
          AllAnimalsQuery.Data.AllAnimal.AsClassroomPet.self,
          HeightInMeters.self
        ] }

        public var id: AnimalKingdomAPI.ID { __data["id"] }
        public var height: Height { __data["height"] }
        public var species: String { __data["species"] }
        public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }
        public var predators: [Predator] { __data["predators"] }

        public var asBird: AsBird? { _asInlineFragment() }

        public struct Fragments: FragmentContainer {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public var heightInMeters: HeightInMeters { _toFragment() }
        }

        public init(
          __typename: String,
          id: AnimalKingdomAPI.ID,
          height: Height,
          species: String,
          skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
          predators: [Predator]
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
            "id": id,
            "height": height._fieldData,
            "species": species,
            "skinCovering": skinCovering,
            "predators": predators._fieldData,
          ])
        }

        /// AllAnimal.AsClassroomPet.Height
        ///
        /// Parent Type: `Height`
        public struct Height: AnimalKingdomAPI.SelectionSet {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            AllAnimalsQuery.Data.AllAnimal.AsClassroomPet.Height.self,
            AllAnimalsQuery.Data.AllAnimal.Height.self,
            HeightInMeters.Height.self
          ] }

          public var feet: Int { __data["feet"] }
          public var inches: Int? { __data["inches"] }
          public var meters: Int { __data["meters"] }

          public init(
            feet: Int,
            inches: Int? = nil,
            meters: Int
          ) {
            self.init(unsafelyWithData: [
              "__typename": AnimalKingdomAPI.Objects.Height.typename,
              "feet": feet,
              "inches": inches,
              "meters": meters,
            ])
          }
        }

        /// AllAnimal.AsClassroomPet.AsBird
        ///
        /// Parent Type: `Bird`
        public struct AsBird: AnimalKingdomAPI.InlineFragment, Identifiable {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Bird }
          @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
            .field("wingspan", Double.self),
          ] }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            AllAnimalsQuery.Data.AllAnimal.self,
            AllAnimalsQuery.Data.AllAnimal.AsClassroomPet.self,
            AllAnimalsQuery.Data.AllAnimal.AsClassroomPet.AsBird.self,
            AllAnimalsQuery.Data.AllAnimal.AsWarmBlooded.self,
            WarmBloodedDetails.self,
            HeightInMeters.self,
            AllAnimalsQuery.Data.AllAnimal.AsPet.self,
            AllAnimalsQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self,
            PetDetails.self
          ] }

          public var wingspan: Double { __data["wingspan"] }
          public var id: AnimalKingdomAPI.ID { __data["id"] }
          public var height: Height { __data["height"] }
          public var species: String { __data["species"] }
          public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }
          public var predators: [Predator] { __data["predators"] }
          public var bodyTemperature: Int { __data["bodyTemperature"] }
          public var humanName: String? { __data["humanName"] }
          public var favoriteToy: String { __data["favoriteToy"] }
          public var owner: Owner? { __data["owner"] }

          public struct Fragments: FragmentContainer {
            @_spi(Unsafe) public let __data: DataDict
            @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

            public var heightInMeters: HeightInMeters { _toFragment() }
            public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
            public var petDetails: PetDetails { _toFragment() }
          }

          public init(
            wingspan: Double,
            id: AnimalKingdomAPI.ID,
            height: Height,
            species: String,
            skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
            predators: [Predator],
            bodyTemperature: Int,
            humanName: String? = nil,
            favoriteToy: String,
            owner: Owner? = nil
          ) {
            self.init(unsafelyWithData: [
              "__typename": AnimalKingdomAPI.Objects.Bird.typename,
              "wingspan": wingspan,
              "id": id,
              "height": height._fieldData,
              "species": species,
              "skinCovering": skinCovering,
              "predators": predators._fieldData,
              "bodyTemperature": bodyTemperature,
              "humanName": humanName,
              "favoriteToy": favoriteToy,
              "owner": owner._fieldData,
            ])
          }

          /// AllAnimal.AsClassroomPet.AsBird.Height
          ///
          /// Parent Type: `Height`
          public struct Height: AnimalKingdomAPI.SelectionSet {
            @_spi(Unsafe) public let __data: DataDict
            @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

            @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
            @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              AllAnimalsQuery.Data.AllAnimal.AsClassroomPet.AsBird.Height.self,
              AllAnimalsQuery.Data.AllAnimal.Height.self,
              HeightInMeters.Height.self,
              AllAnimalsQuery.Data.AllAnimal.AsPet.Height.self
            ] }

            public var feet: Int { __data["feet"] }
            public var inches: Int? { __data["inches"] }
            public var meters: Int { __data["meters"] }
            public var relativeSize: GraphQLEnum<AnimalKingdomAPI.RelativeSize> { __data["relativeSize"] }
            public var centimeters: Double { __data["centimeters"] }

            public init(
              feet: Int,
              inches: Int? = nil,
              meters: Int,
              relativeSize: GraphQLEnum<AnimalKingdomAPI.RelativeSize>,
              centimeters: Double
            ) {
              self.init(unsafelyWithData: [
                "__typename": AnimalKingdomAPI.Objects.Height.typename,
                "feet": feet,
                "inches": inches,
                "meters": meters,
                "relativeSize": relativeSize,
                "centimeters": centimeters,
              ])
            }
          }

          public typealias Owner = PetDetails.Owner
        }
      }

      /// AllAnimal.AsDog
      ///
      /// Parent Type: `Dog`
      public struct AsDog: AnimalKingdomAPI.InlineFragment, Identifiable {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Dog }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("favoriteToy", String.self),
          .field("birthdate", AnimalKingdomAPI.CustomDate?.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          AllAnimalsQuery.Data.AllAnimal.self,
          AllAnimalsQuery.Data.AllAnimal.AsDog.self,
          AllAnimalsQuery.Data.AllAnimal.AsWarmBlooded.self,
          WarmBloodedDetails.self,
          HeightInMeters.self,
          AllAnimalsQuery.Data.AllAnimal.AsPet.self,
          AllAnimalsQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self,
          PetDetails.self
        ] }

        public var favoriteToy: String { __data["favoriteToy"] }
        public var birthdate: AnimalKingdomAPI.CustomDate? { __data["birthdate"] }
        public var id: AnimalKingdomAPI.ID { __data["id"] }
        public var height: Height { __data["height"] }
        public var species: String { __data["species"] }
        public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }
        public var predators: [Predator] { __data["predators"] }
        public var bodyTemperature: Int { __data["bodyTemperature"] }
        public var humanName: String? { __data["humanName"] }
        public var owner: Owner? { __data["owner"] }

        public struct Fragments: FragmentContainer {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public var heightInMeters: HeightInMeters { _toFragment() }
          public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
          public var petDetails: PetDetails { _toFragment() }
        }

        public init(
          favoriteToy: String,
          birthdate: AnimalKingdomAPI.CustomDate? = nil,
          id: AnimalKingdomAPI.ID,
          height: Height,
          species: String,
          skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
          predators: [Predator],
          bodyTemperature: Int,
          humanName: String? = nil,
          owner: Owner? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": AnimalKingdomAPI.Objects.Dog.typename,
            "favoriteToy": favoriteToy,
            "birthdate": birthdate,
            "id": id,
            "height": height._fieldData,
            "species": species,
            "skinCovering": skinCovering,
            "predators": predators._fieldData,
            "bodyTemperature": bodyTemperature,
            "humanName": humanName,
            "owner": owner._fieldData,
          ])
        }

        /// AllAnimal.AsDog.Height
        ///
        /// Parent Type: `Height`
        public struct Height: AnimalKingdomAPI.SelectionSet {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            AllAnimalsQuery.Data.AllAnimal.AsDog.Height.self,
            AllAnimalsQuery.Data.AllAnimal.Height.self,
            HeightInMeters.Height.self,
            AllAnimalsQuery.Data.AllAnimal.AsPet.Height.self
          ] }

          public var feet: Int { __data["feet"] }
          public var inches: Int? { __data["inches"] }
          public var meters: Int { __data["meters"] }
          public var relativeSize: GraphQLEnum<AnimalKingdomAPI.RelativeSize> { __data["relativeSize"] }
          public var centimeters: Double { __data["centimeters"] }

          public init(
            feet: Int,
            inches: Int? = nil,
            meters: Int,
            relativeSize: GraphQLEnum<AnimalKingdomAPI.RelativeSize>,
            centimeters: Double
          ) {
            self.init(unsafelyWithData: [
              "__typename": AnimalKingdomAPI.Objects.Height.typename,
              "feet": feet,
              "inches": inches,
              "meters": meters,
              "relativeSize": relativeSize,
              "centimeters": centimeters,
            ])
          }
        }

        public typealias Owner = PetDetails.Owner
      }
    }
  }
}
