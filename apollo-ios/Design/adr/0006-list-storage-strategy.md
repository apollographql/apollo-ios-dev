# ADR 0006 — List storage: in-place row-per-element with `position`

- **Status:** Accepted
- **Date:** 2026-05-28
- **Phase 1 PR:** Out-of-stack docs follow-up to PR-009. Schema implementation lands as part of PR-009's amended scope (see "Implementation impact"); engineering plan §7.1/§7.2 and execution plan §8 are revised in follow-up PRs.
- **Engineering plan reference:** [cache-rewrite-phase1-plan.md §7.1, §7.2](../cache-rewrite-phase1-plan.md) — to be rewritten per this ADR

## Context

[ADR 0002](./0002-record-abstraction.md) settled the in-memory `Record` shape; engineering plan §7.1 settled the on-disk shape as one row per field, with per-type value columns (`int_value`, `string_value`, `float_value`, `bool_value`, `child_key_value`, `custom_scalar_value`) plus `list_value TEXT` for list-typed fields. Scalars land in their typed column; lists land as a JSON-encoded blob.

The PR-009 review flagged the asymmetry: scalar fields get a typed, indexable column, but list elements collapse to a single opaque string. The §7.1 choice traces to Zach's [SQLite Performance Benchmarks](https://apollographql.atlassian.net/wiki/spaces/ClientDev/pages/1585152147) (Confluence 1585152147), but the benchmark measures only exact-key selects, type+selection-set selects, composite-PK updates, single-row inserts, and CTE-join sorts — no list-heavy paths. The JSON shape was inherited without measurement.

Separately, the cache must support **per-element queries against list-typed fields**: filtering and indexing list elements at the SQL level, watcher observation of single-element changes, and walking list elements during the Phase 2 `@onDelete` cascade. JSON storage forecloses all of these — every per-element operation requires loading and parsing the entire blob in Swift, with no opportunity for SQLite's query planner to participate. This is a capability constraint, not a performance preference.

The capability requirement eliminates JSON from the option space. The remaining choice — between an in-place row-per-element layout and a sibling `list_items` table — decides on design merit. The in-place layout dominates on every dimension that matters; the sibling table only adds indirection and surface area. See "Alternatives considered."

## Decision

**Each list element becomes its own row in the `records` table, addressed by an extended primary key.** A `position` column joins `cache_key` and `field_name` in the PK; scalars use the sentinel `position = -1`, and list elements use `position = 0..N-1`.

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

The `list_value TEXT` column from the §7.1 shape is removed.

**Depth-1 lists** (`[Int]`, `[String]`, `[Friend]` — ~99% of GraphQL list-typed fields in practice) are handled entirely in-place. List-element rows live at the same `cache_key` as the parent record's scalar fields; `WITHOUT ROWID` clustering keeps them physically adjacent on disk. One `SELECT … WHERE cache_key = ?` returns scalar fields and list elements together in the same result set.

**Nested lists** (`[[Int]]`, `[[CacheReference]]` — the rare case) recurse via the existing `CacheKey` indirection. An outer list's row holds a synthetic `child_key_value` (e.g., `User:1.tags[3]`) pointing to a sub-record that itself uses the depth-1 layout. This reuses the reference machinery the cache already has rather than introducing a new mechanism. Depth is bounded by the GraphQL schema, known at codegen time, so the executor never needs recursive CTEs or "find all descendants" queries. This is the industry-standard **adjacency-list-with-position** pattern applied to a domain where depth is bounded.

### Implementation impact

The current §7.1 DDL (with `list_value TEXT`) was landed in PR-008 (#1000, merged into the plan branch). The new DDL replaces it. The migration cost is zero on existing 3.0-alpha installs because **3.0-alpha has not tagged** — the §7.1 schema has only ever existed on the long-lived plan branch and in development databases. The drop-and-rebuild path on first 3.0 launch (per [ADR 0001](./0001-major-version-bump.md)) carries this ADR's schema, not the rejected one.

PR-009 (#1001, open) implemented row-per-field CRUD against the old `list_value` shape. Its scope is amended:
- The PK extension and `position` sentinel land as part of PR-009 (or a follow-up PR-009b, depending on review preference).
- The JSON list-encoding branches in `SQLiteFieldEncoding.swift` are replaced with position-aware row writers.
- The decoder's row-grouping logic gets a `position = -1` branch for scalar rows and a `position >= 0` branch that accumulates ordered list elements.
- The depth ≥ 2 recursion path adds a small `CacheKey` factory for synthetic sub-record keys.

The PR-009 review-findings hardening (`NSNull` round-trip, `$reference`-wrapper disambiguation, `sortedKeys`, `JSONSerialization.isValidJSONObject` probe) is retained where it applies to the `custom_scalar_value` path. The list-encoding branches are discarded.

Engineering plan §7.1 (DDL) and §7.2 (operations) are rewritten in a separate follow-up doc PR to match this ADR. Execution plan §8 is amended in the same follow-up to reflect the PR-009 scope change and any new PR slots that result.

The performance-harness PRs (PR-011, PR-011a) still receive the list-heavy scenarios discussed during this ADR's drafting — `read-record-with-list-of-N`, `write-list-of-N`, `mutate-element-at-position-K-in-list-of-N`, the nested `[[T]]` reads, and `filter-list-elements-by-typed-column` — but as permanent regression coverage of the chosen design, not as decision-gating evidence.

## Alternatives considered

### A. JSON-encoded `list_value` (the §7.1 default)

Each list-typed field stores its elements as a JSON-encoded `TEXT` blob in `list_value`. Nested lists handle naturally via JSON's recursive structure.

- *Rejected because:* **list elements stored as a JSON blob cannot be queried at the SQL level.** Filtering by element value, indexing on element shape, single-element watcher observation, and the Phase 2 `@onDelete` cascade walk all require loading and parsing the entire blob in Swift — work proportional to list length on every operation, with no opportunity for SQLite's query planner to participate. The asymmetry with scalar fields (typed, indexable columns) is the surface symptom; the underlying problem is that JSON storage forecloses an entire class of capabilities the cache is required to support. No benchmark outcome rescues this option because the constraint is capability rather than cost.

### B. Sibling `list_items` table

Lists move to a second table:

```sql
CREATE TABLE IF NOT EXISTS list_items (
  cache_key TEXT NOT NULL, field_name TEXT NOT NULL, position INTEGER NOT NULL,
  int_value INTEGER, string_value TEXT, float_value REAL, bool_value INTEGER,
  child_key_value TEXT, custom_scalar_value TEXT,
  PRIMARY KEY (cache_key, field_name, position),
  FOREIGN KEY (cache_key, field_name) REFERENCES records(cache_key, field_name) ON DELETE CASCADE
) WITHOUT ROWID;
```

Reads issue a second `SELECT` or `LEFT JOIN` for any list-typed field. Nested lists require an explicit depth strategy — depth column, recursive `list_of_lists` table, or per-element indirection.

- *Rejected because:* the chosen layout dominates on every dimension. **Read locality:** the chosen layout's list-element rows are physically clustered with their parent record's scalar rows via `WITHOUT ROWID`; the sibling-table layout requires a second `SELECT` or join regardless of list size. **Schema surface:** the chosen layout is one table; the sibling table doubles the migration surface for every future schema change. **Nested lists:** the chosen layout reuses the `CacheKey` indirection the cache already has; the sibling table requires a new depth strategy with no existing mechanism to lean on. **Phase 2 `@onDelete` cascade:** the chosen layout's cascade walker reads from one source; the sibling-table walker reads from two. There is no scenario where the second table produces a capability or performance advantage the chosen layout lacks. Even hypothetical edge cases (e.g., wildly disproportionate list-vs-scalar sizes biasing index pressure) are bounded by `WITHOUT ROWID` clustering in the chosen layout.

## Consequences

### Positive

- **Per-element queries are SQL-native.** Filtering, indexing, observing changes, and cascade-walking list elements all happen at the storage layer. No JSON parsing on hot paths.
- **Read locality wins for the common case.** `WITHOUT ROWID` clusters list-element rows next to their parent's scalar rows. A single record read returns the entire record — scalars and lists — in one query, with rows arriving contiguous in the result set.
- **One table, one migration surface.** Every future schema change (Phase 2 LRU `lastAccessedAt`, `@onDelete` cascade fields, additional typed columns) touches `records` only. The sibling-table alternative would have doubled the migration burden.
- **Nested lists reuse existing reference indirection.** No new mechanism for depth ≥ 2; `child_key_value` to a synthetic sub-record is just another use of the indirection the cache already has for object references.
- **PR-009's row-per-field harness is preserved.** The CRUD infrastructure landed in PR-009 (#1001) — query construction, transaction handling, result-row grouping — extends naturally to position-keyed rows. Only the encoder/decoder branches for list values change.

### Negative

- **PR-009's JSON list-encoding paths are interim code that gets replaced.** The hardening work in the PR-009 review-findings commit is mostly retained for the `custom_scalar_value` path, but the list-encoding branches in `SQLiteFieldEncoding.swift` are discarded. Mitigation: the discarded surface is localized; existing tests of those paths become test fixtures for the new row-per-element encoder.
- **Decoder branches on the sentinel.** Every `SELECT` against `records` returns scalar rows interleaved with list-element rows; the decoder must branch on `position = -1` for every row. Mitigation: a single integer comparison per row, negligible against the I/O cost of the underlying query.
- **Synthetic-key naming convention must be collision-safe.** The depth ≥ 2 indirection produces keys like `User:1.tags[3]`. The naming convention must be guaranteed not to collide with legitimate cache keys produced by the schema's key-field resolution. Mitigation: the `.field[N]` suffix form has no legitimate use in GraphQL field names, and the brackets are already part of cache-key syntax; a reserved-character audit lands with PR-009.
- **Engineering plan §7.1, §7.2 and execution plan §8 need follow-up doc updates** to match this ADR. Mitigation: those updates are mechanical and land as a single follow-up doc PR; this ADR is the source of truth in the meantime.

### Neutral

- **The PR-011 / PR-011a list-heavy scenarios still get added** — but as permanent regression coverage, not as decision-gating evidence. Tier 3 `read-record-with-list-of-N`, `write-list-of-N`, `mutate-element-at-position-K`, the nested-list scenarios, and `filter-list-elements-by-typed-column` (capability-coverage) all land in PR-011a's standing output.
- **The 2.x baseline dataset (PR-004a, #980) does not measure list paths separately** because the 2.x storage layer does not separate them. The alpha-vs-2.x comparison reports list-path numbers as new data without a 2.x baseline; this is documented in the comparison reporter's output (per perf plan §5).
- **3.0-alpha tag gating is unaffected.** The list-storage shape is no longer a separate "decision lock before PR-012" item; PR-012's existing gating (SQLite performance gates + no `regressed` verdict in the published dataset) covers regression detection against the chosen layout going forward.

## References

- [Engineering plan §7.1, §7.2](../cache-rewrite-phase1-plan.md) — DDL and operations (to be rewritten per this ADR)
- [Engineering plan §7.4](../cache-rewrite-phase1-plan.md) — published performance gates (unchanged)
- [Perf plan §3.2, §3.3, §5.2](../cache-rewrite-phase1-perf.md) — Tier 2 / Tier 3 scenario design and the inline `feat(perf): add scenario` pattern (used for the list-heavy scenarios as permanent coverage)
- [Execution plan §8](../cache-rewrite-phase1-execution.md) — PR list (PR-009 scope amended; PR list updated in follow-up)
- [ADR 0001 — Major version bump](./0001-major-version-bump.md) — drop-and-rebuild migration policy that absorbs the schema change at zero cost while 3.0-alpha is untagged
- [ADR 0002 — Record abstraction](./0002-record-abstraction.md) — in-memory `CachedField` shape; this ADR is the on-disk counterpart for list-typed fields
- [SQLite Performance Benchmarks (Confluence 1585152147)](https://apollographql.atlassian.net/wiki/spaces/ClientDev/pages/1585152147) — origin of the row-per-field shape; the source that does not cover list paths
- [PR-009 (#1001)](https://github.com/apollographql/apollo-ios-dev/pull/1001) — row-per-field CRUD implementation; scope amended per this ADR
- [`SQLiteFieldEncoding.swift`](../../Sources/ApolloSQLite/SQLiteFieldEncoding.swift) — encoder/decoder file affected by the schema change
- Industry pattern reference: adjacency-list-with-position, with depth bounded by the GraphQL schema rather than handled via closure table / nested set. See [Djellouli, *Storing Hierarchical Data in Relational Databases with SQL*](https://adamdjellouli.com/articles/databases_notes/03_sql/09_hierarchical_data) for the general pattern.
