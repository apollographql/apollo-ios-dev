// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct PersonOrPlanetInfo: SwapiSchema.SelectionSet, Fragment, Validatable, Codable {
  public static var fragmentDefinition: StaticString {
    #"fragment PersonOrPlanetInfo on PersonOrPlanet { __typename ... on Person { nestedStringArray nestedPlanetArray { __typename name } homeworld { __typename climates } } ... on Planet { climates diameter } }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }
  public static func validate(value: Self?) throws {
    guard let value else { throw ValidationError.dataIsNil }
    try value.asPerson?.validate()
    try value.asPlanet?.validate()
  }
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: String.self)
    __data = DataDict(data: [
      "__typename": try container.decode(String.self, forKey: "__typename"),
    ], fulfilledFragments: [
      (try? AsPerson(from: decoder)) != nil ? ObjectIdentifier(AsPerson.self): nil,
      (try? AsPlanet(from: decoder)) != nil ? ObjectIdentifier(AsPlanet.self): nil
    ])
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: String.self)
    try container.encode(__typename, forKey: "__typename")
    try self.asPerson?.encode(to: encoder)
    try self.asPlanet?.encode(to: encoder)
  }

  public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Unions.PersonOrPlanet }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .inlineFragment(AsPerson.self),
    .inlineFragment(AsPlanet.self),
  ] }

  public var asPerson: AsPerson? { _asInlineFragment() }
  public var asPlanet: AsPlanet? { _asInlineFragment() }

  /// AsPerson
  ///
  /// Parent Type: `Person`
  public struct AsPerson: SwapiSchema.InlineFragment, Validatable, Codable {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }
    public static func validate(value: Self?) throws {
      guard let value else { throw ValidationError.dataIsNil }
      try value.validate([[[String?]?]?].self, for: "nestedStringArray")
      try value.validate([[[NestedPlanetArray?]?]?].self, for: "nestedPlanetArray")
      try value.validate(Homeworld?.self, for: "homeworld")
    }
    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: String.self)
      __data = DataDict(data: [
        "__typename": try container.decode(String.self, forKey: "__typename"),
        "nestedStringArray": try container.decode([[[String?]?]?].self, forKey: "nestedStringArray"),
        "nestedPlanetArray": try container.decode([[[NestedPlanetArray?]?]?].self, forKey: "nestedPlanetArray"),
        "homeworld": try container.decode(Homeworld?.self, forKey: "homeworld")
      ], fulfilledFragments: [
      ])
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: String.self)
      try container.encode(__typename, forKey: "__typename")
      try container.encode(nestedStringArray, forKey: "nestedStringArray")
      try container.encode(nestedPlanetArray, forKey: "nestedPlanetArray")
      try container.encode(homeworld, forKey: "homeworld")
    }

    public typealias RootEntityType = PersonOrPlanetInfo
    public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Objects.Person }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("nestedStringArray", [[[String?]?]?].self),
      .field("nestedPlanetArray", [[[NestedPlanetArray?]?]?].self),
      .field("homeworld", Homeworld?.self),
    ] }

    public var nestedStringArray: [[[String?]?]?] { __data["nestedStringArray"] }
    public var nestedPlanetArray: [[[NestedPlanetArray?]?]?] { __data["nestedPlanetArray"] }
    /// A planet that this person was born on or inhabits.
    public var homeworld: Homeworld? { __data["homeworld"] }

    /// AsPerson.NestedPlanetArray
    ///
    /// Parent Type: `Planet`
    public struct NestedPlanetArray: SwapiSchema.SelectionSet, Validatable, Codable {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }
      public static func validate(value: Self?) throws {
        guard let value else { throw ValidationError.dataIsNil }
        try value.validate(String?.self, for: "name")
      }
      public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: String.self)
        __data = DataDict(data: [
          "__typename": try container.decode(String.self, forKey: "__typename"),
          "name": try container.decode(String?.self, forKey: "name")
        ], fulfilledFragments: [
        ])
      }

      public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: String.self)
        try container.encode(__typename, forKey: "__typename")
        try container.encode(name, forKey: "name")
      }

      public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Objects.Planet }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("name", String?.self),
      ] }

      /// The name of this planet.
      public var name: String? { __data["name"] }
    }

    /// AsPerson.Homeworld
    ///
    /// Parent Type: `Planet`
    public struct Homeworld: SwapiSchema.SelectionSet, Validatable, Codable {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }
      public static func validate(value: Self?) throws {
        guard let value else { throw ValidationError.dataIsNil }
        try value.validate([String?]?.self, for: "climates")
      }
      public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: String.self)
        __data = DataDict(data: [
          "__typename": try container.decode(String.self, forKey: "__typename"),
          "climates": try container.decode([String?]?.self, forKey: "climates")
        ], fulfilledFragments: [
        ])
      }

      public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: String.self)
        try container.encode(__typename, forKey: "__typename")
        try container.encode(climates, forKey: "climates")
      }

      public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Objects.Planet }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("climates", [String?]?.self),
      ] }

      /// The climates of this planet.
      public var climates: [String?]? { __data["climates"] }
    }
  }

  /// AsPlanet
  ///
  /// Parent Type: `Planet`
  public struct AsPlanet: SwapiSchema.InlineFragment, Validatable, Codable {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }
    public static func validate(value: Self?) throws {
      guard let value else { throw ValidationError.dataIsNil }
      try value.validate([String?]?.self, for: "climates")
      try value.validate(Int?.self, for: "diameter")
    }
    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: String.self)
      __data = DataDict(data: [
        "__typename": try container.decode(String.self, forKey: "__typename"),
        "climates": try container.decode([String?]?.self, forKey: "climates"),
        "diameter": try container.decode(Int?.self, forKey: "diameter")
      ], fulfilledFragments: [
      ])
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: String.self)
      try container.encode(__typename, forKey: "__typename")
      try container.encode(climates, forKey: "climates")
      try container.encode(diameter, forKey: "diameter")
    }

    public typealias RootEntityType = PersonOrPlanetInfo
    public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Objects.Planet }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("climates", [String?]?.self),
      .field("diameter", Int?.self),
    ] }

    /// The climates of this planet.
    public var climates: [String?]? { __data["climates"] }
    /// The diameter of this planet in kilometers.
    public var diameter: Int? { __data["diameter"] }
  }
}
