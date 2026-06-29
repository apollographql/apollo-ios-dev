@_spi(Execution) @_spi(Internal) import ApolloAPI

/// How the cache reader resolves a `Selection.Field` to its value.
///
/// `@fieldPolicy` is a read-side redirect: it tells the reader how to
/// derive a `CacheReference` directly from the field's arguments, so the
/// reader can find the target record without going through the parent
/// record at all. Fields with no policy fall through to the standard
/// path — subscript the parent record under the field's normalized name.
///
/// The three cases capture this asymmetry explicitly:
///
/// - ``parentRecordKey(_:)`` — Standard, non-policy resolution. Subscript
///   the parent record under `name`; the value is whatever the writer
///   stored (a `CacheReference`, a scalar, a list, etc.).
/// - ``policyReference(_:)`` — `@fieldPolicy` applied. The reader
///   produces a `CacheReference(key)` directly. No parent-record
///   subscript. The writer is unaware of this path; it stores the entry
///   on the parent under the normalized field name (`@typePolicy` then
///   keys the child record under the same canonical key, so both
///   directives converge by user-coordinated design — see
///   <https://www.apollographql.com/docs/ios/caching/cache-key-resolution>).
/// - ``policyReferenceList(_:)`` — Like `policyReference`, but for
///   list-typed policy fields: the reader emits N direct references
///   into a list.
///
/// # Aligns with Apollo Kotlin
/// Apollo Kotlin's `FieldPolicyCacheResolver` returns a `CacheKey`
/// target directly when key arguments are present; only the
/// `DefaultCacheResolver` (no policy) performs parent-record lookup.
/// This enum encodes the same distinction in the Swift cache executor.
enum CacheReadStrategy {
  /// Standard read: subscript the parent record by `name`. Used for
  /// every field that does not have a `@fieldPolicy` /
  /// `FieldPolicy.Provider` redirect.
  case parentRecordKey(String)

  /// `@fieldPolicy` redirect: the field's value is a single
  /// `CacheReference(key)`, resolved directly from the field's
  /// arguments. The reader does not subscript the parent record.
  case policyReference(String)

  /// `@fieldPolicy` redirect for list-typed fields: the field's value
  /// is `[CacheReference(k1), CacheReference(k2), ...]`, resolved
  /// directly from the field's arguments.
  case policyReferenceList([String])
}

extension Selection.Field {

  /// Determines how the cache reader should resolve this field's value.
  /// Centralizes the policy-resolution rules so the resolver
  /// (`CacheDataExecutionSource.resolveCacheKey(with:on:)`) and the
  /// projection collector (`FieldProjectionCollector`) agree by
  /// construction on the read strategy for each field.
  ///
  /// Resolution order:
  /// 1. If the field's output type bottoms out at `.object(_)` and a
  ///    field policy applies (programmatic `FieldPolicy.Provider` first,
  ///    `@fieldPolicy` directive second), return ``CacheReadStrategy/policyReference(_:)``
  ///    or ``CacheReadStrategy/policyReferenceList(_:)`` with the
  ///    policy-derived key(s) formatted as `"\(uniqueKeyGroup ?? typename):\(id)"`.
  /// 2. Otherwise, return ``CacheReadStrategy/parentRecordKey(_:)`` with
  ///    `try cacheKey(with: variables)` — the field's normalized name on
  ///    its parent record (matches what the writer wrote).
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
  func cacheReadStrategy(
    variables: GraphQLOperation.Variables?,
    schema: (any SchemaMetadata.Type)?,
    responsePath: ResponsePath
  ) throws -> CacheReadStrategy {
    if let typename = objectFieldTypename,
       let policyResult = resolveCacheFieldPolicy(
         variables: variables,
         schema: schema,
         responsePath: responsePath
       ) {
      switch policyResult {
      case .single(let info):
        return .policyReference(formatPolicyCacheKey(info: info, typename: typename))
      case .list(let infos):
        return .policyReferenceList(infos.map { formatPolicyCacheKey(info: $0, typename: typename) })
      }
    }
    return .parentRecordKey(try cacheKey(with: variables))
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
