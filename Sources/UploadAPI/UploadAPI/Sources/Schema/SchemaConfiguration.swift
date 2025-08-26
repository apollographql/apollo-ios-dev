// @generated
// This file was automatically generated and can be edited to
// provide custom configuration for a generated GraphQL schema.
//
// Any changes to this file will not be overwritten by future
// code generation execution.

import ApolloAPI

public enum SchemaConfiguration: ApolloAPI.SchemaConfiguration {
  public static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? {
    // Implement this function to configure cache key resolution for your schema types.
    return nil
  }
  
  public static func cacheKey(for field: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> CacheKeyInfo? {
    return nil
  }
  
  public static func cacheKeys(for field: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> [CacheKeyInfo]? {
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
