// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Unsafe) import ApolloAPI

public struct WarmBloodedDetails: AnimalKingdomAPI.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment WarmBloodedDetails on WarmBlooded { __typename bodyTemperature ...HeightInMeters }"#
  }

  @_spi(Unsafe) public let __data: DataDict
  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Interfaces.WarmBlooded }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("bodyTemperature", Int.self),
    .fragment(HeightInMeters.self),
  ] }
  public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    WarmBloodedDetails.self,
    HeightInMeters.self
  ] }

  public var bodyTemperature: Int { __data["bodyTemperature"] }
  public var height: Height { __data["height"] }

  public struct Fragments: FragmentContainer {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    public var heightInMeters: HeightInMeters { _toFragment() }
  }

  public init(
    __typename: String,
    bodyTemperature: Int,
    height: Height
  ) {
    self.init(unsafelyWithData: [
      "__typename": __typename,
      "bodyTemperature": bodyTemperature,
      "height": height._fieldData,
    ])
  }

  public typealias Height = HeightInMeters.Height
}
