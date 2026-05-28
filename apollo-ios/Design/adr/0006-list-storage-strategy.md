# ADR 0006 — List storage strategy: JSON blob, sibling table, or in-place rows with `position`

- **Status:** Proposed — Option 3 (in-place rows with `position`) is the **leading candidate**; final lock before PR-012 (3.0-alpha tag) based on PR-011a list-heavy benchmark data
- **Date:** 2026-05-28
- **Phase 1 PR:** Out-of-stack docs follow-up to PR-009
- **Engineering plan reference:** [cache-rewrite-phase1-plan.md §7.1, §7.4](../cache-rewrite-phase1-plan.md)
- **Perf plan reference:** [cache-rewrite-phase1-perf.md](../cache-rewrite-phase1-perf.md) — Tier 3 scenario coverage

## Context

[ADR 0002](./0002-record-abstraction.md) settled the in-memory `Record` shape; engineering plan §7.1 settled the on-disk shape: one row per field, with per-type value columns (`int_value`, `string_value`, `float_value`, `bool_value`, `child_key_value`, `custom_scalar_value`) plus `list_value TEXT` for list-typed fields. Scalars land in their typed column; lists land as a JSON-encoded blob in `list_value`. This asymmetry was flagged in the PR-009 review: scalar fields get a typed, indexable column, but list elements collapse to a single opaque string.

The §7.1 choice traces to Zach's [SQLite Performance Benchmarks](https://apollographql.atlassian.net/wiki/spaces/ClientDev/pages/1585152147) (Confluence page 1585152147), the same source that motivates the row-per-field shape itself. The benchmark's published numbers — and the §7.4 performance gates derived from them — measure exact-key selects, type+selection-set selects, composite-PK updates, single-row inserts, and CTE-join sorts. None of those scenarios exercise list-heavy paths. There is no empirical evidence that JSON-encoded `list_value` is the optimal choice for list-typed fields specifically; the design inherits the choice without having measured the alternative.

PR-009's encoder/decoder already implements the JSON path end-to-end and hardens it (PR-009 review-findings commit: `JSONSerialization.isValidJSONObject` probe, `NSNull` round-trip, `$reference`-wrapper disambiguation, `sortedKeys` for stable on-disk bytes). The implementation is real; what is missing is the *evidence* that this implementation is the right one.

This ADR scopes the question and the evidence-collection plan that resolves it.

## Decision

**Defer.** The choice between the three options below is not made by this ADR. The ADR commits to:

1. Treating the §7.1 `list_value TEXT` shape as a **provisional default**, not a ratified choice, until list-heavy benchmark data exists.
2. Naming **Option 3 (in-place rows with `position`)** as the leading candidate, on design-merit grounds. Final ratification still requires the PR-011a numbers.
3. Adding list-heavy scenarios to the PR-011 / PR-011a performance-measurement harness (see §4, "Deciding evidence").
4. **Locking the decision before PR-012** — the 3.0-alpha tag. The lock happens by amending this ADR with a Status flip from *Proposed* to *Accepted* and a final §2 Decision paragraph naming the chosen option.

### Option 1 — Ratify JSON-encoded `list_value` (current §7.1 shape)

Each list-typed field stores its elements as a JSON-encoded `TEXT` blob in `list_value`. Nested lists (`[[Int]]`, `[[CacheReference]]`) are handled naturally by JSON's recursive structure — no schema change required.

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
  PRIMARY KEY (cache_key, field_name, position),
  FOREIGN KEY (cache_key, field_name) REFERENCES records(cache_key, field_name) ON DELETE CASCADE
) WITHOUT ROWID;
```

Reads issue a second `SELECT … WHERE cache_key = ? AND field_name = ? ORDER BY position` for any list-typed field (or a `LEFT JOIN`). Nested lists require an explicit depth strategy — depth column, recursive `list_of_lists` table, or JSON fallback above depth 1.

### Option 3 — In-place rows with `position`; recurse via `child_key_value` for depth ≥ 2 (leading candidate)

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

## Trade-offs

| Dimension | Option 1 (JSON `list_value`) | Option 2 (`list_items` table) | Option 3 (in-place `position` + indirection) |
|---|---|---|---|
| Read cost | One row, but `JSONSerialization` decode cost grows with list length. | Extra `SELECT` or join per list-typed field. | Same `SELECT` as the parent record (clustered via `WITHOUT ROWID`); depth ≥ 2 adds one `SELECT` per outer element. |
| Write cost | One row UPSERT for full list; full re-encode for any element edit. | N row UPSERTs; single-element edit is one UPSERT at `position`. | N row UPSERTs in the same table; single-element edit is one UPSERT at `position`. |
| Order preservation | Implicit (JSON arrays are ordered). | Explicit `position INTEGER` column. | Explicit `position INTEGER` column; typed sort, no zero-padding. |
| Type symmetry with scalars | Asymmetric — scalars typed, list elements collapse to JSON. | Symmetric within the separate table. | Symmetric within the same table. |
| Nested lists `[[T]]` | Native — JSON nests recursively. | Requires depth strategy (depth column, `list_of_lists` table, or JSON fallback). | Recurses via `child_key_value` to a synthetic sub-record; reuses existing reference indirection; bounded by GraphQL schema depth. |
| Child-reference indexing (Phase 2 `@onDelete` cascade) | Impossible without parsing JSON to find children. | Each reference element is its own row. | Each reference element is its own row in the same table; existing cascade walker handles it without a second source. |
| Schema surface + impl effort | One table. Already implemented (PR-009 + review-findings). | Two tables. New encoder, decoder, migration step, transactional contract for write atomicity. | One table with extended PK `(cache_key, field_name, position)` and `DEFAULT -1` sentinel. Position-aware reader/writer plus the depth ≥ 2 recursion path. PR-009's encoder retains most of its current shape. |

## Deciding evidence

The PR-011 / PR-011a perf-harness PRs are the right place to collect the missing data. Adding list-heavy scenarios there strengthens the 3.0-alpha published dataset against future regressions, independent of this ADR's outcome.

Scenarios to add (Tier 2 — `NormalizedCache` protocol level — and Tier 3 — direct SQLite operations):

| Scenario | Tier | Purpose |
|---|---|---|
| `read-record-with-list-of-N-scalars` (N ∈ {10, 100, 1000}) | 2, 3 | Read cost as list length grows; tests Option 3's clustered-row read |
| `read-record-with-list-of-N-references` (N ∈ {10, 100, 1000}) | 2, 3 | Reference-typed list cost; relevant to Phase 2 cascade |
| `write-list-of-N-scalars` (cold + warm) | 2, 3 | Full-list write cost; the per-row vs single-row write head-to-head |
| `write-list-of-N-references` (cold + warm) | 2, 3 | As above with reference elements |
| `mutate-single-element-in-list-of-N` (N ∈ {10, 100, 1000}) | 2 | Pivotal — Option 1 re-encodes; Options 2 + 3 each UPSERT one row |
| `mutate-element-at-position-K-in-list-of-N` | 2 | Direct measurement of Option 3's `UPDATE … WHERE position = ?` path vs Option 1's full-JSON rewrite |
| `read-record-with-nested-list-[[Int]]` (outer ∈ {10, 100}, inner ∈ {10, 100}) | 2, 3 | Quantifies Option 3's depth ≥ 2 indirection cost vs Option 1's nested-JSON decode |
| `read-record-with-nested-list-[[CacheReference]]` (outer ∈ {10, 100}, inner ∈ {10, 100}) | 2, 3 | As above with the reference shape Phase 2 cares about |

Per perf plan §3, these add a new performance-relevant subsystem (list paths) that the existing scenarios do not cover; perf plan §5.2 already anticipates inline `feat(perf): add scenario for X` additions. The list scenarios land in PR-011a as part of the comprehensive Tier 1 / Tier 2 harness; the Tier 3 SQLite-level scenarios extend PR-011.

The decision rule for the lock:

- If Option 3's depth-1 reads are within the §7.4 envelope across all list lengths *and* `mutate-element-at-position-K` shows a material speedup over Option 1 (>2× on N=100, say) *and* the depth ≥ 2 indirection cost is bounded (≤ 2× of Option 1's nested-JSON decode on the `[[Int]]` scenarios), **Option 3 is ratified.** A new PR (call it PR-009b) extends the PK and lands the position-aware reader/writer before PR-012. The depth ≥ 2 recursion is added in the same PR.
- If Option 1 is competitive on every scenario and the asymmetry's only material cost is conceptual, **Option 1 is ratified** as the path-of-least-change. The asymmetry is accepted; Phase 2 `@onDelete` cascade pays its own per-element JSON parse cost when the time comes.
- Option 2 is ratified only if Option 3's depth ≥ 2 indirection cost is unacceptably high *and* Option 1's nested-JSON decode is also unacceptably high — a narrow case. In that scenario, PR-009b instead lands the sibling table.
- Edge cases — Option 3 wins single-element edit but loses bulk reads, or any other split outcome — escalate to the reviewer per execution plan §6 trigger 8.

The lock is final by PR-012. After 3.0-alpha tags, changing the list-storage strategy would force a second drop-and-rebuild migration on existing 3.0-alpha installs — the same reason §7.1's `written_at` column is added in PR-008 instead of Phase 1C.

## Consequences

### Positive

- **Empirical grounding for an unmeasured choice.** §7.1 attributes the row-per-field shape to a published benchmark, but the benchmark does not cover list paths. This ADR closes that gap before the choice becomes hard to reverse.
- **The leading-candidate framing accelerates Phase 1A planning.** If Option 3 wins the benchmark, PR-009b is the scoped follow-up; the agent and reviewer can prepare it speculatively without committing.
- **Decision-relevant scenarios become permanent harness coverage.** Whichever option lands, the list-heavy scenarios remain in PR-011a's output. Phase 2 (`@onDelete` cascade, LRU on lists) gets a baseline to regress against from day one.
- **Nested-list complexity is surfaced and budgeted, not discovered.** Option 3's depth ≥ 2 recursion path is identified now; if it had been discovered mid-implementation, it would have surfaced as scope creep on a code PR rather than a paragraph in this ADR.
- **PR-012 gating criteria already accommodate this.** The 3.0-alpha tag is already gated on "no `regressed` verdict in the published dataset"; this ADR adds list scenarios to that dataset without changing the gating mechanic.

### Negative

- **Phase 1A timeline absorbs additional scenario authoring.** PR-011a's estimate (~700 LoC) already includes Tier 1 + Tier 2 scenario coverage; the list-heavy additions are ~200–300 LoC of scenario code plus fixtures. Mitigation: scenario authoring is mechanical and parallelizable; perf plan §5.2 accommodates inline additions without restructuring §8.
- **Three possible outcomes mean three possible implementation paths.** The agent and reviewer must hold all three open until the benchmark data arrives. Mitigation: the decision rule above is mechanical; Option 3's PR-009b (the expected outcome) is ~300–400 LoC, comparable to PR-010.
- **Option 3 sentinel semantics add a small reader-side decoder cost.** Every `SELECT` against the records table returns scalar rows interleaved with list-element rows; the decoder must branch on `position = -1`. Mitigation: a single integer comparison per row; negligible vs the JSON-decode cost of Option 1 and the second-`SELECT` cost of Option 2.

### Neutral

- **No 2.x parity question.** 2.x has no list-storage strategy distinct from its records-blob-as-JSON layout; all three options under evaluation are improvements. The 2.x baseline dataset (PR-004a, #980) does not measure list paths separately because the 2.x storage layer does not separate them.
- **The §7.1 wording will need a small editorial pass** once the decision is locked — to either (a) cite this ADR and remove the unsourced "JSON-encoded list" claim, (b) describe the `list_items` table as the locked design, or (c) describe the extended PK with the `position` sentinel.

## References

- [Engineering plan §7.1](../cache-rewrite-phase1-plan.md) — current `list_value TEXT` schema decision being scoped here
- [Engineering plan §7.4](../cache-rewrite-phase1-plan.md) — published performance gates (scalar paths only)
- [Perf plan §3.2, §3.3, §5.2](../cache-rewrite-phase1-perf.md) — Tier 2 / Tier 3 scenario design and the inline `feat(perf): add scenario` pattern
- [Execution plan §8 PR-011, PR-011a, PR-012](../cache-rewrite-phase1-execution.md) — perf-harness PRs that carry the new list-heavy scenarios and the 3.0-alpha tag gating
- [ADR 0001 — Major version bump](./0001-major-version-bump.md) — drop-and-rebuild migration policy that constrains the lock to "before PR-012"
- [ADR 0002 — Record abstraction](./0002-record-abstraction.md) — in-memory `CachedField` shape (independent of this ADR; all three options round-trip cleanly to `CachedField`)
- [SQLite Performance Benchmarks (Confluence 1585152147)](https://apollographql.atlassian.net/wiki/spaces/ClientDev/pages/1585152147) — origin of the row-per-field shape; the source that does not cover list paths
- [PR-009 (#1001)](https://github.com/apollographql/apollo-ios-dev/pull/1001) — row-per-field CRUD implementation; review thread that surfaced the asymmetry
- [`SQLiteFieldEncoding.swift`](../../Sources/ApolloSQLite/SQLiteFieldEncoding.swift) — current JSON-encoded list-path implementation
- Industry pattern reference for the Option 3 shape: adjacency-list-with-position, with depth bounded by the GraphQL schema rather than handled via closure table / nested set. See discussion of when to combine adjacency list with other models for hierarchical data — e.g., [Djellouli, *Storing Hierarchical Data in Relational Databases with SQL*](https://adamdjellouli.com/articles/databases_notes/03_sql/09_hierarchical_data).
