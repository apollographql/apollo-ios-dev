// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct HumanHeightWithVariable: StarWarsAPI.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment HumanHeightWithVariable on Human { __typename height(unit: $heightUnit) }"#
  }

  @_spi(Unsafe) public let __data: DataDict
  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

  @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Human }
  @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("height", Double?.self, arguments: ["unit": .variable("heightUnit")]),
  ] }
  @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    HumanHeightWithVariable.self
  ] }

  /// Height in the preferred unit, default is meters
  public var height: Double? { __data["height"] }

  public init(
    height: Double? = nil
  ) {
    self.init(unsafelyWithData: [
      "__typename": StarWarsAPI.Objects.Human.typename,
      "height": height,
    ])
  }
}
