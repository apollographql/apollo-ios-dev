// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct NodeFragment: SwapiSchema.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment NodeFragment on Node { __typename id ... on Person { name goodOrBad } ...PlanetInfo }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }
  public static func validate(value: Self?) throws {
    guard let value else { throw ValidationError.dataIsNil }
    try value.validate(SwapiSchema.ID.self, for: "id")
    try value.asPerson?.validate()
    try value.asPlanet?.validate()
  }

  public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Interfaces.Node }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", SwapiSchema.ID.self),
    .inlineFragment(AsPerson.self),
    .inlineFragment(AsPlanet.self),
  ] }

  /// The id of the object.
  public var id: SwapiSchema.ID { __data["id"] }

  public var asPerson: AsPerson? { _asInlineFragment() }
  public var asPlanet: AsPlanet? { _asInlineFragment() }

  /// AsPerson
  ///
  /// Parent Type: `Person`
  public struct AsPerson: SwapiSchema.InlineFragment, Validatable {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }
    public static func validate(value: Self?) throws {
      guard let value else { throw ValidationError.dataIsNil }
      try value.validate(String?.self, for: "name")
      try value.validate(GraphQLEnum<SwapiSchema.GoodOrBad>?.self, for: "goodOrBad")
      try value.validate(SwapiSchema.ID.self, for: "id")
    }

    public typealias RootEntityType = NodeFragment
    public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Objects.Person }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("name", String?.self),
      .field("goodOrBad", GraphQLEnum<SwapiSchema.GoodOrBad>?.self),
    ] }

    /// The name of this person.
    public var name: String? { __data["name"] }
    /// Whether this is a good person or a bad one
    public var goodOrBad: GraphQLEnum<SwapiSchema.GoodOrBad>? { __data["goodOrBad"] }
    /// The id of the object.
    public var id: SwapiSchema.ID { __data["id"] }
  }

  /// AsPlanet
  ///
  /// Parent Type: `Planet`
  public struct AsPlanet: SwapiSchema.InlineFragment, Validatable {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }
    public static func validate(value: Self?) throws {
      guard let value else { throw ValidationError.dataIsNil }
      try value.validate(SwapiSchema.ID.self, for: "id")
      try value.validate(String?.self, for: "name")
      try value.validate(Int?.self, for: "orbitalPeriod")
    }

    public typealias RootEntityType = NodeFragment
    public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Objects.Planet }
    public static var __selections: [ApolloAPI.Selection] { [
      .fragment(PlanetInfo.self),
    ] }

    /// The id of the object.
    public var id: SwapiSchema.ID { __data["id"] }
    /// The name of this planet.
    public var name: String? { __data["name"] }
    /// The number of standard days it takes for this planet to complete a single orbit
    /// of its local star.
    public var orbitalPeriod: Int? { __data["orbitalPeriod"] }

    public struct Fragments: FragmentContainer {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public var planetInfo: PlanetInfo { _toFragment() }
    }
  }
}
