# ADR 0006 — List storage strategy: JSON-encoded `list_value` vs sibling `list_items` table

- **Status:** Proposed — decision deferred to PR-011a list-heavy benchmark data; locked before PR-012 (3.0-alpha tag)
- **Date:** 2026-05-28
- **Phase 1 PR:** Out-of-stack docs follow-up to PR-009
- **Engineering plan reference:** [cache-rewrite-phase1-plan.md §7.1, §7.4](../cache-rewrite-phase1-plan.md)
- **Perf plan reference:** [cache-rewrite-phase1-perf.md](../cache-rewrite-phase1-perf.md) — Tier 3 scenario coverage

## Context

[ADR 0002](./0002-record-abstraction.md) settled the in-memory `Record` shape; engineering plan §7.1 settled the on-disk shape: one row per field, with per-type value columns (`int_value`, `string_value`, `float_value`, `bool_value`, `child_key_value`, `custom_scalar_value`) plus `list_value TEXT` for list-typed fields. Scalars land in their typed column; lists land as a JSON-encoded blob in `list_value`. This asymmetry was flagged in the PR-009 review: scalar fields get a typed, indexable column, but list elements collapse to a single opaque string.

The §7.1 choice traces to Zach's [SQLite Performance Benchmarks](https://apollographql.atlassian.net/wiki/spaces/ClientDev/pages/1585152147) (Confluence page 1585152147), the same source that motivates the row-per-field shape itself. The benchmark's published numbers — and the §7.4 performance gates derived from them — measure exact-key selects, type+selection-set selects, composite-PK updates, single-row inserts, and CTE-join sorts. None of those scenarios exercise list-heavy paths. There is no empirical evidence that JSON-encoded `list_value` is the optimal choice for list-typed fields specifically; the design inherits the choice without having measured the alternative.

PR-009's encoder/decoder already implements the JSON path end-to-end and hardens it (PR-009 review-findings commit: `JSONSerialization.isValidJSONObject` probe, `NSNull` round-trip, `$reference`-wrapper disambiguation, `sortedKeys` for stable on-disk bytes). The implementation is real; what is missing is the *evidence* that this implementation is the right one.

This ADR scopes that question and the evidence-collection plan that resolves it.

## Decision

**Defer.** The choice between the two options below is not made by this ADR. The ADR commits to:

1. Treating the §7.1 `list_value TEXT` shape as a **provisional default**, not a ratified choice, until list-heavy benchmark data exists.
2. Adding list-heavy scenarios to the PR-011 / PR-011a performance-measurement harness (see §3, "Deciding evidence").
3. **Locking the decision before PR-012** — the 3.0-alpha tag — based on those numbers. The lock happens by amending this ADR with a Status flip from *Proposed* to *Accepted* and a final §2 Decision paragraph naming the chosen option.

The two options under evaluation are:

### Option 1 — Ratify JSON-encoded `list_value` (current §7.1 shape)

Keep the row-per-field layout exactly as specified in engineering plan §7.1. Each list-typed field stores its elements as a JSON-encoded `TEXT` blob in `list_value`. Nested lists (`[[Int]]`, `[[CacheReference]]`) are handled naturally by JSON's recursive structure — no schema change required.

### Option 2 — Migrate list-typed fields to a sibling `list_items` table

Lists become a one-to-many relation against a second table:

```sql
CREATE TABLE IF NOT EXISTS list_items (
  cache_key            TEXT NOT NULL,
  field_name           TEXT NOT NULL,
  position             INTEGER NOT NULL,
  int_value            INTEGER,
  string_value         TEXT,
  float_value          REAL,
  bool_value           INTEGER,
  child_key_value      TEXT,
  custom_scalar_value  TEXT,
  -- nested-list strategy: TBD; see §4 trade-off table
  PRIMARY KEY (cache_key, field_name, position),
  FOREIGN KEY (cache_key, field_name) REFERENCES records(cache_key, field_name) ON DELETE CASCADE
) WITHOUT ROWID;
```

The `list_value` column in `records` is either dropped or repurposed as a fast-path for very short lists; the design detail is part of the option's evaluation. Reads issue a second `SELECT … WHERE cache_key = ? AND field_name = ? ORDER BY position` for any list-typed field (or a `LEFT JOIN` if the planner prefers).

Nested lists (`[[Int]]`, `[[CacheReference]]`) require an explicit depth strategy under Option 2 — either a `depth` column with a self-referential structure, or a separate `list_of_lists` shape, or a fallback to JSON-encoding for nesting depth > 1. There is no shape that mirrors Option 1's natural recursion without paying additional schema complexity.

## Trade-offs

| Dimension | Option 1 (JSON `list_value`) | Option 2 (`list_items` table) |
|---|---|---|
| Read cost — short list | One row, one column. Decode `JSONSerialization` once. | Second `SELECT` or join. Per-element row construction. |
| Read cost — long list | `JSONSerialization` cost grows with list length. | Per-row dispatch grows with length; potentially better cache locality with `WITHOUT ROWID` clustering. |
| Write cost — full overwrite | One row UPSERT regardless of list cardinality. | N row UPSERTs for length N. Bulk transaction required for atomicity. |
| Write cost — single-element edit | Re-encode and re-write the entire list. | One row UPSERT at the relevant `position`. |
| Order preservation | Implicit (JSON arrays are ordered). | Explicit `position` column on every row. |
| Type symmetry with scalars | Asymmetric — scalars get typed columns, list elements collapse to JSON. | Symmetric — list elements get the same typed-column layout as scalars in the parent table. |
| Nested lists (`[[Int]]`, `[[CacheReference]]`) | Native — JSON nests recursively. | Requires depth strategy: recursive `list_of_lists` table, depth column, or JSON-fallback above depth 1. |
| Child-reference indexing | Impossible without parsing JSON. Blocks per-element FK or sentinel columns for Phase 2 `@onDelete` cascade. | Each `child_key_value` element is a row — directly indexable. Phase 2 cascade can model relationships at the storage layer. |
| SQL operations on members | Not feasible (opaque blob). | Filter, join, aggregate on list members directly. |
| Schema surface | One table. | Two tables. Every future schema migration touches both. |
| Implementation effort to ship | Already complete (PR-009 + review-findings commit). | New encoder, new decoder, new `WITHOUT ROWID` table, new migration step, new transactional contract for write atomicity. |

## Deciding evidence

The PR-011 / PR-011a perf-harness PRs are the right place to collect the missing data. Adding list-heavy scenarios there has the side benefit of strengthening the 3.0-alpha published dataset against future regressions, independent of this ADR's outcome.

Scenarios to add (Tier 2 — `NormalizedCache` protocol level — and Tier 3 — direct SQLite operations):

| Scenario | Tier | Purpose |
|---|---|---|
| `read-record-with-list-of-N-scalars` (N ∈ {10, 100, 1000}) | 2, 3 | Read cost as list length grows |
| `read-record-with-list-of-N-references` (N ∈ {10, 100, 1000}) | 2, 3 | Reference-typed list cost; relevant to Phase 2 cascade |
| `write-list-of-N-scalars` (cold + warm) | 2, 3 | Full-list write cost; pivotal for Option 1 vs 2 |
| `write-list-of-N-references` (cold + warm) | 2, 3 | As above with reference elements |
| `mutate-single-element-in-list-of-N` (N ∈ {10, 100, 1000}) | 2 | Pivotal for the "edit one item" workload that favors Option 2 |
| `read-record-with-nested-list-[[Int]]` (outer ∈ {10, 100}, inner ∈ {10, 100}) | 2, 3 | Stresses Option 2's depth strategy |
| `read-record-with-nested-list-[[CacheReference]]` (outer ∈ {10, 100}, inner ∈ {10, 100}) | 2, 3 | As above with the reference shape Phase 2 cares about |

Per perf plan §3, these add a new performance-relevant subsystem (list paths) that the existing scenarios do not cover; perf plan §5.2 already anticipates inline `feat(perf): add scenario for X` additions. The list scenarios land in PR-011a as part of the comprehensive Tier 1 / Tier 2 harness; the Tier 3 SQLite-level scenarios extend PR-011.

The decision rule for the lock:

- If Option 1 is within the §7.4 performance envelope (suitably extended for the new scenarios) across all list lengths *and* the Option 2 mutate-single-element case is not dramatically faster (>3× speedup on `mutate-single-element-in-list-of-100`, say), **Option 1 is ratified**. The asymmetry is accepted; Phase 2 `@onDelete` cascade pays its own per-element parse cost when the time comes.
- If Option 2 is materially faster on `mutate-single-element-in-list-of-N` or `read-record-with-list-of-1000-references` *and* the nested-list overhead is bounded, **Option 2 is adopted before PR-012.** A new PR (call it PR-009b) lands the second table, migrating the `list_value` path. Migration is a no-op for end users (drop-and-rebuild migration per ADR 0001 already happens once on 3.0 upgrade; the schema simply lands in its final shape).
- Edge cases — Option 2 wins single-element edit but loses bulk reads, or vice versa — escalate to the reviewer per execution plan §6 trigger 8.

The lock is final by PR-012. After 3.0-alpha tags, changing the list-storage strategy would force a second drop-and-rebuild migration on existing 3.0-alpha installs — the same reason §7.1's `written_at` column is added in PR-008 instead of Phase 1C.

## Consequences

### Positive

- **Empirical grounding for an unmeasured choice.** The current §7.1 wording attributes the row-per-field shape to a published benchmark, but the benchmark does not cover list paths. This ADR closes that gap before the choice becomes hard to reverse.
- **Decision-relevant scenarios become permanent harness coverage.** Even if Option 1 is ratified, the list-heavy scenarios remain in PR-011a's output. Phase 2 (`@onDelete` cascade, LRU on lists) gets a baseline to regress against from day one.
- **Nested-list complexity is surfaced and budgeted, not discovered.** Option 2's depth strategy is identified now, when the cost of designing it is a paragraph in this ADR. If the decision had been made silently in favor of Option 2 without surfacing nesting, the discovery would land mid-implementation.
- **PR-012 gating criteria already accommodate this.** The 3.0-alpha tag is already gated on "no `regressed` verdict in the published dataset"; this ADR adds list scenarios to that dataset without changing the gating mechanic.

### Negative

- **Phase 1A timeline absorbs a small amount of additional scenario authoring.** PR-011a's estimate (~700 LoC) already includes Tier 1 + Tier 2 scenario coverage; the list-heavy additions are ~150–250 LoC of additional scenario code plus the supporting fixtures. Mitigation: scenario authoring is mechanical and parallelizable with other Phase 1A work; the perf plan §5.2 inline-PR pattern accommodates this without restructuring §8.
- **Two possible outcomes mean two possible implementation paths in Phase 1A.** If Option 2 wins, a new PR (PR-009b) lands the migration before PR-012; if Option 1 wins, no additional code is required. The agent and reviewer must hold both possibilities open until the benchmark data arrives. Mitigation: the decision rule above is mechanical; the additional PR (if needed) is ~400 LoC of well-scoped storage work, comparable to PR-010 in size.
- **Deferring the decision means PR-009's encoder remains in production-shape under uncertainty.** The encoder is correct and hardened; if Option 2 wins, parts of it are discarded. Mitigation: the discarded code is a localized JSON encoder path, not architecture; the cost of writing it (already paid) is recovered as test fixtures and as the Option 1 fallback if Option 2 turns out worse than expected at the eleventh hour.

### Neutral

- **No 2.x parity question.** 2.x has no list-storage strategy distinct from its records-blob-as-JSON layout; both options under evaluation are improvements over the 2.x shape. The 2.x baseline dataset (PR-004a, #980) does not measure list paths separately because the 2.x storage layer does not separate them.
- **The §7.1 wording will need a small editorial pass** once the decision is locked, regardless of outcome — to either (a) cite this ADR and remove the unsourced "JSON-encoded list" claim, or (b) describe the `list_items` table as the locked design.

## References

- [Engineering plan §7.1](../cache-rewrite-phase1-plan.md) — current `list_value TEXT` schema decision being scoped here
- [Engineering plan §7.4](../cache-rewrite-phase1-plan.md) — published performance gates (scalar paths only)
- [Perf plan §3.2, §3.3, §5.2](../cache-rewrite-phase1-perf.md) — Tier 2 / Tier 3 scenario design and the inline `feat(perf): add scenario` pattern
- [Execution plan §8 PR-011, PR-011a, PR-012](../cache-rewrite-phase1-execution.md) — perf-harness PRs that carry the new list-heavy scenarios and the 3.0-alpha tag gating
- [ADR 0001 — Major version bump](./0001-major-version-bump.md) — drop-and-rebuild migration policy that constrains the lock to "before PR-012"
- [ADR 0002 — Record abstraction](./0002-record-abstraction.md) — in-memory `CachedField` shape (independent of this ADR; both options round-trip cleanly to `CachedField`)
- [SQLite Performance Benchmarks (Confluence 1585152147)](https://apollographql.atlassian.net/wiki/spaces/ClientDev/pages/1585152147) — origin of the row-per-field shape; the source that does not cover list paths
- [PR-009 (#1001)](https://github.com/apollographql/apollo-ios-dev/pull/1001) — row-per-field CRUD implementation; review thread that surfaced the asymmetry
- [`SQLiteFieldEncoding.swift`](../../Sources/ApolloSQLite/SQLiteFieldEncoding.swift) — current JSON-encoded list-path implementation
