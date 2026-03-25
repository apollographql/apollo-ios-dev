// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == StarWarsAPI.SchemaMetadata {}

public protocol InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == StarWarsAPI.SchemaMetadata {}

public protocol MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == StarWarsAPI.SchemaMetadata {}

public protocol MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == StarWarsAPI.SchemaMetadata {}

public enum SchemaMetadata: ApolloAPI.SchemaMetadata {
  public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

  private static let objectTypeMap: [String: ApolloAPI.Object] = [
    "Droid": StarWarsAPI.Objects.Droid,
    "Human": StarWarsAPI.Objects.Human,
    "Mutation": StarWarsAPI.Objects.Mutation,
    "Query": StarWarsAPI.Objects.Query,
    "Review": StarWarsAPI.Objects.Review,
    "Starship": StarWarsAPI.Objects.Starship,
    "Subscription": StarWarsAPI.Objects.Subscription
  ]

  public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
    objectTypeMap[typename]
  }
}

public enum Objects {}
public enum Interfaces {}
public enum Unions {}
