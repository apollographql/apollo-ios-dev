@_spi(Execution) import ApolloAPI

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
  /// - Returns: The projections to request from the cache for this
  ///   record at this level.
  public static func collect(
    selections: [Selection],
    cacheKey: CacheKey,
    variables: GraphQLOperation.Variables?,
    resolveRuntimeType: () -> Object?
  ) throws -> Set<FieldProjection> {
    var projections: Set<FieldProjection> = []
    try walk(
      selections,
      into: &projections,
      cacheKey: cacheKey,
      variables: variables,
      resolveRuntimeType: resolveRuntimeType
    )
    return projections
  }

  // MARK: - Selection walk

  /// Mirrors the `Selection` case handling in
  /// `DefaultFieldSelectionCollector.collectFields(...)` so the
  /// upfront-projection path and the lazy-resolution path always agree
  /// on which fields each Selection case contributes. Differences from
  /// the default collector:
  ///
  /// - The output is a flat `Set<FieldProjection>` keyed by
  ///   `(cacheKey, fieldName, columnShape, cardinality)`, not a
  ///   `FieldSelectionGrouping` of `FieldExecutionInfo`. The collector
  ///   doesn't need response-key grouping because cache rows are
  ///   keyed by cache-field-key, not by response key, and the cache
  ///   read doesn't need to know about fragment fulfillment state.
  /// - There's no separate "fulfilled fragment" bookkeeping. The
  ///   collector enters every fulfilled fragment and inline fragment
  ///   to collect its inner fields; downstream callers don't need a
  ///   fulfilled-set output because the projections themselves carry
  ///   the necessary `(cacheKey, fieldName)` pairs.
  /// - `.deferred` fragments are handled identically to the cache's
  ///   existing executor behavior: the executor sets
  ///   `shouldAttemptDeferredFragmentExecution = true` for
  ///   `CacheDataExecutionSource`, so all deferred fragments are
  ///   eagerly entered here (subject to the deferred condition).
  ///   This keeps cache reads complete on a cold read; the executor
  ///   ignores deferred-fragment incrementality on the cache path.
  private static func walk(
    _ selections: [Selection],
    into projections: inout Set<FieldProjection>,
    cacheKey: CacheKey,
    variables: GraphQLOperation.Variables?,
    resolveRuntimeType: () -> Object?
  ) throws {
    for selection in selections {
      switch selection {
      case .field(let field):
        let fieldName = try field.cacheKey(with: variables)
        projections.insert(FieldProjection(
          cacheKey: cacheKey,
          fieldName: fieldName,
          outputType: field.type
        ))

      case .conditional(let conditions, let nested):
        if conditions.evaluate(with: variables) {
          try walk(
            nested,
            into: &projections,
            cacheKey: cacheKey,
            variables: variables,
            resolveRuntimeType: resolveRuntimeType
          )
        }

      case .fragment(let fragmentType):
        try walk(
          fragmentType.__selections,
          into: &projections,
          cacheKey: cacheKey,
          variables: variables,
          resolveRuntimeType: resolveRuntimeType
        )

      case .inlineFragment(let typeCase):
        if let runtimeType = resolveRuntimeType(),
           typeCase.__parentType.canBeConverted(from: runtimeType) {
          try walk(
            typeCase.__selections,
            into: &projections,
            cacheKey: cacheKey,
            variables: variables,
            resolveRuntimeType: resolveRuntimeType
          )
        }

      case .deferred(_, let typeCase, _):
        // The cache executor path treats deferred fragments as fully
        // fulfilled regardless of the `@defer(if:)` condition: it
        // has no incremental delivery channel to honor `@defer`, so
        // `CacheDataExecutionSource` sets
        // `shouldAttemptDeferredFragmentExecution = true` and
        // `GraphQLExecutor` eagerly executes the deferred fragment's
        // selections after the normal grouping pass. Mirror that
        // behavior here so the collected projection set is complete
        // for the level — every deferred fragment's fields are
        // projected. The `if:` condition only controls *whether* the
        // fragment is deferred (yes/no); under the cache path the
        // fields are read in either branch.
        try walk(
          typeCase.__selections,
          into: &projections,
          cacheKey: cacheKey,
          variables: variables,
          resolveRuntimeType: resolveRuntimeType
        )
      }
    }
  }
}
