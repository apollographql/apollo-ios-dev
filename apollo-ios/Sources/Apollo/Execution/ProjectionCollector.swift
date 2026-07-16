@_spi(Execution) @_spi(Internal) import ApolloAPI

/// Walks a `[Selection]` tree for one level of a selection set and
/// emits the storage field names the cache should be asked to read for
/// one record at that level. This is the "Phase 1" half of ADR 0007
/// Principle 5's two-phase pattern: a caller traverses the selection
/// set up-front to collect a ``RecordProjection``, then issues a
/// single `loadFields(_:)` call against the cache, then resolves field
/// values from the returned data.
///
/// One `collectFieldNames` call describes exactly one record — the
/// caller composes the result with the record's cache key into a
/// ``RecordProjection``. Object/list fields are stored in the cache as
/// `CacheReference`s pointing at independent records, and the cache
/// keys of the child records aren't known until the parent's field
/// values are loaded — so projection collection cannot recurse past a
/// `.object`/`.customScalar`/scalar boundary. The caller drives the
/// per-level loop. (Nested-list `[[T]]` synthetic sub-records are an
/// exception, but they are reached via `child_key_value` resolution at
/// read time, not via projection-time recursion.)
///
/// # See Also
///
/// - [ADR 0007 — Selection-set-aware cache reads](../Design/adr/0007-selection-aware-cache-reads.md)
///   Principle 5 (upfront projection).
/// - `FieldSelectionCollector` — the analogous structure for the
///   executor's resolve path. This collector follows the same
///   `Selection` walk shape (via the shared `SelectionWalker`) so the
///   two paths stay in agreement about which fields each `Selection`
///   case contributes.
/// - ``RecordProjection`` — the value type composed from this
///   collector's output.
@_spi(Execution)
public enum ProjectionCollector {

  /// Collects the storage field names for one record at one level of a
  /// selection set. Duplicate selections of the same field across
  /// multiple fragments collapse into one name.
  ///
  /// - Parameters:
  ///   - selections: The selections at this level (typically a
  ///     `SelectionSet.__selections` or a fragment's `.__selections`).
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
  ///     `CacheDataExecutionSource` when projecting fields for a child
  ///     record whose `__typename` isn't yet loaded: every type case's
  ///     fields are projected (an "over-fetch"); the executor's actual
  ///     traversal still uses the loaded `__typename` to select which
  ///     type case applies, so only the matching type case's fields
  ///     are surfaced to the response. Defaults to `false` for the
  ///     conservative collect-by-known-type semantics.
  ///   - schema: The `SchemaMetadata.Type` for the operation being
  ///     read. Used to resolve *programmatic* field policies
  ///     (`SchemaConfiguration: FieldPolicy.Provider`) — if a field
  ///     has a configured programmatic policy, the parent record
  ///     stores the field reference under the policy-derived name
  ///     (e.g. `"Hero:1"`) rather than the standard
  ///     `field.cacheKey(with:)` name, and the collector must emit
  ///     names matching the stored name. Pass `nil` (the default)
  ///     when the caller doesn't have schema context — only the
  ///     directive-based `@fieldPolicy` is then honored.
  ///   - responsePath: The response path of the *object* whose fields
  ///     are being projected — the path that the executor uses for
  ///     `FieldPolicy.Provider`'s `path:` argument when resolving
  ///     programmatic policies. Defaults to empty; most providers
  ///     don't consult it.
  /// - Returns: The storage field names to request from the cache for
  ///   this record at this level.
  public static func collectFieldNames(
    selections: [Selection],
    variables: GraphQLOperation.Variables?,
    resolveRuntimeType: () -> Object?,
    includeAllInlineFragments: Bool = false,
    schema: (any SchemaMetadata.Type)? = nil,
    responsePath: ResponsePath = []
  ) throws -> Set<String> {
    var fieldNames: Set<String> = []
    // `SelectionWalker` owns the case dispatch. The projection path
    // differs from `DefaultFieldSelectionCollector` only in the
    // per-field action and the policy choices:
    //
    //  - `inlineFragmentPolicy`: when the receiving record's
    //    `__typename` isn't yet loaded (typical on the projection-time
    //    pre-pass driven by `CacheDataExecutionSource`), the caller
    //    passes `includeAllInlineFragments: true`, which selects
    //    `.includeAll`. The resulting field-name set over-fetches every
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
    // No fragment-tracking callbacks: the field-name set carries
    // everything downstream needs. The fulfilled/deferred-fragment
    // bookkeeping that the resolve path maintains is irrelevant here.
    try SelectionWalker.walk(
      selections,
      variables: variables,
      resolveRuntimeType: resolveRuntimeType,
      inlineFragmentPolicy: includeAllInlineFragments ? .includeAll : .byRuntimeType,
      deferredFragmentPolicy: .eager,
      onField: { field in
        try collectField(
          field,
          into: &fieldNames,
          variables: variables,
          schema: schema,
          responsePath: responsePath
        )
      }
    )
    return fieldNames
  }

  // MARK: - Per-field collection

  /// Emits the storage field name(s) for one `.field` selection. For
  /// fields resolved via `@fieldPolicy` (`.policyReference` /
  /// `.policyReferenceList`), no parent-record field is needed — the
  /// reader returns a direct `CacheReference` and the next-level read
  /// loads the policy-referenced record under its canonical key. See
  /// `CacheDataExecutionSource.resolveCacheKey` for the matching
  /// resolve-time switch.
  private static func collectField(
    _ field: Selection.Field,
    into fieldNames: inout Set<String>,
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
      fieldNames.insert(name)
    case .policyReference, .policyReferenceList:
      // No parent-record field: the field's value is a direct
      // `CacheReference` derived from the field's arguments.
      break
    }
  }

}
