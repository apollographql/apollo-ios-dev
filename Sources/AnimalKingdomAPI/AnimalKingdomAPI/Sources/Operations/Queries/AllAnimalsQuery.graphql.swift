// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class AllAnimalsQuery: GraphQLQuery {
  public static let operationName: String = "AllAnimalsQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query AllAnimalsQuery { allAnimals { __typename id height { __typename feet inches } ...HeightInMeters ...WarmBloodedDetails species skinCovering ... on Pet { ...PetDetails ...WarmBloodedDetails ... on Animal { height { __typename relativeSize centimeters } } } ... on Cat { isJellicle } ... on ClassroomPet { ... on Bird { wingspan } } ... on Dog { favoriteToy birthdate } predators { __typename species ... on WarmBlooded { predators { __typename species } ...WarmBloodedDetails laysEggs } } } }"#,
      fragments: [HeightInMeters.self, PetDetails.self, WarmBloodedDetails.self]
    ))

  public init() {}

  public struct Data: AnimalKingdomAPI.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("allAnimals", [AllAnimal].self),
    ] }

    public var allAnimals: [AllAnimal] { __data["allAnimals"] }

    public init(
      allAnimals: [AllAnimal]
    ) {
      self.init(_dataDict: DataDict(
        data: [
          "__typename": AnimalKingdomAPI.Objects.Query.typename,
          "allAnimals": allAnimals._fieldData,
        ],
        fulfilledFragments: [
          ObjectIdentifier(AllAnimalsQuery.Data.self)
        ]
      ))
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
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

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
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "id": id,
            "height": height._fieldData,
            "species": species,
            "skinCovering": skinCovering,
            "predators": predators._fieldData,
          ],
          fulfilledFragments: [
            ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.self)
          ]
        ))
      }

      /// AllAnimal.Height
      ///
      /// Parent Type: `Height`
      public struct Height: AnimalKingdomAPI.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("feet", Int.self),
          .field("inches", Int?.self),
        ] }

        public var feet: Int { __data["feet"] }
        public var inches: Int? { __data["inches"] }
        public var meters: Int { __data["meters"] }

        public init(
          feet: Int,
          inches: Int? = nil,
          meters: Int
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": AnimalKingdomAPI.Objects.Height.typename,
              "feet": feet,
              "inches": inches,
              "meters": meters,
            ],
            fulfilledFragments: [
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Height.self),
              ObjectIdentifier(HeightInMeters.Height.self)
            ]
          ))
        }
      }

      /// AllAnimal.Predator
      ///
      /// Parent Type: `Animal`
      public struct Predator: AnimalKingdomAPI.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Animal }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("species", String.self),
          .inlineFragment(AsWarmBlooded.self),
        ] }

        public var species: String { __data["species"] }

        public var asWarmBlooded: AsWarmBlooded? { _asInlineFragment() }

        public init(
          __typename: String,
          species: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "species": species,
            ],
            fulfilledFragments: [
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Predator.self)
            ]
          ))
        }

        /// AllAnimal.Predator.AsWarmBlooded
        ///
        /// Parent Type: `WarmBlooded`
        public struct AsWarmBlooded: AnimalKingdomAPI.InlineFragment {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal.Predator
          public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.WarmBlooded }
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

          public init(
            __typename: String,
            predators: [Predator],
            laysEggs: Bool,
            species: String,
            bodyTemperature: Int,
            height: Height
          ) {
            self.init(_dataDict: DataDict(
              data: [
                "__typename": __typename,
                "predators": predators._fieldData,
                "laysEggs": laysEggs,
                "species": species,
                "bodyTemperature": bodyTemperature,
                "height": height._fieldData,
              ],
              fulfilledFragments: [
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Predator.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Predator.AsWarmBlooded.self),
                ObjectIdentifier(WarmBloodedDetails.self),
                ObjectIdentifier(HeightInMeters.self)
              ]
            ))
          }

          /// AllAnimal.Predator.AsWarmBlooded.Predator
          ///
          /// Parent Type: `Animal`
          public struct Predator: AnimalKingdomAPI.SelectionSet {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Animal }
            public static var __selections: [ApolloAPI.Selection] { [
              .field("__typename", String.self),
              .field("species", String.self),
            ] }

            public var species: String { __data["species"] }

            public init(
              __typename: String,
              species: String
            ) {
              self.init(_dataDict: DataDict(
                data: [
                  "__typename": __typename,
                  "species": species,
                ],
                fulfilledFragments: [
                  ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Predator.AsWarmBlooded.Predator.self)
                ]
              ))
            }
          }

          public typealias Height = HeightInMeters.Height
        }
      }

      /// AllAnimal.AsWarmBlooded
      ///
      /// Parent Type: `WarmBlooded`
      public struct AsWarmBlooded: AnimalKingdomAPI.InlineFragment, Identifiable {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.WarmBlooded }
        public static var __selections: [ApolloAPI.Selection] { [
          .fragment(WarmBloodedDetails.self),
        ] }

        public var id: AnimalKingdomAPI.ID { __data["id"] }
        public var height: Height { __data["height"] }
        public var species: String { __data["species"] }
        public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }
        public var predators: [Predator] { __data["predators"] }
        public var bodyTemperature: Int { __data["bodyTemperature"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "id": id,
              "height": height._fieldData,
              "species": species,
              "skinCovering": skinCovering,
              "predators": predators._fieldData,
              "bodyTemperature": bodyTemperature,
            ],
            fulfilledFragments: [
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.self),
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsWarmBlooded.self),
              ObjectIdentifier(WarmBloodedDetails.self),
              ObjectIdentifier(HeightInMeters.self)
            ]
          ))
        }

        /// AllAnimal.AsWarmBlooded.Height
        ///
        /// Parent Type: `Height`
        public struct Height: AnimalKingdomAPI.SelectionSet {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }

          public var feet: Int { __data["feet"] }
          public var inches: Int? { __data["inches"] }
          public var meters: Int { __data["meters"] }

          public init(
            feet: Int,
            inches: Int? = nil,
            meters: Int
          ) {
            self.init(_dataDict: DataDict(
              data: [
                "__typename": AnimalKingdomAPI.Objects.Height.typename,
                "feet": feet,
                "inches": inches,
                "meters": meters,
              ],
              fulfilledFragments: [
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsWarmBlooded.Height.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Height.self),
                ObjectIdentifier(HeightInMeters.Height.self)
              ]
            ))
          }
        }
      }

      /// AllAnimal.AsPet
      ///
      /// Parent Type: `Pet`
      public struct AsPet: AnimalKingdomAPI.InlineFragment, Identifiable {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Pet }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("height", Height.self),
          .inlineFragment(AsWarmBlooded.self),
          .fragment(PetDetails.self),
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
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "height": height._fieldData,
              "id": id,
              "species": species,
              "skinCovering": skinCovering,
              "predators": predators._fieldData,
              "humanName": humanName,
              "favoriteToy": favoriteToy,
              "owner": owner._fieldData,
            ],
            fulfilledFragments: [
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.self),
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.self),
              ObjectIdentifier(PetDetails.self)
            ]
          ))
        }

        /// AllAnimal.AsPet.Height
        ///
        /// Parent Type: `Height`
        public struct Height: AnimalKingdomAPI.SelectionSet {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("relativeSize", GraphQLEnum<AnimalKingdomAPI.RelativeSize>.self),
            .field("centimeters", Double.self),
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
            self.init(_dataDict: DataDict(
              data: [
                "__typename": AnimalKingdomAPI.Objects.Height.typename,
                "relativeSize": relativeSize,
                "centimeters": centimeters,
                "feet": feet,
                "inches": inches,
                "meters": meters,
              ],
              fulfilledFragments: [
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.Height.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Height.self),
                ObjectIdentifier(HeightInMeters.Height.self)
              ]
            ))
          }
        }

        public typealias Owner = PetDetails.Owner

        /// AllAnimal.AsPet.AsWarmBlooded
        ///
        /// Parent Type: `WarmBlooded`
        public struct AsWarmBlooded: AnimalKingdomAPI.InlineFragment, Identifiable {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
          public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.WarmBlooded }
          public static var __selections: [ApolloAPI.Selection] { [
            .fragment(WarmBloodedDetails.self),
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
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

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
            self.init(_dataDict: DataDict(
              data: [
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
              ],
              fulfilledFragments: [
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self),
                ObjectIdentifier(WarmBloodedDetails.self),
                ObjectIdentifier(HeightInMeters.self),
                ObjectIdentifier(PetDetails.self)
              ]
            ))
          }

          /// AllAnimal.AsPet.AsWarmBlooded.Height
          ///
          /// Parent Type: `Height`
          public struct Height: AnimalKingdomAPI.SelectionSet {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }

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
              self.init(_dataDict: DataDict(
                data: [
                  "__typename": AnimalKingdomAPI.Objects.Height.typename,
                  "feet": feet,
                  "inches": inches,
                  "meters": meters,
                  "relativeSize": relativeSize,
                  "centimeters": centimeters,
                ],
                fulfilledFragments: [
                  ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.AsWarmBlooded.Height.self),
                  ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Height.self),
                  ObjectIdentifier(HeightInMeters.Height.self),
                  ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.Height.self)
                ]
              ))
            }
          }

          public typealias Owner = PetDetails.Owner
        }
      }

      /// AllAnimal.AsCat
      ///
      /// Parent Type: `Cat`
      public struct AsCat: AnimalKingdomAPI.InlineFragment, Identifiable {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Cat }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("isJellicle", Bool.self),
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
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

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
          self.init(_dataDict: DataDict(
            data: [
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
            ],
            fulfilledFragments: [
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.self),
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsCat.self),
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsWarmBlooded.self),
              ObjectIdentifier(WarmBloodedDetails.self),
              ObjectIdentifier(HeightInMeters.self),
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.self),
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self),
              ObjectIdentifier(PetDetails.self)
            ]
          ))
        }

        /// AllAnimal.AsCat.Height
        ///
        /// Parent Type: `Height`
        public struct Height: AnimalKingdomAPI.SelectionSet {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }

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
            self.init(_dataDict: DataDict(
              data: [
                "__typename": AnimalKingdomAPI.Objects.Height.typename,
                "feet": feet,
                "inches": inches,
                "meters": meters,
                "relativeSize": relativeSize,
                "centimeters": centimeters,
              ],
              fulfilledFragments: [
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsCat.Height.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Height.self),
                ObjectIdentifier(HeightInMeters.Height.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.Height.self)
              ]
            ))
          }
        }

        public typealias Owner = PetDetails.Owner
      }

      /// AllAnimal.AsClassroomPet
      ///
      /// Parent Type: `ClassroomPet`
      public struct AsClassroomPet: AnimalKingdomAPI.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Unions.ClassroomPet }
        public static var __selections: [ApolloAPI.Selection] { [
          .inlineFragment(AsBird.self),
        ] }

        public var id: AnimalKingdomAPI.ID { __data["id"] }
        public var height: Height { __data["height"] }
        public var species: String { __data["species"] }
        public var skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? { __data["skinCovering"] }
        public var predators: [Predator] { __data["predators"] }

        public var asBird: AsBird? { _asInlineFragment() }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "id": id,
              "height": height._fieldData,
              "species": species,
              "skinCovering": skinCovering,
              "predators": predators._fieldData,
            ],
            fulfilledFragments: [
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.self),
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsClassroomPet.self),
              ObjectIdentifier(HeightInMeters.self)
            ]
          ))
        }

        /// AllAnimal.AsClassroomPet.Height
        ///
        /// Parent Type: `Height`
        public struct Height: AnimalKingdomAPI.SelectionSet {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }

          public var feet: Int { __data["feet"] }
          public var inches: Int? { __data["inches"] }
          public var meters: Int { __data["meters"] }

          public init(
            feet: Int,
            inches: Int? = nil,
            meters: Int
          ) {
            self.init(_dataDict: DataDict(
              data: [
                "__typename": AnimalKingdomAPI.Objects.Height.typename,
                "feet": feet,
                "inches": inches,
                "meters": meters,
              ],
              fulfilledFragments: [
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsClassroomPet.Height.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Height.self),
                ObjectIdentifier(HeightInMeters.Height.self)
              ]
            ))
          }
        }

        /// AllAnimal.AsClassroomPet.AsBird
        ///
        /// Parent Type: `Bird`
        public struct AsBird: AnimalKingdomAPI.InlineFragment, Identifiable {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
          public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Bird }
          public static var __selections: [ApolloAPI.Selection] { [
            .field("wingspan", Double.self),
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
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

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
            self.init(_dataDict: DataDict(
              data: [
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
              ],
              fulfilledFragments: [
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsClassroomPet.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsClassroomPet.AsBird.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsWarmBlooded.self),
                ObjectIdentifier(WarmBloodedDetails.self),
                ObjectIdentifier(HeightInMeters.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self),
                ObjectIdentifier(PetDetails.self)
              ]
            ))
          }

          /// AllAnimal.AsClassroomPet.AsBird.Height
          ///
          /// Parent Type: `Height`
          public struct Height: AnimalKingdomAPI.SelectionSet {
            public let __data: DataDict
            public init(_dataDict: DataDict) { __data = _dataDict }

            public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }

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
              self.init(_dataDict: DataDict(
                data: [
                  "__typename": AnimalKingdomAPI.Objects.Height.typename,
                  "feet": feet,
                  "inches": inches,
                  "meters": meters,
                  "relativeSize": relativeSize,
                  "centimeters": centimeters,
                ],
                fulfilledFragments: [
                  ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsClassroomPet.AsBird.Height.self),
                  ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Height.self),
                  ObjectIdentifier(HeightInMeters.Height.self),
                  ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.Height.self)
                ]
              ))
            }
          }

          public typealias Owner = PetDetails.Owner
        }
      }

      /// AllAnimal.AsDog
      ///
      /// Parent Type: `Dog`
      public struct AsDog: AnimalKingdomAPI.InlineFragment, Identifiable {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = AllAnimalsQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Dog }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("favoriteToy", String.self),
          .field("birthdate", AnimalKingdomAPI.CustomDate?.self),
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
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

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
          self.init(_dataDict: DataDict(
            data: [
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
            ],
            fulfilledFragments: [
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.self),
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsDog.self),
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsWarmBlooded.self),
              ObjectIdentifier(WarmBloodedDetails.self),
              ObjectIdentifier(HeightInMeters.self),
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.self),
              ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self),
              ObjectIdentifier(PetDetails.self)
            ]
          ))
        }

        /// AllAnimal.AsDog.Height
        ///
        /// Parent Type: `Height`
        public struct Height: AnimalKingdomAPI.SelectionSet {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }

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
            self.init(_dataDict: DataDict(
              data: [
                "__typename": AnimalKingdomAPI.Objects.Height.typename,
                "feet": feet,
                "inches": inches,
                "meters": meters,
                "relativeSize": relativeSize,
                "centimeters": centimeters,
              ],
              fulfilledFragments: [
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsDog.Height.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.Height.self),
                ObjectIdentifier(HeightInMeters.Height.self),
                ObjectIdentifier(AllAnimalsQuery.Data.AllAnimal.AsPet.Height.self)
              ]
            ))
          }
        }

        public typealias Owner = PetDetails.Owner
      }
    }
  }
}
