// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Unsafe) import ApolloAPI

public struct DogFragment: AnimalKingdomAPI.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment DogFragment on Dog { __typename species }"#
  }

  @_spi(Unsafe) public let __data: DataDict
  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { AnimalKingdomAPI.Objects.Dog }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("species", String.self),
  ] }
  public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    DogFragment.self
  ] }

  public var species: String { __data["species"] }

  public init(
    species: String
  ) {
    self.init(unsafelyWithData: [
      "__typename": AnimalKingdomAPI.Objects.Dog.typename,
      "species": species,
    ])
  }
}
