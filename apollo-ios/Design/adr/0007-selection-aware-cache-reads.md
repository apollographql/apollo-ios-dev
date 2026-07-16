# ADR 0007 — Selection-set-aware cache reads

- **Status:** Accepted (amended 2026-07-13 — see [Amendments](#amendments))
- **Date:** 2026-05-28
- **Phase 1 PR:** PR-009a (cache rewrite execution plan §8, sub-phase 1A.5)
- **Engineering plan reference:** [cache-rewrite-phase1-plan.md §7](../cache-rewrite-phase1-plan.md)
- **Related ADRs:** [0001](./0001-major-version-bump.md) (major version bump), [0002](./0002-record-abstraction.md) (Record abstraction)

## Context

PR-008 introduced the typed-column SQLite schema, and [ADR 0006](./0006-list-storage-strategy.md) amended it (via PR-008b, ~150 LoC) into its current row-per-element form. Each scalar field becomes one row at `position = -1`; each list element becomes one row at `position = 0..N-1`. The primary key is `(cache_key, field_name, position)`, and each row's value lives in exactly one of six type-specific columns: `int_value`, `string_value`, `float_value`, `bool_value`, `child_key_value`, `custom_scalar_value`. The other five value columns on every row are `NULL`. The schema's central design property is that **each field's (or list element's) storage column is determined by its GraphQL type, which is known at codegen time**.

PR-009 (as amended by ADR 0006) lays down the corresponding row-per-element writes, deletes, and per-type value encoder/decoder. The read path was initially drafted alongside as `SQLiteDatabase.selectRecords(forKeys:)` — a single `SELECT * FROM records WHERE cache_key IN (…)` that projects all six value columns plus `position` and reassembles whole `Record` instances in Swift. That implementation works, and is preserved as a test-only `internal` helper in PR-009. But it is the wrong shape for the public read contract, for two reasons.

**1. It does not exploit the schema's central optimization.** Five of the six value columns are `NULL` on every row, and every list-typed field's read pulls N rows where N is the list length. Pulling all six value columns across the SQLite-to-Swift boundary on every row, allocating Swift optionals for each, and then discarding five of them per row is pure waste. The row-per-element schema exists to enable typed reads — *if the caller knows a field is an Int, the SELECT should pull only `int_value`; if the caller knows it is a `[String]`, the SELECT should pull only `string_value` filtered to `position >= 0` and ordered by `position`*. The benchmark dataset that motivated the row-per-field shape (Zach's "SQLite Performance Benchmarks" Confluence page, ID 1585152147) does not gate this optimization — its targets cover scalar select/update/sort timings, not column-projection scenarios — so we have no empirical evidence that whole-record reads hit a perf wall. But shipping a public protocol that bakes whole-record reads into the contract forecloses the optimization for the rest of 3.x without another major version. The cost of holding the contract open is one sub-phase of work today.

**2. The information needed to project per-field columns lives upstream of the cache.** When `CacheDataExecutionSource.resolveField(with:on:)` resolves a field, it has the field's `Selection.Field` in hand — including its declared output type. The executor *knows* `User.age` is `Int!` and `User.tags` is `[String!]!`. That information currently never reaches the cache: the executor asks `ApolloStore.load(_:)` for whole records, traverses `Record.fields` by response key, and discards everything it does not need. To project at the SQL layer, the executor must declare its field reads *before* it executes them, and that declaration must thread through `ApolloStore`, the `NormalizedCache` protocol, and `SQLiteNormalizedCache` down to the `SQLiteDatabase` SELECT.

This is a public-protocol-shape change. `NormalizedCache.loadRecords(forKeys:)` is the documented extension point for custom cache implementations; changing it breaks downstream conformers. The cost is justified by the 3.0 major version bump (see [ADR 0001](./0001-major-version-bump.md)) and by the cost of *not* making the change — which would be permanent under semver.

## Decision

**Cache reads under 3.0 carry per-field projection info — the `(cacheKey, fieldName)` pairs a selection set needs — end-to-end from executor to SQL.** *(Amended 2026-07-13: projections carry no storage-shape type info; see [Amendments](#amendments).)* The whole-record `loadRecords(forKeys:)` API is replaced. *(As of the PR-009g-ii stack tip, `loadRecords` is still present on the protocols and `loadFields` is `@_spi(Execution)`-gated as a transition state; per the 2026-07-16 amendment, PR-009h removes `loadRecords` from the protocols and graduates `loadFields` to the sole, public read requirement.)* `SQLiteNormalizedCache`, `InMemoryNormalizedCache`, and any custom `NormalizedCache` implementor must adopt the new contract.

The new contract is captured by a value type, `FieldProjection`, that the executor populates from its `Selection.Field` traversal and the cache consumes to drive its read. The exact API surface of `FieldProjection` and the renamed `NormalizedCache.loadFields(_:)` method is fixed in PR-009b/c (the next two PRs in sub-phase 1A.5); this ADR commits only to the principles below.

### Principles the implementation must honor

1. **Per-field reads are identified by `(cacheKey, fieldName)` alone.** *(Amended 2026-07-13; the original principle required per-field type info — see [Amendments](#amendments).)* The cache reads every stored row for the pair and infers scalar-vs-list shape from the rows' `position` values at read time (`-1` scalar, `>= 0` list elements, `-2` empty-list marker). No GraphQL type information crosses the cache boundary. If the stored shape disagrees with the shape the generated models declare — a non-backwards-compatible schema change shipped without clearing the cache — the mismatch surfaces to the caller as a `JSONDecodingError.wrongType` execution error, matching 2.x behavior. The cache does not mask schema drift as a silent miss; the developer decides how to respond.

2. **The `NormalizedCache` protocol changes its read shape.** `loadRecords(forKeys:) -> [CacheKey: Record]` is replaced by a load API that takes `[FieldProjection]` (or equivalent) and returns the projected field values. Custom implementors get a one-paragraph migration note in the 3.0 migration guide (PR-029 in the original plan numbering; renumbered under the restructure).

3. **SQL-level *row filtering* is the implementation target for `ApolloSQLiteDatabase`.** *(Amended 2026-07-13; the original principle targeted per-column projection with position predicates — see [Amendments](#amendments).)* The SELECT filters rows by a `(cache_key, field_name)`-tuple `IN` list and projects all value columns; grouping back into per-record shape happens in Swift after rows arrive. Column narrowing is dropped, not deferred: SQLite stores rows whole in B-tree leaf pages (and the records table is `WITHOUT ROWID`, clustered by primary key), so a narrower column list saves no IO — a `NULL` column costs one record-header byte — while per-field column sets fragment the SQL statement shapes and work against prepared-statement reuse. The row-level win (not fetching rows for fields the selection set doesn't touch) is the real optimization, and row filtering delivers it.

4. **`InMemoryNormalizedCache` filters fields client-side.** No SQL involved, no projection at the storage layer — the in-memory cache holds full records and just returns the requested subset. The shared `FieldProjection` type drives the same API surface so the two cache backends are interchangeable.

5. **`CacheDataExecutionSource` declares field reads upfront, not lazily.** The current lazy-resolution pattern (`object[responseKey]`) is incompatible with one-shot SQL reads — the cache cannot project columns it does not know are wanted. The executor switches to a two-phase pattern: traverse the selection set to collect field projections, then resolve. This is the highest-risk PR in the sub-phase; if the executor's existing lazy contract cannot accommodate the change in one PR, the work is split (see PR-009d in the restructured plan).

6. **Per-field dependency tracking falls out naturally.** `GraphQLDependencyTracker` already records field-level cache keys for watcher dirty-set computation; with field projections in hand, the watcher's `didChangeKeys` re-read becomes the same projection-driven load, only with a different set of fields. *(Amended 2026-07-13: as shipped, PR-009f introduced `CacheDependentKey` — a structured public `(cacheKey, fieldName)` pair replacing the legacy string keys on `ApolloStoreSubscriber`, `NormalizedCache.merge`, and `RecordSet.merge` — rather than reusing `FieldProjection` for the dirty set. The original "no new tracking primitive" expectation did not hold; the two types are deliberately distinct: one names a field a result depends on, the other names a field a read requests.)*

7. **~~Custom scalars must expose their storage-shape type.~~** *(Withdrawn by the 2026-07-13 amendment.)* With column projection dropped (Principle 3), reads never consult a field's storage column, so no static column declaration is needed from `CustomScalarType` conformers, and no codegen emission is required. The write side continues to route values to columns by runtime JSON shape via `SQLiteFieldEncoding`; reads return whatever column is populated.

### Non-goals

- **The list-storage layout itself.** Whether list elements are stored as JSON, in a sibling table, or in-place as position-keyed rows is the subject of [ADR 0006](./0006-list-storage-strategy.md), which settled on the row-per-element in-place layout. This ADR *consumes* that layout — the projection API expresses list-field reads in `position`-aware terms because that is what ADR 0006 produced — but does not redecide it. Nested lists (`[[T]]`) are handled by ADR 0006's synthetic-sub-record indirection; the projection mechanism follows the indirection transparently and does not need a separate non-goal carve-out.
- **Per-field TTL evaluation during projection.** TTL is checked at read time inside `CacheDataExecutionSource.resolveField` per [ADR 0003](./0003-ttl-semantics.md). The projection mechanism delivers field values to the executor; TTL evaluation happens after delivery. The two concerns compose but do not interact.
- **Cross-cache compatibility with 2.x.** The new `NormalizedCache` protocol is a breaking change. There is no compatibility shim, no dual-stack. The migration guide is the contract.

## Alternatives considered

### A. Status quo — whole-record reads on a typed-column schema

Keep the current `selectRecords(forKeys:)` shape; the typed columns exist purely to avoid the JSON-parse overhead of the legacy single-column blob layout.

- *Rejected because:* This trades a 3.x perf optimization for a 5-day refactor today. The typed columns already pay back the JSON-parse cost (PR-008's benchmark gates pass), but the whole-record contract leaves the per-field-projection win on the table permanently. Reversing this later requires a 4.0 major version. Under [ADR 0001](./0001-major-version-bump.md), we have one major-version window to get the public read contract right; spending it on whole-record reads is a one-way ratchet against future performance work.

### B. Field-name projection only — no GraphQL-type info at the cache layer

The cache API takes `(cacheKey, fieldName)` pairs but no type. SQL SELECTs still project all six value columns (smaller result sets — fewer rows when the executor only wants a subset — but the same wide column projection per row).

- *Originally rejected, adopted by the 2026-07-13 amendment.* The original rejection ("each row still carries five `NULL` columns across the boundary") misjudged SQLite's storage model: rows are stored whole in clustered B-tree pages, so wide column projection costs no IO and `NULL` columns cost one header byte each. The "bigger win" the rejection reserved for per-column projection does not exist at the storage layer; the row-count reduction this alternative delivers *is* the optimization. What landed in PR-009g is this design, and PR-009g-ii slims `FieldProjection` to match. See [Amendments](#amendments).

### C. Lazy field resolution via a cache callback

Keep the executor's lazy `object[responseKey]` pattern; have `loadRecords` return a record-like object whose subscript reaches back into the cache on each field read. The cache projects per-field columns lazily.

- *Rejected because:* This turns every field read into a separate SQL round trip. For a selection set with N fields on M records, that is N×M prepared-statement steps versus the one batched SELECT the upfront-projection pattern enables. SQLite's parse-and-prepare overhead per statement is small but non-zero, and at typical selection-set sizes (10–30 fields on 1–100 records per read) it dominates the savings from per-column projection. The benchmark we would need to validate this approach does not exist; the upfront-projection alternative is well-understood and aligns with how every other typed-storage cache (Realm, GRDB) shapes its read API.

### D. Eager whole-record reads with column projection masked at the SQL layer

The executor still asks for whole records; `SQLiteNormalizedCache` keeps internal selection-set-derived projections it learns from the executor's prior reads, and uses those to project columns on subsequent reads.

- *Rejected because:* This works for steady-state selection sets that repeat (the same query running repeatedly populates the projection cache), but does nothing for first-read latency — the very metric most affected by cache reads on cold-start UI. The complexity of maintaining the projection cache (invalidation on schema changes, on selection-set evolution, on cache-key changes) is comparable to just plumbing the projection upstream. The upfront approach is also simpler to reason about and to test.

### E. Single-column generic value with a type tag

Collapse the six typed columns back to one `value BLOB` column plus a `value_type INTEGER` tag, and do projection by filtering rows on `value_type` instead of by selecting columns. SQL becomes simpler (one column always); reads become "give me rows where value_type is INT".

- *Rejected because:* This re-introduces the JSON-blob layout's problem under a different name. The BLOB column needs a Swift-side decoder that branches on the type tag — exactly the dispatch table `SQLiteFieldEncoding` already implements at the column level. The typed-column schema is faster because SQLite's storage is column-typed; collapsing back to a generic BLOB undoes that. The schema commitments from PR-008 + PR-008b already locked us out of this alternative; reopening it here would require dropping the schema and re-running the benchmark gates.

### F. Two-pass cache read to resolve runtime type before field projection

For records containing inline fragments, issue *two* cache round-trips: the first loads only `__typename`; the second issues a precise projection narrowed by the now-known runtime type. The collector wouldn't need an `includeAllInlineFragments` mode — it'd know which type cases apply before building the projection set.

- *Rejected because:* Doubles the per-level round-trip count for any record with inline fragments. *(Corrected by the 2026-07-13 amendment: this rationale originally claimed a single-query `__typename` CTE design "landed in PR-009g" — it did not. PR-009g as shipped issues an existence probe plus a row-filter SELECT with no `__typename` filter; unmatched type cases' rows are over-fetched and discarded by the executor's type-aware traversal.)* The two-pass design stays rejected on its own demerits. The single-statement `__typename` filter remains the preferred shape *if* the inline-fragment over-fetch ever measures as significant: it is deferred behind the Tier 2 `loadFields` inline-fragment scenario in the [perf plan](../cache-rewrite-phase1-perf.md), and if justified it arrives as an *additive* change — a `requiredTypename` property on `FieldProjection` (the framework constructs projections, so adding a property does not break custom `NormalizedCache` implementors).

### G. Cross-phase `FieldExecutionInfo` sharing as a Phase 1A foundation

Restructure `FieldProjectionCollector` from the outset to emit both projections and a `FieldSelectionGrouping`, so the executor's `groupFields` consumes the precomputed grouping rather than walking again — eliminating the projection-time / resolve-time recompute of `cacheFieldKey` entirely.

- *Deferred, not rejected:* This is captured as the optional PR-009g-bis in the implementation sequence, gated on profiling after PR-009g lands. The benefit is real but bounded by how expensive policy resolution is on realistic workloads: scalar fields short-circuit cheaply, and the resolver-side recompute is already addressed by PR-009d-iii's `FieldExecutionInfo` memo. The full cross-phase sharing is a meaningful API change (collector return shape, executor's groupFields accepting precomputed input) and is best evaluated against measured policy-resolution cost rather than committed up front. The collector-then-resolver dataflow is design-compatible with PR-009g-bis — landing the foundation now doesn't preclude the optimization later.

## Migration

### For users of `Apollo` (the SDK)

No change. The executor and the public client APIs (`ApolloClient.fetch`, `Watch`, `Subscribe`) have the same shape under 3.0 as under 2.x. Selection-set traversal is internal to the framework; the projection plumbing is invisible to consumers.

### For custom `NormalizedCache` implementors

The protocol changes. The legacy `loadRecords(forKeys:)` requirement is removed; in its place is a new requirement (exact name fixed in PR-009c) that takes `FieldProjection` values. The migration is mechanical: change the signature, project the requested fields out of the existing storage, return the new result type.

Pre-3.0 cache implementations cannot be carried forward without modification. This is the standard cost of the major version bump per [ADR 0001](./0001-major-version-bump.md) and is documented in the 3.0 migration guide.

### For codegen output

No change. *(Amended 2026-07-13: the original text anticipated codegen emitting a column-shape mapping for custom scalars per the now-withdrawn Principle 7; with column projection dropped, no codegen change is needed.)*

## Implementation sequence

The sub-phase 1A.5 PRs that implement this decision, in order. PR-008b and PR-009 are already in §8 (PR-008b inserted, PR-009 rewritten, per [ADR 0006](./0006-list-storage-strategy.md) and the §8 amendment in PR #1004); PR-009a–h are the additions this ADR introduces.

| Slot | Title | Notes |
|---|---|---|
| PR-008b | feat(sqlite): position-keyed schema | per ADR 0006; lands the schema this ADR's projection mechanism reads against. Schema version stays at `3` (Apollo iOS 3.x has not shipped externally, so the layout change is a within-v3 evolution rather than a wire-version bump). |
| PR-009 | feat(sqlite): row-per-element CRUD against position-keyed schema | amended per ADR 0006; the internal-test-only `selectRecords` is kept here until PR-009g supersedes it |
| PR-009a | docs(cache): ADR 0007 — selection-set-aware cache reads | **this PR** |
| PR-009b | refactor(cache): introduce `FieldProjection` types | new value types, no consumers yet. As landed, included a scalar-vs-list discriminator and column-shape classification required by the original Principle 1; both are removed again by PR-009g-ii per the 2026-07-13 amendment |
| PR-009c | refactor(cache): `NormalizedCache` adopts field projection | breaking protocol change; `InMemoryNormalizedCache` implements; `SQLiteNormalizedCache` falls back to the PR-009 read path during transition |
| PR-009d-i | refactor(executor): introduce `FieldProjectionCollector` | per-level selection-set traversal that emits `Set<FieldProjection>` for one record. Additive — no executor caller wired yet. Walks `[Selection]` with the same case-dispatch shape as `DefaultFieldSelectionCollector`, parameterized by inline-fragment and deferred-fragment policies. Split from the original PR-009d slot per the Risk and rollback fallback. |
| PR-009d-ii | refactor(executor): `CacheDataExecutionSource` adopts upfront projection | `ProjectionLoader` replaces `DataLoader<CacheKey, Record>`; `ReadTransaction.loadObject(forKey:selections:variables:schema:responsePath:)` drives projection-aware reads; per-field `CacheReference` resolution issues child-level projections through the same loader. `PossiblyDeferred` and the shared `GraphQLExecutor` are unchanged — only the cache execution source switches paths. `NormalizedCache.loadFields(_:)` contract refined: a cache key appears in the result iff the record exists in storage, with empty `fields` when no requested field is present (preserves the executor's per-field `missingValue` path wrapping). Introduces a `Selection.Field.cacheFieldKey(variables:schema:responsePath:)` shared helper so the collector and the resolver compute the same policy-aware field name(s) by construction. |
| PR-009d-iii | refactor(executor): `FieldExecutionInfo` memoizes `CacheFieldKey` | small follow-up. Adds a `_cacheFieldKey: CacheFieldKey?` cache on `FieldExecutionInfo` mirroring the existing `_cacheKeyForField` pattern. `CacheDataExecutionSource.resolveCacheKey` calls `info.cacheFieldKey()` instead of `info.field.cacheFieldKey(...)`. Resolver-side cache field key resolution becomes O(1) per info; the policy evaluator is invoked once per `(field, info)`, not once per `resolveField`. |
| PR-009d-iv | refactor(cache): extract shared `SelectionWalker` | deduplicates the Selection-case dispatch logic shared between `DefaultFieldSelectionCollector` (resolve path) and `FieldProjectionCollector` (projection path). Parameterized by per-field action, `InlineFragmentPolicy` (`byRuntimeType` / `includeAll`), and `DeferredFragmentPolicy` (`respectDeferCondition` / `eager`). Both collectors call the shared walker; no behavior change, no public API change. Lands before PR-009f so the dependency tracker's invalidation walk can use the unified helper. |
| PR-009e | refactor(cache): `ApolloStore.load(_:)` propagates field projection | finalizes the loose ends from PR-009d-ii — retires `DataLoader<CacheKey, Record>` from `ApolloStore.swift` (no longer referenced), verifies every public `load` / `read` entry point routes through the projection-aware path, updates test scaffolding that depended on the old DataLoader-keyed behavior. |
| PR-009f | refactor(cache): `GraphQLDependencyTracker` emits structured `CacheDependentKey` | **As shipped (amended 2026-07-13):** the tracker emits structured `CacheDependentKey` pairs; `ApolloStoreSubscriber.store(_:didChangeKeys:)`, `NormalizedCache.merge`, and `RecordSet.merge` adopt `Set<CacheDependentKey>`, and watcher matching intersects typed sets exactly. The originally-planned conversion of dirty entries into `FieldProjection`s via a direct shape initializer was not built (and that initializer is removed by PR-009g-ii). |
| PR-009g | feat(sqlite): field-aware `selectFields` (row filtering) | **As shipped (amended 2026-07-13):** two statements inside one queue hop — an existence probe (so callers distinguish record-absent from field-missing) plus a `(cache_key, field_name)` row-filter SELECT projecting all value columns. No column projection, no `position` predicates, no `__typename` filter; per amended Principle 3 those are dropped or deferred, not pending. The internal-test-only `selectRecords` from PR-009 is removed in PR-009h. |
| PR-009g-ii | refactor(cache): slim `FieldProjection` to `(cacheKey, fieldName)` | removes `columnShape`/`cardinality` and the OutputType classification machinery per the 2026-07-13 amendment; no backend consumed them. Projections dedupe on exactly what backends read, eliminating the conflicting-duplicate-projections hazard |
| PR-009g-bis | refactor(cache): cross-phase `FieldExecutionInfo` sharing | **OPTIONAL — gated on profiling after PR-009g lands.** Restructure `FieldProjectionCollector.collect(...)` to return `(Set<FieldProjection>, FieldSelectionGrouping)`. `loadObject(...)` retains the grouping alongside the loaded `Record`; the executor's `groupFields` accepts a precomputed grouping for cache-path execution sources and falls back to building from scratch for the network / selection-set-model paths. Combined with PR-009d-iii's info memo, `cacheFieldKey` is computed once per `(field, parent_info)` ever — eliminates the projection-time recompute that's currently amortized only on the resolver side. Significant collector API change; commit only if measurement on realistic policy-heavy workloads justifies the complexity. |
| PR-009h | refactor(sqlite): `SQLiteNormalizedCache` switches to field-aware path + drop-and-rebuild migration | the original PR-010. **Expanded per the 2026-07-16 amendment:** removes `loadRecords(forKeys:)` from `NormalizedCache`/`ReadOnlyNormalizedCache`, drops the delegating default `loadFields` implementation, graduates `loadFields` and `FieldProjection` from `@_spi(Execution)` to public as the sole read requirement, and gives `InMemoryNormalizedCache` a native `loadFields` implementation. |

Phase 1A's calendar estimate grows from the post-ADR-0006 count of 11 PRs to ~19 PRs (~20 if PR-009g-bis lands), adding roughly 5–7 weeks to the Phase 1A end date. Phases 1B, 1C, and 1D are unchanged in scope and renumber but do not restructure.

## Risk and rollback

The highest risk is the PR-009d executor reshape. The sub-phase splits PR-009d into:

- **PR-009d-i**: introduce the upfront-projection API alongside the existing lazy pattern; both paths coexist.
- **PR-009d-ii**: switch internal callers (executor and dependency tracker) to the upfront-projection path; remove the lazy pattern.

This split adds time but does not change the destination. The split is invisible to downstream consumers because the lazy pattern's surface is internal to `ApolloExecution`.

The follow-on cleanups PR-009d-iii (info memo) and PR-009d-iv (extract `SelectionWalker`) are low-risk additive refactors on top of PR-009d-ii. They surface as small, focused PRs rather than expanding PR-009d-ii's diff because (a) the memo is a refinement of the `CacheFieldKey` machinery introduced in PR-009d-ii and reads more clearly as a separate change, and (b) the walker extraction touches both the existing `DefaultFieldSelectionCollector` and the new `FieldProjectionCollector`, which is a refactoring concern distinct from the projection-path adoption.

PR-009g-bis is a profile-gated commitment. The benefit (one-time `cacheFieldKey` computation per `(field, parent_info)`) is bounded by how expensive policy resolution is on realistic workloads — for scalar-heavy queries the resolution short-circuits cheaply and the cross-phase memo barely registers; for object-policy-heavy queries the savings may be measurable. The decision falls naturally after PR-009g because that PR bounds the IO over-fetch cost of the projection-time `includeAllInlineFragments: true` strategy: with the SQL filtering by `__typename` in one statement, the walker-level over-fetch is the only remaining cost, and PR-009g-bis is what addresses it. Without the PR-009g IO benefit in place, PR-009g-bis's payoff is harder to measure cleanly.

Rollback after merge: the design is not reversible without another major version. Once `NormalizedCache.loadFields(_:)` ships in 3.0, returning to `loadRecords(forKeys:)` would be a 4.0 break. This is the standard one-way-ratchet cost of public-protocol decisions and is accepted under [ADR 0001](./0001-major-version-bump.md)'s framing.

## Amendments

### 2026-07-13 — Row filtering adopted; column projection dropped; shape metadata removed

**What changed.** Alternative B (field-name row filtering with wide column projection) is the accepted read design; the original decision's per-column projection with `position` predicates (original Principles 1 and 3) and the custom-scalar column declaration (original Principle 7) are withdrawn. `FieldProjection` slims to `(cacheKey, fieldName)` (PR-009g-ii). The single-statement `__typename` inline-fragment filter is deferred behind measurement (see below).

**Why column projection is dropped, not deferred.** The original decision assumed a column-store cost model. SQLite is row-oriented: rows live whole in B-tree leaf pages, and the records table is `WITHOUT ROWID` — clustered whole-row storage keyed by `(cache_key, field_name, position)`. Reading any column of a row reads the page holding the entire row, and a `NULL` value column costs a single record-header byte. Column narrowing therefore saves no IO; the realizable saving is minor per-row CPU (fewer `sqlite3_column_*` extractions), while the cost is real — per-field column sets multiply SQL statement shapes, which works directly against the statement caching the write path needs before the PR-011 gates. Separately, column projection as specified would have been *incorrect* against the shipped encoding: explicit `null` is always stored in `custom_scalar_value` regardless of field type, codegen-default custom scalars and `GraphQLEnum` values store in `string_value` while classification routed them to `custom_scalar_value`, and a `Float` field whose JSON arrives integral stores in `int_value` (a per-value condition no static declaration can fix). Correct column projection would have required encoding changes plus compatible-column over-reads, further shrinking the already-illusory benefit.

**Why position predicates are dropped.** On well-formed data a field has one shape at a time, so a `position` predicate reads exactly the rows the row filter already reads — zero benefit. Its only observable effect was converting a declared-vs-stored shape mismatch (a non-backwards-compatible schema change shipped without clearing the cache) from a caller-visible `JSONDecodingError.wrongType` into a silent per-field refetch. The visible error is the *chosen* semantics: it matches 2.x, requires no new code, and keeps schema drift a developer-visible event rather than something the cache papers over. Schema changes are normally additive and leave the existing cache valid; whole-cache invalidation on every schema change was considered and rejected.

**Consequences for the public 3.0 surface.** `FieldProjection` is the pair `(cacheKey, fieldName)`; `Set<FieldProjection>` dedupes on exactly what backends read, eliminating the conflicting-duplicate-projections precondition that shape-inclusive hashing created. Custom `NormalizedCache` implementors receive the simplest possible contract. If the `__typename` SQL filter is later justified, the type-condition metadata it needs (`requiredTypename: String?`) is added to `FieldProjection` as an additive property — the framework constructs projections, so this is not a breaking change.

**Measurement gate.** The inline-fragment over-fetch (the walker's `includeAllInlineFragments: true` fetching rows for unmatched type cases) is the one remaining row-level inefficiency, and it is schema-dependent. The Tier 2 `loadFields` scenarios added to the [perf plan](../cache-rewrite-phase1-perf.md) — including an interface-heavy inline-fragment scenario — are the gate for both the `__typename` filter and PR-009g-bis. Neither lands without a `regressed`-class measurement justifying it.

### 2026-07-16 — `loadRecords` removal confirmed

The retention question left open by the 2026-07-13 amendment is resolved: the final 3.0 `NormalizedCache`/`ReadOnlyNormalizedCache` protocols expose **only** the projection-aware `loadFields(_:)` read. `loadRecords(forKeys:)` is removed at PR-009h, not kept alongside — supporting both read shapes indefinitely would preserve the whole-record contract ADR 0007 exists to retire. Consequences, all landing in PR-009h: the delegating default `loadFields` implementation is deleted (it has nothing left to delegate to), `loadFields` becomes a hard requirement and — together with `FieldProjection` — graduates from `@_spi(Execution)` to public (an SPI-only requirement on a public protocol would be unimplementable by third parties), and `InMemoryNormalizedCache` implements `loadFields` natively. `SQLiteNormalizedCache` may keep a whole-record read as a private implementation detail of the legacy-blob migration path, but it is no longer protocol surface.

### 2026-07-16 — Projections grouped per record

`FieldProjection(cacheKey, fieldName)` is reshaped into
`RecordProjection(cacheKey, fieldNames: Set<String>)` (PR-009g-iii). The
pairwise type denormalized data that is born grouped: the collector walks one
record's selections per call (its `cacheKey` parameter existed only to build
the pairs and is now gone), every backend's first move was regrouping by cache
key, and `ProjectionLoader`'s state was already per-key. `RecordProjection`
is a transfer type, not an accumulator — repeated cache keys in a
`loadFields(_:)` call merge to the union of their field names, and
accumulation code uses `[CacheKey: Set<String>]`. `CacheDependentKey`
deliberately stays pairwise (a changed field is one pair), so the
projection/dependency types now differ structurally as well as in role. The
future `requiredTypename` metadata, if the deferred `__typename` filter is
ever justified, attaches per field within the group — still additive.

## References

- [Cache rewrite Phase 1 plan](../cache-rewrite-phase1-plan.md), §7 (SQLite schema — rewritten per ADR 0006)
- [Cache rewrite execution plan](../cache-rewrite-phase1-execution.md), §8 (PR list — PR-008b inserted and PR-009 amended per ADR 0006)
- [ADR 0001 — Major version bump](./0001-major-version-bump.md)
- [ADR 0002 — Record abstraction](./0002-record-abstraction.md)
- [ADR 0003 — TTL semantics](./0003-ttl-semantics.md)
- [ADR 0006 — List storage strategy](./0006-list-storage-strategy.md) — the row-per-element schema this ADR's projection mechanism reads against
- PR #1001 (PR-009 — row-per-element CRUD; `selectRecords` retained as internal-test-only)
