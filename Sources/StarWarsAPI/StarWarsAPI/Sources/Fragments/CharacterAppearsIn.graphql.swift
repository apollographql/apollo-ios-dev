// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct CharacterAppearsIn: StarWarsAPI.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment CharacterAppearsIn on Character { __typename appearsIn }"#
  }

  @_spi(Unsafe) public let __data: DataDict
  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

  @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
  @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("appearsIn", [GraphQLEnum<StarWarsAPI.Episode>?].self),
  ] }
  @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    CharacterAppearsIn.self
  ] }

  /// The movies this character appears in
  public var appearsIn: [GraphQLEnum<StarWarsAPI.Episode>?] { __data["appearsIn"] }

  public init(
    __typename: String,
    appearsIn: [GraphQLEnum<StarWarsAPI.Episode>?]
  ) {
    self.init(unsafelyWithData: [
      "__typename": __typename,
      "appearsIn": appearsIn,
    ])
  }
}
