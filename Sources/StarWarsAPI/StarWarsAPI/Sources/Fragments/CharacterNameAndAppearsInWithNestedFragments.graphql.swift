// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct CharacterNameAndAppearsInWithNestedFragments: StarWarsAPI.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment CharacterNameAndAppearsInWithNestedFragments on Character { __typename ...CharacterNameWithNestedAppearsInFragment }"#
  }

  @_spi(Unsafe) public let __data: DataDict
  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

  @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
  @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .fragment(CharacterNameWithNestedAppearsInFragment.self),
  ] }
  @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    CharacterNameAndAppearsInWithNestedFragments.self,
    CharacterNameWithNestedAppearsInFragment.self,
    CharacterAppearsIn.self
  ] }

  /// The name of the character
  public var name: String { __data["name"] }
  /// The movies this character appears in
  public var appearsIn: [GraphQLEnum<StarWarsAPI.Episode>?] { __data["appearsIn"] }

  public struct Fragments: FragmentContainer {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    public var characterNameWithNestedAppearsInFragment: CharacterNameWithNestedAppearsInFragment { _toFragment() }
    public var characterAppearsIn: CharacterAppearsIn { _toFragment() }
  }

  public init(
    __typename: String,
    name: String,
    appearsIn: [GraphQLEnum<StarWarsAPI.Episode>?]
  ) {
    self.init(unsafelyWithData: [
      "__typename": __typename,
      "name": name,
      "appearsIn": appearsIn,
    ])
  }
}
