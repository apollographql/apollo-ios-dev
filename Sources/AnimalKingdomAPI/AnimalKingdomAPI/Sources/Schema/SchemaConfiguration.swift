// @generated
// This file was automatically generated and can be edited to
// provide custom configuration for a generated GraphQL schema.
//
// Any changes to this file will not be overwritten by future
// code generation execution.

import ApolloAPI

public enum SchemaConfiguration: ApolloAPI.SchemaConfiguration {
  public static func cacheKeyInfo(
    for type: ApolloAPI.Object,
    object: ApolloAPI.ObjectData
  ) -> ApolloAPI.CacheKeyInfo? {
    // Implement this function to configure cache key resolution for your schema types.
    return nil
  }


  static func cacheKey(for field: ApolloAPI.Selection.Field, variables: ApolloAPI.GraphQLOperation.Variables?, path: ApolloAPI.ResponsePath) -> ApolloAPI.CacheKeyInfo? {
    // Implement this function to configure cache key resolution for fields that return a single object/value
    return nil
  }


  static func cacheKeys(for field: ApolloAPI.Selection.Field, variables: ApolloAPI.GraphQLOperation.Variables?, path: ApolloAPI.ResponsePath) -> [ApolloAPI.CacheKeyInfo]? {
    // Implement this function to configure cache key resolution for fields that return a list of objects/values
    return nil
  }  
}
