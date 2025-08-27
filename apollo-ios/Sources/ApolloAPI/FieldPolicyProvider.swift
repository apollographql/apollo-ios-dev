public protocol FieldPolicyProvider {
  /// The entry point for resolving cache keys to read objects from the `NormalizedCache` when executing an operation,
  /// prior to attempting to fetch data from the network.
  ///
  /// The default generated implementation always returns `nil`, disabling all cache normalization.
  ///
  /// This function returns an array containing 1 or more cache key strings depending on the return type of the given field.
  static func cacheKey(for field: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> CacheKeyInfo?
  
  static func cacheKeys(for field: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> [CacheKeyInfo]?
}
