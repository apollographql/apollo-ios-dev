@_spi(Execution) @_spi(Internal) import ApolloAPI

/// Walks a `[Selection]` tree for one level of a selection set and emits
/// the `FieldProjection`s the cache should be asked to read for that
/// level. This is the "Phase 1" half of ADR 0007 Principle 5's two-phase
/// pattern: a caller traverses the selection set up-front to collect
/// projections, then issues a single `loadFields(_:)` call against the
/// cache, then resolves field values from the returned data.
///
/// Why one level at a time: object/list fields are stored in the cache
/// as `CacheReference`s pointing at independent records. The cache keys
/// of the child records aren't known until the parent's field values
/// are loaded — so projection collection cannot recurse past a
/// `.object`/`.customScalar`/scalar boundary. The caller drives the
/// per-level loop. (Nested-list `[[T]]` synthetic sub-records are an
/// exception, but they are reached via `child_key_value` resolution at
/// read time, not via projection-time recursion.)
///
/// # See Also
///
/// - [ADR 0007 — Selection-set-aware cache reads](../Design/adr/0007-selection-aware-cache-reads.md)
///   Principle 5 (upfront projection); Principle 1 (per-field type info).
/// - `FieldSelectionCollector` — the analogous structure for the
///   existing lazy-resolution executor path. This collector follows the
///   same `Selection` walk shape so the two paths stay in agreement
///   about which fields each `Selection` case contributes.
/// - `FieldProjection` (PR-009b) — the value type this collector emits.
@_spi(Execution)
public enum FieldProjectionCollector {

  /// Collects field projections for one record at one level of a
  /// selection set. Returns the projections deduplicated by their
  /// natural `Hashable` identity — duplicate selections of the same
  /// field across multiple fragments collapse into one projection.
  ///
  /// - Parameters:
  ///   - selections: The selections at this level (typically a
  ///     `SelectionSet.__selections` or a fragment's `.__selections`).
  ///   - cacheKey: The cache key of the record whose fields are being
  ///     projected. The same cache key is used for every projection
  ///     emitted by one call — the caller invokes this method again
  ///     for each distinct child record discovered when resolving the
  ///     returned projections.
  ///   - variables: Operation variables, used to evaluate
  ///     `@include`/`@skip` conditionals on `.conditional` selections
  ///     and to compose the cache field key for fields with arguments.
  ///   - resolveRuntimeType: Returns the runtime `Object` type of the
  ///     record being projected, used to gate `.inlineFragment`
  ///     traversal. Passed as a closure so callers can defer resolving
  ///     `__typename` from the record (or whatever source they have)
  ///     until an inline fragment is actually encountered. Return
  ///     `nil` to skip every inline fragment.
  ///   - includeAllInlineFragments: When `true`, every
  ///     `.inlineFragment` is entered regardless of `resolveRuntimeType`
  ///     — the closure is not invoked. Used by the pre-load path in
  ///     `CacheDataExecutionSource` (PR-009d-ii) when projecting
  ///     fields for a child record whose `__typename` isn't yet
  ///     loaded: every type case's fields are projected
  ///     (an "over-fetch"); the executor's actual traversal still
  ///     uses the loaded `__typename` to select which type case
  ///     applies, so only the matching type case's fields are
  ///     surfaced to the response. Defaults to `false` for the
  ///     conservative collect-by-known-type semantics.
  ///   - schema: The `SchemaMetadata.Type` for the operation being
  ///     read. Used to resolve *programmatic* field policies
  ///     (`SchemaConfiguration: FieldPolicy.Provider`) — if a field
  ///     has a configured programmatic policy, the parent record
  ///     stores the field reference under the policy-derived name
  ///     (e.g. `"Hero:1"`) rather than the standard
  ///     `field.cacheKey(with:)` name, and the collector must emit
  ///     projections matching the stored name. Pass `nil` (the
  ///     default) when the caller doesn't have schema context — only
  ///     the directive-based `@fieldPolicy` is then honored.
  ///   - responsePath: The response path of the *object* whose fields
  ///     are being projected — the path that the executor uses for
  ///     `FieldPolicy.Provider`'s `path:` argument when resolving
  ///     programmatic policies. Defaults to empty; most providers
  ///     don't consult it.
  /// - Returns: The projections to request from the cache for this
  ///   record at this level.
  public static func collect(
    selections: [Selection],
    cacheKey: CacheKey,
    variables: GraphQLOperation.Variables?,
    resolveRuntimeType: () -> Object?,
    includeAllInlineFragments: Bool = false,
    schema: (any SchemaMetadata.Type)? = nil,
    responsePath: ResponsePath = []
  ) throws -> Set<FieldProjection> {
    var projections: Set<FieldProjection> = []
    // `SelectionWalker` owns the case dispatch — see PR-009d-iv. The
    // projection path differs from `DefaultFieldSelectionCollector` only
    // in the per-field action and the policy choices:
    //
    //  - `inlineFragmentPolicy`: when the receiving record's
    //    `__typename` isn't yet loaded (typical on the projection-time
    //    pre-pass driven by `CacheDataExecutionSource`), the caller
    //    passes `includeAllInlineFragments: true`, which selects
    //    `.includeAll`. The resulting projection set over-fetches every
    //    type case's fields; the executor's later, type-aware traversal
    //    surfaces only the matching type case to the response. The
    //    over-fetch is an accepted cost per ADR 0007; narrowing it at
    //    the SQL layer (a `__typename`-aware filter) is a deferred
    //    optimization gated on the Phase 1A performance results.
    //
    //  - `deferredFragmentPolicy: .eager` because the cache path has no
    //    incremental delivery channel — `CacheDataExecutionSource` sets
    //    `shouldAttemptDeferredFragmentExecution = true` and the
    //    executor eagerly resolves deferred fragments on cache reads.
    //
    // No fragment-tracking callbacks: the projection set carries
    // everything downstream needs by `(cacheKey, fieldName)`. The
    // fulfilled/deferred-fragment bookkeeping that the resolve path
    // maintains is irrelevant here.
    try SelectionWalker.walk(
      selections,
      variables: variables,
      resolveRuntimeType: resolveRuntimeType,
      inlineFragmentPolicy: includeAllInlineFragments ? .includeAll : .byRuntimeType,
      deferredFragmentPolicy: .eager,
      onField: { field in
        try collectField(
          field,
          into: &projections,
          cacheKey: cacheKey,
          variables: variables,
          schema: schema,
          responsePath: responsePath
        )
      }
    )
    return projections
  }

  // MARK: - Per-field projection

  /// Emits the projection(s) for one `.field` selection. For fields
  /// resolved via `@fieldPolicy` (`.policyReference` /
  /// `.policyReferenceList`), no parent-record projection is needed —
  /// the reader returns a direct `CacheReference` and the next-level
  /// read loads the policy-referenced record under its canonical key.
  /// See `CacheDataExecutionSource.resolveCacheKey` for the matching
  /// resolve-time switch.
  private static func collectField(
    _ field: Selection.Field,
    into projections: inout Set<FieldProjection>,
    cacheKey: CacheKey,
    variables: GraphQLOperation.Variables?,
    schema: (any SchemaMetadata.Type)?,
    responsePath: ResponsePath
  ) throws {
    let strategy = try field.cacheReadStrategy(
      variables: variables,
      schema: schema,
      responsePath: responsePath
    )
    switch strategy {
    case .parentRecordField(let name):
      projections.insert(FieldProjection(
        cacheKey: cacheKey,
        fieldName: name
      ))
    case .policyReference, .policyReferenceList:
      // No parent-record projection: the field's value is a direct
      // `CacheReference` derived from the field's arguments.
      break
    }
  }

}
