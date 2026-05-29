# ADR 0007 — Selection-set-aware cache reads with per-field column projection

- **Status:** Accepted
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

**Cache reads under 3.0 carry per-field projection info, including each requested field's storage-shape type, end-to-end from executor to SQL.** The whole-record `loadRecords(forKeys:)` API is replaced. `SQLiteNormalizedCache`, `InMemoryNormalizedCache`, and any custom `NormalizedCache` implementor must adopt the new contract.

The new contract is captured by a value type, `FieldProjection`, that the executor populates from its `Selection.Field` traversal and the cache consumes to drive its read. The exact API surface of `FieldProjection` and the renamed `NormalizedCache.loadFields(_:)` method is fixed in PR-009b/c (the next two PRs in sub-phase 1A.5); this ADR commits only to the principles below.

### Principles the implementation must honor

1. **Per-field type info is required.** The cache layer must know, for each requested `(cacheKey, fieldName)` pair, which of the six storage columns the value lives in *and* whether the field is scalar or list-typed (per [ADR 0006](./0006-list-storage-strategy.md)'s `position` discriminator). The executor — not the cache — is the source of truth for this mapping, because the GraphQL type lives in the generated `Selection.Field`. A scalar `Int` field projects `int_value` filtered to `position = -1`; a `[String]` field projects `string_value` filtered to `position >= 0` and ordered by `position`.

2. **The `NormalizedCache` protocol changes its read shape.** `loadRecords(forKeys:) -> [CacheKey: Record]` is replaced by a load API that takes `[FieldProjection]` (or equivalent) and returns the projected field values. Custom implementors get a one-paragraph migration note in the 3.0 migration guide (PR-029 in the original plan numbering; renumbered under the restructure).

3. **SQL-level projection is the implementation target for `ApolloSQLiteDatabase`.** The new SELECT projects only the storage column(s) the request specifies, with the appropriate `position` predicate per field. Scalar `int_value`-typed fields produce single-column, single-row reads at `position = -1`; `[String]` fields produce single-column, N-row reads at `position >= 0`, ordered by `position`; mixed selections compose those projections in one SELECT via UNION ALL or a `(cache_key, field_name, position)`-tuple `IN` filter. The grouping back into a per-record shape happens in Swift after rows arrive.

4. **`InMemoryNormalizedCache` filters fields client-side.** No SQL involved, no projection at the storage layer — the in-memory cache holds full records and just returns the requested subset. The shared `FieldProjection` type drives the same API surface so the two cache backends are interchangeable.

5. **`CacheDataExecutionSource` declares field reads upfront, not lazily.** The current lazy-resolution pattern (`object[responseKey]`) is incompatible with one-shot SQL reads — the cache cannot project columns it does not know are wanted. The executor switches to a two-phase pattern: traverse the selection set to collect field projections, then resolve. This is the highest-risk PR in the sub-phase; if the executor's existing lazy contract cannot accommodate the change in one PR, the work is split (see PR-009d in the restructured plan).

6. **Per-field dependency tracking falls out naturally.** `GraphQLDependencyTracker` already records field-level cache keys for watcher dirty-set computation; with field projections in hand, the watcher's `didChangeKeys` re-read becomes the same projection-driven load, only with a different set of fields. No new tracking primitive is required.

7. **Custom scalars must expose their storage-shape type.** A custom scalar's `_jsonValue` ultimately maps to one of the six SQL columns (typically `custom_scalar_value` for dicts, or one of the primitive columns when the scalar's JSON shape is a primitive). The mechanism by which `CustomScalarType`-conforming types declare their column to the cache — whether via an existing `CustomScalarType` API, a new codegen-emitted property, or runtime introspection — is decided in PR-009b. This ADR commits only to the principle that the declaration is required and must be available statically (no runtime probe).

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

- *Rejected because:* This is half a fix. Smaller result sets help, but each row still carries five `NULL` columns across the boundary. The bigger win is per-column projection, and that requires type info. Doing the API change without the type info means changing the public `NormalizedCache` contract twice — once for field names, again for types — across the same major version. One coordinated change is cheaper.

### C. Lazy field resolution via a cache callback

Keep the executor's lazy `object[responseKey]` pattern; have `loadRecords` return a record-like object whose subscript reaches back into the cache on each field read. The cache projects per-field columns lazily.

- *Rejected because:* This turns every field read into a separate SQL round trip. For a selection set with N fields on M records, that is N×M prepared-statement steps versus the one batched SELECT the upfront-projection pattern enables. SQLite's parse-and-prepare overhead per statement is small but non-zero, and at typical selection-set sizes (10–30 fields on 1–100 records per read) it dominates the savings from per-column projection. The benchmark we would need to validate this approach does not exist; the upfront-projection alternative is well-understood and aligns with how every other typed-storage cache (Realm, GRDB) shapes its read API.

### D. Eager whole-record reads with column projection masked at the SQL layer

The executor still asks for whole records; `SQLiteNormalizedCache` keeps internal selection-set-derived projections it learns from the executor's prior reads, and uses those to project columns on subsequent reads.

- *Rejected because:* This works for steady-state selection sets that repeat (the same query running repeatedly populates the projection cache), but does nothing for first-read latency — the very metric most affected by cache reads on cold-start UI. The complexity of maintaining the projection cache (invalidation on schema changes, on selection-set evolution, on cache-key changes) is comparable to just plumbing the projection upstream. The upfront approach is also simpler to reason about and to test.

### E. Single-column generic value with a type tag

Collapse the six typed columns back to one `value BLOB` column plus a `value_type INTEGER` tag, and do projection by filtering rows on `value_type` instead of by selecting columns. SQL becomes simpler (one column always); reads become "give me rows where value_type is INT".

- *Rejected because:* This re-introduces the JSON-blob layout's problem under a different name. The BLOB column needs a Swift-side decoder that branches on the type tag — exactly the dispatch table `SQLiteFieldEncoding` already implements at the column level. The typed-column schema is faster because SQLite's storage is column-typed; collapsing back to a generic BLOB undoes that. The schema commitments from PR-008 + PR-008b already locked us out of this alternative; reopening it here would require dropping the schema and re-running the benchmark gates.

## Migration

### For users of `Apollo` (the SDK)

No change. The executor and the public client APIs (`ApolloClient.fetch`, `Watch`, `Subscribe`) have the same shape under 3.0 as under 2.x. Selection-set traversal is internal to the framework; the projection plumbing is invisible to consumers.

### For custom `NormalizedCache` implementors

The protocol changes. The legacy `loadRecords(forKeys:)` requirement is removed; in its place is a new requirement (exact name fixed in PR-009c) that takes `FieldProjection` values. The migration is mechanical: change the signature, project the requested fields out of the existing storage, return the new result type.

Pre-3.0 cache implementations cannot be carried forward without modification. This is the standard cost of the major version bump per [ADR 0001](./0001-major-version-bump.md) and is documented in the 3.0 migration guide.

### For codegen output

Generated `Selection.Field` declarations already carry output-type information sufficient to drive projection. Codegen may need to emit one additional piece of metadata per field — the column-shape mapping for custom scalars (per principle 7) — but this is additive and does not break compatibility with pre-PR-009b codegen output.

## Implementation sequence

The sub-phase 1A.5 PRs that implement this decision, in order. PR-008b and PR-009 are already in §8 (PR-008b inserted, PR-009 rewritten, per [ADR 0006](./0006-list-storage-strategy.md) and the §8 amendment in PR #1004); PR-009a–h are the additions this ADR introduces.

| Slot | Title | Notes |
|---|---|---|
| PR-008b | feat(sqlite): position-keyed schema | per ADR 0006; lands the schema this ADR's projection mechanism reads against. Schema version stays at `3` (Apollo iOS 3.x has not shipped externally, so the layout change is a within-v3 evolution rather than a wire-version bump). |
| PR-009 | feat(sqlite): row-per-element CRUD against position-keyed schema | amended per ADR 0006; the internal-test-only `selectRecords` is kept here until PR-009g supersedes it |
| PR-009a | docs(cache): ADR 0007 — selection-set-aware cache reads | **this PR** |
| PR-009b | refactor(cache): introduce `FieldProjection` types | new value types, no consumers yet; includes the scalar-vs-list discriminator required by Principle 1 |
| PR-009c | refactor(cache): `NormalizedCache` adopts field projection | breaking protocol change; `InMemoryNormalizedCache` implements; `SQLiteNormalizedCache` falls back to the PR-009 read path during transition |
| PR-009d | refactor(executor): `CacheDataExecutionSource` declares field reads upfront | highest-risk PR in the sub-phase; may split if the executor's lazy pattern can't be migrated in one shot |
| PR-009e | refactor(cache): `ApolloStore.load(_:)` propagates field projection | wires PR-009d through to `loadFields(_:)` |
| PR-009f | refactor(cache): `GraphQLDependencyTracker` consumes field projections | watcher dirty-set computation switches to projection-driven re-reads |
| PR-009g | feat(sqlite): field-aware `selectFields` with column projection | SQL-level projection in `ApolloSQLiteDatabase`, including `position` predicates per Principle 3; the internal-test-only `selectRecords` from PR-009 is removed in this PR or the next |
| PR-009h | refactor(sqlite): `SQLiteNormalizedCache` switches to field-aware path + drop-and-rebuild migration | the original PR-010 |

Phase 1A's calendar estimate grows from the post-ADR-0006 count of 11 PRs to ~17 PRs, adding roughly 4–6 weeks to the Phase 1A end date. Phases 1B, 1C, and 1D are unchanged in scope and renumber but do not restructure.

## Risk and rollback

The highest risk is PR-009d (the executor reshape). If the executor's lazy field-resolution pattern proves intractable to convert in one PR, the sub-phase splits PR-009d into:

- **PR-009d-i**: introduce the upfront-projection API alongside the existing lazy pattern; both paths coexist.
- **PR-009d-ii**: switch internal callers (executor and dependency tracker) to the upfront-projection path; remove the lazy pattern.

This split adds time but does not change the destination. The split is invisible to downstream consumers because the lazy pattern's surface is internal to `ApolloExecution`.

Rollback after merge: the design is not reversible without another major version. Once `NormalizedCache.loadFields(_:)` ships in 3.0, returning to `loadRecords(forKeys:)` would be a 4.0 break. This is the standard one-way-ratchet cost of public-protocol decisions and is accepted under [ADR 0001](./0001-major-version-bump.md)'s framing.

## References

- [Cache rewrite Phase 1 plan](../cache-rewrite-phase1-plan.md), §7 (SQLite schema — rewritten per ADR 0006)
- [Cache rewrite execution plan](../cache-rewrite-phase1-execution.md), §8 (PR list — PR-008b inserted and PR-009 amended per ADR 0006)
- [ADR 0001 — Major version bump](./0001-major-version-bump.md)
- [ADR 0002 — Record abstraction](./0002-record-abstraction.md)
- [ADR 0003 — TTL semantics](./0003-ttl-semantics.md)
- [ADR 0006 — List storage strategy](./0006-list-storage-strategy.md) — the row-per-element schema this ADR's projection mechanism reads against
- PR #1001 (PR-009 — row-per-element CRUD; `selectRecords` retained as internal-test-only)
