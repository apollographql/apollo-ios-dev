// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct FriendsNames: StarWarsAPI.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment FriendsNames on Character { __typename friends { __typename name } }"#
  }

  @_spi(Unsafe) public let __data: DataDict
  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

  @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
  @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("friends", [Friend?]?.self),
  ] }
  @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    FriendsNames.self
  ] }

  /// The friends of the character, or an empty list if they have none
  public var friends: [Friend?]? { __data["friends"] }

  public init(
    __typename: String,
    friends: [Friend?]? = nil
  ) {
    self.init(unsafelyWithData: [
      "__typename": __typename,
      "friends": friends._fieldData,
    ])
  }

  /// Friend
  ///
  /// Parent Type: `Character`
  public struct Friend: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Interfaces.Character }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("name", String.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      FriendsNames.Friend.self
    ] }

    /// The name of the character
    public var name: String { __data["name"] }

    public init(
      __typename: String,
      name: String
    ) {
      self.init(unsafelyWithData: [
        "__typename": __typename,
        "name": name,
      ])
    }
  }
}
