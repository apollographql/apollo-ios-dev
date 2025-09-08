// @generated
// This file was automatically generated and can be edited to
// provide custom configuration for a generated GraphQL schema.
//
// Any changes to this file will not be overwritten by future
// code generation execution.

import ApolloAPI

public enum SchemaConfiguration: ApolloAPI.SchemaConfiguration {
  public static func cacheKey(for field: ApolloAPI.Selection.Field, variables: [String : any ApolloAPI.GraphQLOperationVariableValue]?, path: ApolloAPI.ResponsePath) -> ApolloAPI.CacheKeyInfo? {
    return nil
  }
  
  public static func cacheKeyList(for listField: ApolloAPI.Selection.Field, variables: [String : any ApolloAPI.GraphQLOperationVariableValue]?, path: ApolloAPI.ResponsePath) -> [ApolloAPI.CacheKeyInfo]? {
    return nil
  }
  
  public static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? {
    // Implement this function to configure cache key resolution for your schema types.
    return nil
  }
}
