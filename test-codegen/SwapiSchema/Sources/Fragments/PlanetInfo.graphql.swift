// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct PlanetInfo: SwapiSchema.SelectionSet, Fragment, Validatable, Codable {
  public static var fragmentDefinition: StaticString {
    #"fragment PlanetInfo on Planet { __typename name orbitalPeriod }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }
  public static func validate(value: Self?) throws {
    guard let value else { throw ValidationError.dataIsNil }
    try value.validate(String?.self, for: "name")
    try value.validate(Int?.self, for: "orbitalPeriod")
  }
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: String.self)
    __data = DataDict(data: [
      "__typename": try container.decode(String.self, forKey: "__typename"),
      "name": try container.decode(String?.self, forKey: "name"),
      "orbitalPeriod": try container.decode(Int?.self, forKey: "orbitalPeriod")
    ], fulfilledFragments: [
    ])
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: String.self)
    try container.encode(__typename, forKey: "__typename")
    try container.encode(name, forKey: "name")
    try container.encode(orbitalPeriod, forKey: "orbitalPeriod")
  }

  public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Objects.Planet }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("name", String?.self),
    .field("orbitalPeriod", Int?.self),
  ] }

  /// The name of this planet.
  public var name: String? { __data["name"] }
  /// The number of standard days it takes for this planet to complete a single orbit
  /// of its local star.
  public var orbitalPeriod: Int? { __data["orbitalPeriod"] }
}
