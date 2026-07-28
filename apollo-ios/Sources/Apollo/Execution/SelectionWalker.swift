@_spi(Execution) import ApolloAPI

/// Shared dispatch over a `[Selection]` tree, parameterized by per-case
/// policies. Both `DefaultFieldSelectionCollector` (the resolve path)
/// and `ProjectionCollector` (the projection path) traverse the
/// same `Selection` shape with the same conditional/fragment/inline-
/// fragment/deferred branches — they differ only in:
///
/// 1. What they do per `.field` (append to a grouping vs emit a
///    `RecordProjection`).
/// 2. Whether `.inlineFragment` requires runtime-type matching
///    (`TypeCaseProjection.byRuntimeType`) or enters unconditionally
///    (`.allTypeCases`, the cache projection's over-fetch strategy —
///    see `TypeCaseProjection` for the trade-off).
/// 3. Whether `.deferred` honors its `@defer(if:)` condition
///    (`respectDeferCondition`, the normal resolve path) or always
///    enters (`eager`, the cache path where there's no incremental
///    delivery to honor).
///
/// `SelectionWalker.walk(_:)` collapses the dispatch into one place;
/// callers supply policies and per-event closures. Tracking side
/// effects (fulfilled/deferred fragment sets, projection accumulators)
/// happen inside the caller-supplied closures, which capture whatever
/// state the caller needs.
///
/// All closure parameters are non-escaping so callers can mutate
/// `inout` accumulators from within them; pass `{ _ in }` for entry
/// events the caller doesn't need to observe.
///
/// # See Also
///
/// - [ADR 0007 — Selection-set-aware cache reads](../../../Design/adr/0007-selection-aware-cache-reads.md)
///   PR-009d-iv (this extraction); lands before PR-009f so the
///   dependency tracker's invalidation walk can use the unified helper.
enum SelectionWalker {

  /// Gating policy for `.deferred` cases.
  enum DeferredFragmentPolicy {
    /// Honor the `@defer(if:)` condition. When the condition is `nil`
    /// (no `if:`) or evaluates to `true`, the fragment is *deferred*:
    /// the walker calls `onDeferredFragmentSkipped` and does not
    /// recurse into the fragment's selections. When it evaluates to
    /// `false`, the fragment is treated as fulfilled:
    /// `onDeferredFragmentEntered` is called and the walker recurses.
    case respectDeferCondition

    /// Treat every deferred fragment as if `@defer` did not apply —
    /// always call `onDeferredFragmentEntered` and recurse. Used by
    /// the cache path: `CacheDataExecutionSource` sets
    /// `shouldAttemptDeferredFragmentExecution = true`, so reads
    /// surface every deferred fragment eagerly.
    case eager
  }

  /// Walks `selections` and dispatches each case. Recursion is
  /// internal; callers are not expected to call `walk` again from
  /// their closures.
  ///
  /// - Parameters:
  ///   - selections: The selection tree to walk at this level.
  ///   - variables: Operation variables. Used to evaluate
  ///     `.conditional`'s `@include`/`@skip` and `.deferred`'s
  ///     `@defer(if:)` conditions.
  ///   - typeCases: Gating policy for `.inlineFragment` entry — see
  ///     ``TypeCaseProjection``. Under `.byRuntimeType`, the case's
  ///     resolver is called lazily the first time an inline fragment
  ///     is encountered; under `.allTypeCases`, every inline fragment
  ///     is entered.
  ///   - deferredFragmentPolicy: See ``DeferredFragmentPolicy``.
  ///   - onField: Called once per `.field` selection reached.
  ///   - onFragmentEntered: Called immediately before recursing into
  ///     a named `.fragment`'s selections. Pass `{ _ in }` if the
  ///     dispatch is fragment-tracking-agnostic.
  ///   - onInlineFragmentEntered: Called immediately before recursing
  ///     into an `.inlineFragment`'s selections — only after the
  ///     policy gate has approved entry.
  ///   - onDeferredFragmentEntered: Called immediately before
  ///     recursing into a `.deferred` fragment's selections — only
  ///     when the policy decides to enter (always under `.eager`, or
  ///     when the condition evaluates to `false` under
  ///     `.respectDeferCondition`).
  ///   - onDeferredFragmentSkipped: Called when a `.deferred` fragment
  ///     is encountered but recursion is skipped because the policy
  ///     treats it as still-deferred. Only fires under
  ///     `.respectDeferCondition` when the condition holds.
  static func walk(
    _ selections: [Selection],
    variables: GraphQLOperation.Variables?,
    typeCases: TypeCaseProjection,
    deferredFragmentPolicy: DeferredFragmentPolicy,
    onField: (Selection.Field) throws -> Void,
    onFragmentEntered: (any Fragment.Type) throws -> Void = { _ in },
    onInlineFragmentEntered: (any InlineFragment.Type) throws -> Void = { _ in },
    onDeferredFragmentEntered: (any Deferrable.Type) throws -> Void = { _ in },
    onDeferredFragmentSkipped: (any Deferrable.Type) throws -> Void = { _ in }
  ) throws {
    // The receiving object's runtime type is constant for the whole
    // walk, so `.byRuntimeType`'s resolver runs at most once even
    // when multiple inline fragments are encountered.
    // `.some(nil)` = resolved to nil; `nil` = not yet resolved.
    var resolvedRuntimeType: Object?? = nil
    try walk(
      selections,
      variables: variables,
      typeCases: typeCases,
      deferredFragmentPolicy: deferredFragmentPolicy,
      resolvedRuntimeType: &resolvedRuntimeType,
      onField: onField,
      onFragmentEntered: onFragmentEntered,
      onInlineFragmentEntered: onInlineFragmentEntered,
      onDeferredFragmentEntered: onDeferredFragmentEntered,
      onDeferredFragmentSkipped: onDeferredFragmentSkipped
    )
  }

  private static func walk(
    _ selections: [Selection],
    variables: GraphQLOperation.Variables?,
    typeCases: TypeCaseProjection,
    deferredFragmentPolicy: DeferredFragmentPolicy,
    resolvedRuntimeType: inout Object??,
    onField: (Selection.Field) throws -> Void,
    onFragmentEntered: (any Fragment.Type) throws -> Void,
    onInlineFragmentEntered: (any InlineFragment.Type) throws -> Void,
    onDeferredFragmentEntered: (any Deferrable.Type) throws -> Void,
    onDeferredFragmentSkipped: (any Deferrable.Type) throws -> Void
  ) throws {
    for selection in selections {
      switch selection {
      case let .field(field):
        try onField(field)

      case let .conditional(conditions, nested):
        if conditions.evaluate(with: variables) {
          try walk(
            nested,
            variables: variables,
            typeCases: typeCases,
            deferredFragmentPolicy: deferredFragmentPolicy,
            resolvedRuntimeType: &resolvedRuntimeType,
            onField: onField,
            onFragmentEntered: onFragmentEntered,
            onInlineFragmentEntered: onInlineFragmentEntered,
            onDeferredFragmentEntered: onDeferredFragmentEntered,
            onDeferredFragmentSkipped: onDeferredFragmentSkipped
          )
        }

      case let .fragment(fragment):
        try onFragmentEntered(fragment)
        try walk(
          fragment.__selections,
          variables: variables,
          typeCases: typeCases,
          deferredFragmentPolicy: deferredFragmentPolicy,
          resolvedRuntimeType: &resolvedRuntimeType,
          onField: onField,
          onFragmentEntered: onFragmentEntered,
          onInlineFragmentEntered: onInlineFragmentEntered,
          onDeferredFragmentEntered: onDeferredFragmentEntered,
          onDeferredFragmentSkipped: onDeferredFragmentSkipped
        )

      case let .inlineFragment(typeCase):
        let shouldEnter: Bool
        switch typeCases {
        case .allTypeCases:
          shouldEnter = true
        case .byRuntimeType(let resolveRuntimeType):
          let runtimeType: Object?
          if let resolved = resolvedRuntimeType {
            runtimeType = resolved
          } else {
            runtimeType = resolveRuntimeType()
            resolvedRuntimeType = .some(runtimeType)
          }
          if let runtimeType,
             typeCase.__parentType.canBeConverted(from: runtimeType) {
            shouldEnter = true
          } else {
            shouldEnter = false
          }
        }
        if shouldEnter {
          try onInlineFragmentEntered(typeCase)
          try walk(
            typeCase.__selections,
            variables: variables,
            typeCases: typeCases,
            deferredFragmentPolicy: deferredFragmentPolicy,
            resolvedRuntimeType: &resolvedRuntimeType,
            onField: onField,
            onFragmentEntered: onFragmentEntered,
            onInlineFragmentEntered: onInlineFragmentEntered,
            onDeferredFragmentEntered: onDeferredFragmentEntered,
            onDeferredFragmentSkipped: onDeferredFragmentSkipped
          )
        }

      case let .deferred(condition, typeCase, _):
        let shouldEnter: Bool
        switch deferredFragmentPolicy {
        case .eager:
          shouldEnter = true
        case .respectDeferCondition:
          // The Apollo Router + Server implementation of deferSpec
          // 20220824 honors every `@defer`. When the condition is
          // present and evaluates to `false`, the fragment is
          // considered fulfilled rather than deferred — the walker
          // enters it. When the condition is absent or evaluates
          // to `true`, the fragment stays deferred and the walker
          // skips recursion (the caller can still record it as
          // deferred via `onDeferredFragmentSkipped`).
          if let condition, !condition.evaluate(with: variables) {
            shouldEnter = true
          } else {
            shouldEnter = false
          }
        }
        if shouldEnter {
          try onDeferredFragmentEntered(typeCase)
          try walk(
            typeCase.__selections,
            variables: variables,
            typeCases: typeCases,
            deferredFragmentPolicy: deferredFragmentPolicy,
            resolvedRuntimeType: &resolvedRuntimeType,
            onField: onField,
            onFragmentEntered: onFragmentEntered,
            onInlineFragmentEntered: onInlineFragmentEntered,
            onDeferredFragmentEntered: onDeferredFragmentEntered,
            onDeferredFragmentSkipped: onDeferredFragmentSkipped
          )
        } else {
          try onDeferredFragmentSkipped(typeCase)
        }
      }
    }
  }
}
