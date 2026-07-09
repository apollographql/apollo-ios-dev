@_spi(Execution) @_spi(Internal) import ApolloAPI

/// The cache field name(s) a `Selection.Field` reads from / writes to
/// on its parent record. Either a single name (the common case: a
/// non-policy field, or a `.single` field-policy result) or a list of
/// names (a `.list` field-policy result, where the parent stores N
/// child references under N distinct names).
///
/// The discriminator matters at the resolver: a `.single` field reads
/// one value out of the parent record; a `.list` field reads N values
/// and aggregates them into an array.
enum CacheFieldKey {
  case single(String)
  case list([String])

  /// Flattens both cases into their underlying name(s) — useful for
  /// the projection-collection path, which emits one projection per
  /// stored name regardless of `.single`/`.list` shape.
  var allNames: [String] {
    switch self {
    case .single(let name): return [name]
    case .list(let names): return names
    }
  }
}

extension Selection.Field {

  /// Resolves the cache field name(s) the parent record stores this
  /// field's value under. Centralizes the policy-resolution rules
  /// shared between `CacheDataExecutionSource.resolveCacheKey(with:on:)`
  /// (read time) and `FieldProjectionCollector` (projection time):
  ///
  /// 1. If the field's output type bottoms out at `.object(_)` AND a
  ///    field policy applies (programmatic via
  ///    `FieldPolicy.Provider`, falling back to the `@fieldPolicy`
  ///    directive), the result is the policy-derived name(s)
  ///    formatted as `"\(uniqueKeyGroup ?? typename):\(id)"`.
  /// 2. Otherwise, the result is `.single` of
  ///    `try cacheKey(with: variables)` — the standard composition
  ///    of field name plus argument hash.
  ///
  /// Both callers compute the same name(s) for the same
  /// `(field, variables, schema, path)` — projection and resolution
  /// stay in agreement by construction, so the cache load fetches
  /// what the resolver will subscript for.
  ///
  /// - Parameters:
  ///   - variables: Operation variables, used to evaluate field
  ///     policies and to compose the standard cache key.
  ///   - schema: The `SchemaMetadata.Type` for the operation —
  ///     consulted for programmatic `FieldPolicy.Provider`
  ///     resolution. Pass `nil` when the caller doesn't have schema
  ///     context (only the directive-based `@fieldPolicy` is then
  ///     honored).
  ///   - responsePath: The response path passed to
  ///     `FieldPolicy.Provider.cacheKey(...)` /
  ///     `cacheKeyList(...)`. Most providers don't consult it.
  func cacheFieldKey(
    variables: GraphQLOperation.Variables?,
    schema: (any SchemaMetadata.Type)?,
    responsePath: ResponsePath
  ) throws -> CacheFieldKey {
    if let typename = objectFieldTypename,
       let policyResult = resolveCacheFieldPolicy(
         variables: variables,
         schema: schema,
         responsePath: responsePath
       ) {
      switch policyResult {
      case .single(let info):
        return .single(formatPolicyCacheKey(info: info, typename: typename))
      case .list(let infos):
        return .list(infos.map { formatPolicyCacheKey(info: $0, typename: typename) })
      }
    }
    return .single(try cacheKey(with: variables))
  }

  /// The typename used to format a policy-derived cache field name.
  /// Returns the named-type `__typename` of this field's output type
  /// if it bottoms out at `.object(_)`; otherwise `nil` (no policy
  /// applies because there's no target object).
  private var objectFieldTypename: String? {
    switch type.namedType {
    case .object(let selectionSetType):
      return selectionSetType.__parentType.__typename
    default:
      return nil
    }
  }

  /// Programmatic `FieldPolicy.Provider` first, falling back to the
  /// `@fieldPolicy` directive. Order matches
  /// `CacheDataExecutionSource.resolveCacheKey(with:on:)`.
  private func resolveCacheFieldPolicy(
    variables: GraphQLOperation.Variables?,
    schema: (any SchemaMetadata.Type)?,
    responsePath: ResponsePath
  ) -> FieldPolicyResult? {
    if let result = programmaticPolicyResult(
      type: type,
      variables: variables,
      schema: schema,
      responsePath: responsePath
    ) {
      return result
    }
    return FieldPolicyDirectiveEvaluator(
      field: self,
      variables: variables
    )?.resolveFieldPolicy()
  }

  /// Peels `.nonNull`, dispatches to `provider.cacheKeyList(...)` for
  /// `.list` output types and `provider.cacheKey(...)` otherwise.
  private func programmaticPolicyResult(
    type: Selection.Field.OutputType,
    variables: GraphQLOperation.Variables?,
    schema: (any SchemaMetadata.Type)?,
    responsePath: ResponsePath
  ) -> FieldPolicyResult? {
    guard let schema,
          let provider = schema.configuration.self as? (any FieldPolicy.Provider.Type),
          let arguments = arguments
    else {
      return nil
    }

    switch type {
    case .nonNull(let inner):
      return programmaticPolicyResult(
        type: inner,
        variables: variables,
        schema: schema,
        responsePath: responsePath
      )
    case .list:
      if let keys = provider.cacheKeyList(
        for: FieldPolicy.Field(self),
        inputData: FieldPolicy.InputData(
          _rawType: .inputValue(arguments),
          _variables: variables
        ),
        path: responsePath
      ) {
        return .list(keys)
      }
      return nil
    default:
      if let key = provider.cacheKey(
        for: FieldPolicy.Field(self),
        inputData: FieldPolicy.InputData(
          _rawType: .inputValue(arguments),
          _variables: variables
        ),
        path: responsePath
      ) {
        return .single(key)
      }
      return nil
    }
  }

  /// Mirrors the formatting in
  /// `CacheDataExecutionSource.formatCacheKey(withInfo:andTypename:)`.
  private func formatPolicyCacheKey(
    info: CacheKeyInfo,
    typename: String
  ) -> String {
    "\(info.uniqueKeyGroup ?? typename):\(info.id)"
  }
}
