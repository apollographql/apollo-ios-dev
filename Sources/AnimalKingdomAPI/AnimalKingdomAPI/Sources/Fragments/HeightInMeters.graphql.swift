// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct HeightInMeters: AnimalKingdomAPI.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment HeightInMeters on Animal { __typename height { __typename meters } }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Animal }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("height", Height.self),
  ] }
  public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    HeightInMeters.self
  ] }

  public var height: Height { __data["height"] }

  public init(
    __typename: String,
    height: Height
  ) {
    self.init(unsafelyWithData: [
      "__typename": __typename,
      "height": height._fieldData,
    ])
  }

  /// Height
  ///
  /// Parent Type: `Height`
  public struct Height: AnimalKingdomAPI.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("meters", Int.self),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      HeightInMeters.Height.self
    ] }

    public var meters: Int { __data["meters"] }

    public init(
      meters: Int
    ) {
      self.init(unsafelyWithData: [
        "__typename": AnimalKingdomAPI.Objects.Height.typename,
        "meters": meters,
      ])
    }
  }
}
