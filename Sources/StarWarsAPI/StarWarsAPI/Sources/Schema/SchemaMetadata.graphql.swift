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

  @_spi(Execution) public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
    switch typename {
    case "Droid": return StarWarsAPI.Objects.Droid
    case "Human": return StarWarsAPI.Objects.Human
    case "Mutation": return StarWarsAPI.Objects.Mutation
    case "Query": return StarWarsAPI.Objects.Query
    case "Review": return StarWarsAPI.Objects.Review
    case "Starship": return StarWarsAPI.Objects.Starship
    case "Subscription": return StarWarsAPI.Objects.Subscription
    default: return nil
    }
  }
}

public enum Objects {}
public enum Interfaces {}
public enum Unions {}
