# ADR 0006 — List storage strategy: sibling table or in-place rows with `position`

- **Status:** Proposed — Option 2 (in-place rows with `position`) is the **leading candidate**; final lock before PR-012 (3.0-alpha tag) based on PR-011a list-heavy benchmark data
- **Date:** 2026-05-28
- **Phase 1 PR:** Out-of-stack docs follow-up to PR-009
- **Engineering plan reference:** [cache-rewrite-phase1-plan.md §7.1, §7.4](../cache-rewrite-phase1-plan.md)
- **Perf plan reference:** [cache-rewrite-phase1-perf.md](../cache-rewrite-phase1-perf.md) — Tier 3 scenario coverage

## Context

[ADR 0002](./0002-record-abstraction.md) settled the in-memory `Record` shape; engineering plan §7.1 settled the on-disk shape: one row per field, with per-type value columns (`int_value`, `string_value`, `float_value`, `bool_value`, `child_key_value`, `custom_scalar_value`) plus `list_value TEXT` for list-typed fields. Scalars land in their typed column; lists land as a JSON-encoded blob in `list_value`. This asymmetry was flagged in the PR-009 review: scalar fields get a typed, indexable column, but list elements collapse to a single opaque string.

The §7.1 choice traces to Zach's [SQLite Performance Benchmarks](https://apollographql.atlassian.net/wiki/spaces/ClientDev/pages/1585152147) (Confluence page 1585152147), the same source that motivates the row-per-field shape itself. The benchmark's published numbers — and the §7.4 performance gates derived from them — measure exact-key selects, type+selection-set selects, composite-PK updates, single-row inserts, and CTE-join sorts. None of those scenarios exercise list-heavy paths.

Separately, the cache is required to support **per-element queries against list-typed fields** — filtering and indexing list elements at the SQL level, observing changes to a specific list element via the watcher, and walking list elements as part of the Phase 2 `@onDelete` cascade. JSON-blob storage forbids all of these at the SQL layer (any operation requires loading and parsing the entire blob in Swift). This is a hard capability requirement, not a performance preference; it eliminates the JSON `list_value` shape from the option space regardless of how it benchmarks.

What remains is choosing between two row-per-element shapes. The benchmark gap from §7.1 still applies — neither shape has been measured against the other — and the lock happens against perf data before PR-012.

PR-009's encoder/decoder implements the JSON path end-to-end and hardens it (PR-009 review-findings commit: `JSONSerialization.isValidJSONObject` probe, `NSNull` round-trip, `$reference`-wrapper disambiguation, `sortedKeys` for stable on-disk bytes). That code is correct but addresses the rejected shape; both options below replace it.

## Decision

**Defer between the two row-per-element options below.** The ADR commits to:

1. Treating the §7.1 `list_value TEXT` shape as **rejected** on capability grounds (see Alternatives considered). The PR-009 JSON encoder/decoder is interim code that will be replaced before 3.0-alpha tags.
2. Naming **Option 2 (in-place rows with `position`)** as the leading candidate, on design-merit grounds. Final ratification still requires the PR-011a numbers.
3. Adding list-heavy scenarios to the PR-011 / PR-011a performance-measurement harness (see "Deciding evidence").
4. **Locking the decision before PR-012** — the 3.0-alpha tag. The lock happens by amending this ADR with a Status flip from *Proposed* to *Accepted* and a final §2 Decision paragraph naming the chosen option.

### Option 1 — Sibling `list_items` table

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
  PRIMARY KEY (cache_key, field_name, position),
  FOREIGN KEY (cache_key, field_name) REFERENCES records(cache_key, field_name) ON DELETE CASCADE
) WITHOUT ROWID;
```

Reads issue a second `SELECT … WHERE cache_key = ? AND field_name = ? ORDER BY position` for any list-typed field (or a `LEFT JOIN`). Nested lists (`[[Int]]`, `[[CacheReference]]`) require an explicit depth strategy — depth column, recursive `list_of_lists` table, or per-element `child_key_value` indirection to a record-shaped sub-list. The depth strategy is part of the ratification, not deferred separately.

### Option 2 — In-place rows with `position`; recurse via `child_key_value` for depth ≥ 2 (leading candidate)

Extend the records table's PK with a `position` column. Scalars use a sentinel `position = -1`; list elements use `position = 0..N-1`. List-element rows live in the same table as the parent record, at the same `cache_key`. Thanks to `WITHOUT ROWID` clustering, they are physically adjacent to the parent's scalar fields on disk.

```sql
CREATE TABLE IF NOT EXISTS records (
  cache_key            TEXT NOT NULL,
  field_name           TEXT NOT NULL,
  position             INTEGER NOT NULL DEFAULT -1,  -- -1 = scalar; 0..N-1 = list element
  int_value            INTEGER,
  string_value         TEXT,
  float_value          REAL,
  bool_value           INTEGER,
  child_key_value      TEXT,
  custom_scalar_value  TEXT,
  written_at           INTEGER NOT NULL,
  PRIMARY KEY (cache_key, field_name, position)
) WITHOUT ROWID;
```

The depth-1 case (`[Int]`, `[String]`, `[Friend]` — ~99% of GraphQL list-typed fields in practice) is handled entirely in-place: one `SELECT … WHERE cache_key = ?` returns scalar fields *and* list elements in the same result set, clustered together on disk. No JSON, no second table, no join.

Nested lists (`[[Int]]`, `[[CacheReference]]` — the rare case) recurse via the existing `CacheKey` indirection: an outer list's row holds a synthetic `child_key_value` (e.g., `User:1.tags[3]`) pointing to a sub-record, which itself uses the depth-1 layout for the inner list. This reuses the reference machinery the cache already has rather than introducing a new mechanism. Depth is bounded by the GraphQL schema, not unbounded — the executor walks a selection set whose shape is compiled in, so we never need recursive CTEs or "find all descendants" queries.

This is the industry-standard **adjacency-list-with-position** pattern applied to a domain where depth is bounded and known at codegen time. The heavier hierarchical-data patterns (nested set, closure table, materialized path) exist to answer queries we never ask.

## Alternatives considered

### JSON-encoded `list_value` (current §7.1 default — rejected)

Keep the row-per-field layout exactly as specified in engineering plan §7.1. Each list-typed field stores its elements as a JSON-encoded `TEXT` blob in `list_value`. Nested lists handle naturally via JSON's recursive structure.

- *Rejected because:* **list elements stored as a JSON blob cannot be queried at the SQL level.** Filtering a list by element value, indexing on element shape, watching for changes to a single element, and walking list elements during the Phase 2 `@onDelete` cascade all require loading the entire blob into Swift and parsing it — work proportional to list length on every operation, with no opportunity for SQLite's query planner to participate. The asymmetry with scalar fields (which get typed, indexable columns) is the surface symptom; the underlying problem is that JSON storage forecloses an entire class of capabilities the cache is required to support. No benchmark outcome rescues this option, because the constraint is capability rather than cost. The PR-009 encoder/decoder for this shape was correct, but it solves a problem we have decided not to keep.

## Trade-offs

The choice between Option 1 (sibling table) and Option 2 (in-place rows) is what the PR-011a numbers resolve. Both support per-element querying — the capability requirement that eliminated JSON — so the comparison reduces to read locality, schema surface, and the nested-list handling cost.

| Dimension | Option 1 (`list_items` table) | Option 2 (in-place `position` + indirection) |
|---|---|---|
| Read cost — depth 1 | Extra `SELECT` or join per list-typed field. | Same `SELECT` as the parent record (clustered via `WITHOUT ROWID`). |
| Read cost — depth ≥ 2 | Depends on the chosen depth strategy. Recursive `list_of_lists` table: another `SELECT`/join per nesting level. Depth column with self-join: planner-dependent. | One extra `SELECT` per outer element (the `child_key_value` indirection). |
| Write cost | N row UPSERTs per list; single-element edit is one UPSERT at `position`. | N row UPSERTs per list in the same table; single-element edit is one UPSERT at `position`. |
| Order preservation | Explicit `position INTEGER` column. | Explicit `position INTEGER` column; typed sort, no zero-padding. |
| Type symmetry with scalars | Symmetric within the separate table. | Symmetric within the same table. |
| Child-reference indexing (Phase 2 `@onDelete` cascade) | Each reference element is its own row in `list_items`; cascade walker must read from two tables. | Each reference element is its own row in `records`; existing cascade walker handles it without a second source. |
| Schema surface + impl effort | Two tables. New encoder, decoder, migration step, transactional contract for write atomicity. Depth strategy adds further design work. | One table with extended PK `(cache_key, field_name, position)` and `DEFAULT -1` sentinel. Position-aware reader/writer plus the depth ≥ 2 recursion path. PR-009's encoder is largely rewritten but the row-per-field harness stays. |

## Deciding evidence

The PR-011 / PR-011a perf-harness PRs are the right place to collect the missing data. Adding list-heavy scenarios there strengthens the 3.0-alpha published dataset against future regressions, independent of which option wins.

Scenarios to add (Tier 2 — `NormalizedCache` protocol level — and Tier 3 — direct SQLite operations):

| Scenario | Tier | Purpose |
|---|---|---|
| `read-record-with-list-of-N-scalars` (N ∈ {10, 100, 1000}) | 2, 3 | Read cost as list length grows; Option 2 clustered-row read vs Option 1 second `SELECT`/join |
| `read-record-with-list-of-N-references` (N ∈ {10, 100, 1000}) | 2, 3 | Reference-typed list cost; relevant to Phase 2 cascade walker |
| `write-list-of-N-scalars` (cold + warm) | 2, 3 | Full-list write cost; both options do N row UPSERTs, but to different tables |
| `write-list-of-N-references` (cold + warm) | 2, 3 | As above with reference elements |
| `mutate-element-at-position-K-in-list-of-N` | 2, 3 | Single-row UPSERT at `position`; both options should be close, deciding the floor |
| `read-record-with-nested-list-[[Int]]` (outer ∈ {10, 100}, inner ∈ {10, 100}) | 2, 3 | Quantifies Option 2's depth ≥ 2 indirection cost vs Option 1's depth strategy |
| `read-record-with-nested-list-[[CacheReference]]` (outer ∈ {10, 100}, inner ∈ {10, 100}) | 2, 3 | As above with the reference shape Phase 2 cares about |
| `filter-list-elements-by-typed-column` | 2 | Confirms the capability requirement is satisfied; both options should pass; included to lock in coverage |

Per perf plan §3, these add a new performance-relevant subsystem (list paths) that the existing scenarios do not cover; perf plan §5.2 already anticipates inline `feat(perf): add scenario for X` additions. The list scenarios land in PR-011a as part of the comprehensive Tier 1 / Tier 2 harness; the Tier 3 SQLite-level scenarios extend PR-011.

The decision rule for the lock:

- If Option 2's depth-1 reads are within the §7.4 envelope across all list lengths *and* the depth ≥ 2 indirection cost is bounded (≤ 2× of a comparable Option 1 depth-strategy read on the `[[Int]]` scenarios), **Option 2 is ratified.** A new PR (call it PR-009b) extends the PK, lands the position-aware reader/writer, and adds the depth ≥ 2 recursion.
- If Option 2's depth ≥ 2 indirection cost is unacceptably high *and* Option 1's chosen depth strategy is materially better on nested-list reads, **Option 1 is ratified.** PR-009b instead lands the sibling table plus its depth strategy.
- Edge cases — Option 2 wins single-table-locality but loses badly on nested-list reads, or any other split outcome — escalate to the reviewer per execution plan §6 trigger 8.

The lock is final by PR-012. After 3.0-alpha tags, changing the list-storage strategy would force a second drop-and-rebuild migration on existing 3.0-alpha installs — the same reason §7.1's `written_at` column is added in PR-008 instead of Phase 1C.

## Consequences

### Positive

- **Capability requirement is documented and locked.** Per-element queryability is now an explicit constraint in this ADR, not a tacit assumption. Any future reconsideration of the storage shape (Phase 2, Phase 3) starts from "must support per-element SQL queries" rather than relitigating the JSON shape.
- **Empirical grounding for the remaining choice.** §7.1 attributes the row-per-field shape to a published benchmark, but the benchmark does not cover list paths. This ADR closes that gap for the live decision (Option 1 vs Option 2) before the choice becomes hard to reverse.
- **The leading-candidate framing accelerates Phase 1A planning.** PR-009b can be scoped speculatively against Option 2 while the benchmarks run; if the data flips to Option 1, the scope swap is mechanical.
- **Decision-relevant scenarios become permanent harness coverage.** Whichever option lands, the list-heavy scenarios remain in PR-011a's output. Phase 2 (`@onDelete` cascade, LRU on lists) gets a baseline to regress against from day one.
- **Nested-list complexity is surfaced and budgeted, not discovered.** Option 2's depth ≥ 2 recursion path and Option 1's depth-strategy choice are identified now; if either had been discovered mid-implementation, it would have surfaced as scope creep on a code PR rather than a paragraph in this ADR.
- **PR-012 gating criteria already accommodate this.** The 3.0-alpha tag is already gated on "no `regressed` verdict in the published dataset"; this ADR adds list scenarios to that dataset without changing the gating mechanic.

### Negative

- **PR-009's encoder is now interim code.** The JSON-blob path will be replaced by PR-009b regardless of which option wins. The hardening work in the PR-009 review-findings commit (`NSNull`, `$reference`, sortedKeys, etc.) is mostly retained for the `custom_scalar_value` path, but the list-encoding branches are discarded. Mitigation: the discarded code is localized; tests for the JSON path become test fixtures for the new row-per-element encoder.
- **Phase 1A timeline absorbs additional scenario authoring.** PR-011a's estimate (~700 LoC) already includes Tier 1 + Tier 2 scenario coverage; the list-heavy additions are ~200–300 LoC of scenario code plus fixtures. Mitigation: scenario authoring is mechanical and parallelizable; perf plan §5.2 accommodates inline additions without restructuring §8.
- **Option 2's sentinel semantics add a small reader-side decoder cost.** Every `SELECT` against `records` returns scalar rows interleaved with list-element rows; the decoder must branch on `position = -1`. Mitigation: a single integer comparison per row; negligible vs Option 1's second-`SELECT` cost.

### Neutral

- **No 2.x parity question.** 2.x has no list-storage strategy distinct from its records-blob-as-JSON layout; both options under evaluation are improvements. The 2.x baseline dataset (PR-004a, #980) does not measure list paths separately because the 2.x storage layer does not separate them.
- **The §7.1 wording will need an editorial pass** once the decision is locked — to either (a) describe the `list_items` table as the locked design or (b) describe the extended PK with the `position` sentinel. The current "JSON-encoded list" claim is removed in either case.

## References

- [Engineering plan §7.1](../cache-rewrite-phase1-plan.md) — current `list_value TEXT` schema decision being replaced
- [Engineering plan §7.4](../cache-rewrite-phase1-plan.md) — published performance gates (scalar paths only)
- [Perf plan §3.2, §3.3, §5.2](../cache-rewrite-phase1-perf.md) — Tier 2 / Tier 3 scenario design and the inline `feat(perf): add scenario` pattern
- [Execution plan §8 PR-011, PR-011a, PR-012](../cache-rewrite-phase1-execution.md) — perf-harness PRs that carry the new list-heavy scenarios and the 3.0-alpha tag gating
- [ADR 0001 — Major version bump](./0001-major-version-bump.md) — drop-and-rebuild migration policy that constrains the lock to "before PR-012"
- [ADR 0002 — Record abstraction](./0002-record-abstraction.md) — in-memory `CachedField` shape (independent of this ADR; both options round-trip cleanly to `CachedField`)
- [SQLite Performance Benchmarks (Confluence 1585152147)](https://apollographql.atlassian.net/wiki/spaces/ClientDev/pages/1585152147) — origin of the row-per-field shape; the source that does not cover list paths
- [PR-009 (#1001)](https://github.com/apollographql/apollo-ios-dev/pull/1001) — row-per-field CRUD implementation; review thread that surfaced the asymmetry
- [`SQLiteFieldEncoding.swift`](../../Sources/ApolloSQLite/SQLiteFieldEncoding.swift) — current JSON-encoded list-path implementation (interim; replaced by PR-009b)
- Industry pattern reference for the Option 2 shape: adjacency-list-with-position, with depth bounded by the GraphQL schema rather than handled via closure table / nested set. See discussion of when to combine adjacency list with other models for hierarchical data — e.g., [Djellouli, *Storing Hierarchical Data in Relational Databases with SQL*](https://adamdjellouli.com/articles/databases_notes/03_sql/09_hierarchical_data).
