@_spi(Execution) import ApolloAPI

/// Shared dispatch over a `[Selection]` tree, parameterized by per-case
/// policies. Both `DefaultFieldSelectionCollector` (the resolve path)
/// and `FieldProjectionCollector` (the projection path) traverse the
/// same `Selection` shape with the same conditional/fragment/inline-
/// fragment/deferred branches — they differ only in:
///
/// 1. What they do per `.field` (append to a grouping vs emit a
///    `FieldProjection`).
/// 2. Whether `.inlineFragment` requires runtime-type matching
///    (`byRuntimeType`) or enters unconditionally (`includeAll`, the
///    cache projection's over-fetch strategy — the executor's later
///    selection-set traversal still uses the loaded `__typename` to
///    pick the matching type case).
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

  /// Gating policy for `.inlineFragment` cases.
  enum InlineFragmentPolicy {
    /// Enter the inline fragment only when the receiving object's
    /// runtime type can be converted to the fragment's parent type.
    /// `resolveRuntimeType()` is called lazily once an inline fragment
    /// is encountered; if it returns `nil`, the fragment is skipped.
    case byRuntimeType

    /// Enter every inline fragment unconditionally. Used by the cache
    /// projection path when the receiving object's `__typename` is not
    /// yet loaded: every type case's fields are projected. The
    /// executor's later, type-aware traversal still picks the matching
    /// type case from the loaded data.
    case includeAll
  }

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
  ///   - resolveRuntimeType: Lazily resolves the receiving object's
  ///     runtime `Object` type, used by `.byRuntimeType` to gate
  ///     `.inlineFragment` entry. Not called under `.includeAll`.
  ///   - inlineFragmentPolicy: See ``InlineFragmentPolicy``.
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
    resolveRuntimeType: () -> Object?,
    inlineFragmentPolicy: InlineFragmentPolicy,
    deferredFragmentPolicy: DeferredFragmentPolicy,
    onField: (Selection.Field) throws -> Void,
    onFragmentEntered: (any Fragment.Type) throws -> Void = { _ in },
    onInlineFragmentEntered: (any InlineFragment.Type) throws -> Void = { _ in },
    onDeferredFragmentEntered: (any Deferrable.Type) throws -> Void = { _ in },
    onDeferredFragmentSkipped: (any Deferrable.Type) throws -> Void = { _ in }
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
            resolveRuntimeType: resolveRuntimeType,
            inlineFragmentPolicy: inlineFragmentPolicy,
            deferredFragmentPolicy: deferredFragmentPolicy,
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
          resolveRuntimeType: resolveRuntimeType,
          inlineFragmentPolicy: inlineFragmentPolicy,
          deferredFragmentPolicy: deferredFragmentPolicy,
          onField: onField,
          onFragmentEntered: onFragmentEntered,
          onInlineFragmentEntered: onInlineFragmentEntered,
          onDeferredFragmentEntered: onDeferredFragmentEntered,
          onDeferredFragmentSkipped: onDeferredFragmentSkipped
        )

      case let .inlineFragment(typeCase):
        let shouldEnter: Bool
        switch inlineFragmentPolicy {
        case .includeAll:
          shouldEnter = true
        case .byRuntimeType:
          if let runtimeType = resolveRuntimeType(),
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
            resolveRuntimeType: resolveRuntimeType,
            inlineFragmentPolicy: inlineFragmentPolicy,
            deferredFragmentPolicy: deferredFragmentPolicy,
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
            resolveRuntimeType: resolveRuntimeType,
            inlineFragmentPolicy: inlineFragmentPolicy,
            deferredFragmentPolicy: deferredFragmentPolicy,
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
