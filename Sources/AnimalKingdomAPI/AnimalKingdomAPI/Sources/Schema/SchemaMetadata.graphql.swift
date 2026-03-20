// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == AnimalKingdomAPI.SchemaMetadata {}

public protocol InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == AnimalKingdomAPI.SchemaMetadata {}

public protocol MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == AnimalKingdomAPI.SchemaMetadata {}

public protocol MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == AnimalKingdomAPI.SchemaMetadata {}

public enum SchemaMetadata: ApolloAPI.SchemaMetadata {
  public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

  private static let objectTypeMap: [String: ApolloAPI.Object] = [
    "Bird": AnimalKingdomAPI.Objects.Bird,
    "Cat": AnimalKingdomAPI.Objects.Cat,
    "Crocodile": AnimalKingdomAPI.Objects.Crocodile,
    "Dog": AnimalKingdomAPI.Objects.Dog,
    "Fish": AnimalKingdomAPI.Objects.Fish,
    "Height": AnimalKingdomAPI.Objects.Height,
    "Human": AnimalKingdomAPI.Objects.Human,
    "Mutation": AnimalKingdomAPI.Objects.Mutation,
    "PetRock": AnimalKingdomAPI.Objects.PetRock,
    "Query": AnimalKingdomAPI.Objects.Query,
    "Rat": AnimalKingdomAPI.Objects.Rat
  ]

  @_spi(Execution) public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
    objectTypeMap[typename]
  }
}

public enum Objects {}
public enum Interfaces {}
public enum Unions {}
