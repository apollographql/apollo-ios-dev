// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct HeightInMeters: AnimalKingdomAPI.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment HeightInMeters on Animal { __typename height { __typename meters } }"#
  }

  @_spi(Unsafe) public let __data: DataDict
  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

  @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.Animal }
  @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("height", Height.self),
  ] }
  @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
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
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Height }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("meters", Int.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
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
