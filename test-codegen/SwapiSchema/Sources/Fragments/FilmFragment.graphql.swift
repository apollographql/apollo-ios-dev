// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct FilmFragment: SwapiSchema.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment FilmFragment on Film { __typename director episodeID }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }
  public static func validate(value: Self?) throws {
    guard let value else { throw ValidationError.dataIsNil }
    try value.validate(String?.self, for: "director")
    try value.validate(Int?.self, for: "episodeID")
  }

  public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Objects.Film }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("director", String?.self),
    .field("episodeID", Int?.self),
  ] }

  /// The name of the director of this film.
  public var director: String? { __data["director"] }
  /// The episode number of this film.
  public var episodeID: Int? { __data["episodeID"] }
}
