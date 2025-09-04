// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct PetDetails: AnimalKingdomAPI.SelectionSet, Fragment, Identifiable {
  public static var fragmentDefinition: StaticString {
    #"fragment PetDetails on Pet { __typename id humanName favoriteToy owner { __typename firstName } }"#
  }

  @_spi(Unsafe) public let __data: DataDict
  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

  @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Pet }
  @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", AnimalKingdomAPI.ID.self),
    .field("humanName", String?.self),
    .field("favoriteToy", String.self),
    .field("owner", Owner?.self),
  ] }
  @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    PetDetails.self
  ] }

  public var id: AnimalKingdomAPI.ID { __data["id"] }
  public var humanName: String? { __data["humanName"] }
  public var favoriteToy: String { __data["favoriteToy"] }
  public var owner: Owner? { __data["owner"] }

  public init(
    __typename: String,
    id: AnimalKingdomAPI.ID,
    humanName: String? = nil,
    favoriteToy: String,
    owner: Owner? = nil
  ) {
    self.init(unsafelyWithData: [
      "__typename": __typename,
      "id": id,
      "humanName": humanName,
      "favoriteToy": favoriteToy,
      "owner": owner._fieldData,
    ])
  }

  /// Owner
  ///
  /// Parent Type: `Human`
  public struct Owner: AnimalKingdomAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Human }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("firstName", String.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      PetDetails.Owner.self
    ] }

    public var firstName: String { __data["firstName"] }

    public init(
      firstName: String
    ) {
      self.init(unsafelyWithData: [
        "__typename": AnimalKingdomAPI.Objects.Human.typename,
        "firstName": firstName,
      ])
    }
  }
}
