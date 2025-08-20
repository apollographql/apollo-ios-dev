// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Unsafe) import ApolloAPI

public struct AuthorDetails: GitHubAPI.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment AuthorDetails on Actor { __typename login ... on User { __typename id name } }"#
  }

  @_spi(Unsafe) public let __data: DataDict
  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Interfaces.Actor }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("login", String.self),
    .inlineFragment(AsUser.self),
  ] }
  public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    AuthorDetails.self
  ] }

  /// The username of the actor.
  public var login: String { __data["login"] }

  public var asUser: AsUser? { _asInlineFragment() }

  /// AsUser
  ///
  /// Parent Type: `User`
  public struct AsUser: GitHubAPI.InlineFragment {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    public typealias RootEntityType = AuthorDetails
    public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Objects.User }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("id", GitHubAPI.ID.self),
      .field("name", String?.self),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      AuthorDetails.self,
      AuthorDetails.AsUser.self
    ] }

    public var id: GitHubAPI.ID { __data["id"] }
    /// The user's public profile name.
    public var name: String? { __data["name"] }
    /// The username of the actor.
    public var login: String { __data["login"] }
  }
}
