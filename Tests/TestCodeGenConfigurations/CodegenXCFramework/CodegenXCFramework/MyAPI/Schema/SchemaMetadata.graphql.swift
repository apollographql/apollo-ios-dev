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
      case "Query": return MyAPI.Objects.Query
      case "Human": return MyAPI.Objects.Human
      case "Cat": return MyAPI.Objects.Cat
      case "Dog": return MyAPI.Objects.Dog
      case "Bird": return MyAPI.Objects.Bird
      case "Fish": return MyAPI.Objects.Fish
      case "Rat": return MyAPI.Objects.Rat
      case "PetRock": return MyAPI.Objects.PetRock
      case "Crocodile": return MyAPI.Objects.Crocodile
      case "Height": return MyAPI.Objects.Height
      case "Mutation": return MyAPI.Objects.Mutation
      default: return nil
      }
    }
  }

  enum Objects {}
  enum Interfaces {}
  enum Unions {}

}