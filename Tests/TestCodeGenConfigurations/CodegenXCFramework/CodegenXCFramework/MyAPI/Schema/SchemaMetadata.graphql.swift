// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public protocol MyAPI_SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == MyAPI.SchemaMetadata {}

public protocol MyAPI_InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == MyAPI.SchemaMetadata {}

public protocol MyAPI_MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == MyAPI.SchemaMetadata {}

public protocol MyAPI_MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == MyAPI.SchemaMetadata {}

public extension MyAPI {
  typealias SelectionSet = MyAPI_SelectionSet

  typealias InlineFragment = MyAPI_InlineFragment

  typealias MutableSelectionSet = MyAPI_MutableSelectionSet

  typealias MutableInlineFragment = MyAPI_MutableInlineFragment

  enum SchemaMetadata: ApolloAPI.SchemaMetadata {
    public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

    public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
      switch typename {
      case "Bird": return MyAPI.Objects.Bird
      case "Cat": return MyAPI.Objects.Cat
      case "Crocodile": return MyAPI.Objects.Crocodile
      case "Dog": return MyAPI.Objects.Dog
      case "Fish": return MyAPI.Objects.Fish
      case "Height": return MyAPI.Objects.Height
      case "Human": return MyAPI.Objects.Human
      case "Mutation": return MyAPI.Objects.Mutation
      case "PetRock": return MyAPI.Objects.PetRock
      case "Query": return MyAPI.Objects.Query
      case "Rat": return MyAPI.Objects.Rat
      default: return nil
      }
    }
  }

  enum Objects {}
  enum Interfaces {}
  enum Unions {}

}