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

  public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
    switch typename {
    case "Bird": return AnimalKingdomAPI.Objects.Bird
    case "Cat": return AnimalKingdomAPI.Objects.Cat
    case "Crocodile": return AnimalKingdomAPI.Objects.Crocodile
    case "Dog": return AnimalKingdomAPI.Objects.Dog
    case "Fish": return AnimalKingdomAPI.Objects.Fish
    case "Height": return AnimalKingdomAPI.Objects.Height
    case "Human": return AnimalKingdomAPI.Objects.Human
    case "Mutation": return AnimalKingdomAPI.Objects.Mutation
    case "PetRock": return AnimalKingdomAPI.Objects.PetRock
    case "Query": return AnimalKingdomAPI.Objects.Query
    case "Rat": return AnimalKingdomAPI.Objects.Rat
    default: return nil
    }
  }
}

public enum Objects {}
public enum Interfaces {}
public enum Unions {}
