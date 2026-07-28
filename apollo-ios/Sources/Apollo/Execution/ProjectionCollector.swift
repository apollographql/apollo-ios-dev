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

  /// How the collector treats `.inlineFragment` type cases while
  /// walking. Modeled as an explicit policy because the choice
  /// encodes a real cost trade-off, not just a traversal detail.
  public enum TypeCaseProjection {
    /// Project every type case's fields, regardless of the record's
    /// runtime type. Used when the record hasn't been loaded yet and
    /// its `__typename` is unknown — the pre-load projection pass in
    /// `ApolloStore.ReadTransaction.loadObject` — where walking by
    /// runtime type is impossible.
    ///
    /// **This over-fetches.** Fields of type cases the record turns
    /// out not to match *are* requested from the cache and fetched;
    /// the executor's type-aware resolve pass discards them from the
    /// response (correctness), but the fetch cost is paid today.
    /// Accepted per ADR 0007's amended decision; a SQL-level
    /// `__typename` filter that would drop the unmatched rows before
    /// they cross the wire is a deferred optimization gated on the
    /// Phase 1A performance results (ADR 0007 § Amendments).
    case allTypeCases

    /// Enter only the type cases matching the record's runtime type,
    /// resolved lazily via the closure the first time an inline
    /// fragment is encountered. Return `nil` to skip every inline
    /// fragment. Used when the caller already has the record (and
    /// its `__typename`) in hand.
    case byRuntimeType(() -> Object?)
  }

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
  ///   - typeCases: How `.inlineFragment` type cases are treated —
  ///     see ``TypeCaseProjection``. Pass `.allTypeCases` for the
  ///     pre-load path where the record's runtime type is unknown
  ///     (the documented over-fetch), or `.byRuntimeType(_:)` when
  ///     the runtime type can be resolved.
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
    typeCases: TypeCaseProjection,
    schema: (any SchemaMetadata.Type)? = nil,
    responsePath: ResponsePath = []
  ) throws -> Set<String> {
    let inlineFragmentPolicy: SelectionWalker.InlineFragmentPolicy
    let resolveRuntimeType: () -> Object?
    switch typeCases {
    case .allTypeCases:
      inlineFragmentPolicy = .includeAll
      resolveRuntimeType = { nil }
    case .byRuntimeType(let resolver):
      inlineFragmentPolicy = .byRuntimeType
      resolveRuntimeType = resolver
    }

    var fieldNames: Set<String> = []
    // `SelectionWalker` owns the case dispatch. The projection path
    // differs from `DefaultFieldSelectionCollector` only in the
    // per-field action and the policy choices:
    //
    //  - `inlineFragmentPolicy`: derived from `typeCases` above; see
    //    `TypeCaseProjection` for the over-fetch trade-off that
    //    `.allTypeCases` accepts.
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
      inlineFragmentPolicy: inlineFragmentPolicy,
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
